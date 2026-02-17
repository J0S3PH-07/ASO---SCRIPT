#!/bin/bash

# ==============================================================================
# Script: alta_massiva.sh
# Descripción: Script autónomo de creación masiva de usuarios en OpenLDAP.
# Requisitos: 
#   - Conexión a ldap://ldap-server
#   - Detección automática de separador CSV (auto-detect , o ;)
#   - Limpieza robusta de datos (comillas, espacios)
#   - Creación automática de OUs inexistentes
#   - Atributos estándar: inetOrgPerson, posixAccount, shadowAccount
# ==============================================================================

# ==============================================================================
# CONFIGURACIÓN
# ==============================================================================
LDAP_SERVER="ldap://ldap-server"           # Contenedor LDAP
LDAP_BASE_DN="dc=tecnosolutions,dc=com"    # Dominio
LDAP_BIND_DN="cn=admin,$LDAP_BASE_DN"      # Admin DN
LDAP_BIND_PW="admin"                       # Admin Password

INPUT_FILE="empleados.csv"
LOG_FILE="alta_usuaris.log"

# ==============================================================================
# FUNCIONES
# ==============================================================================

log() {
    local TYPE=$1
    local MSG=$2
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] [$TYPE] $MSG" | tee -a "$LOG_FILE"
}

normalize() {
    # Convierte a minúsculas, quita acentos, quita espacios
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[áàäâ]/a/g;s/[éèëê]/e/g;s/[íìïî]/i/g;s/[óòöô]/o/g;s/[úùüû]/u/g;s/ñ/n/g' | tr -d ' '
}

clean_field() {
    # Elimina comillas dobles al inicio/final y espacios en blanco al inicio/final
    echo "$1" | sed 's/^"//;s/"$//' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

check_ou_exists() {
    local OU_NAME=$1
    # Búsqueda silenciosa
    ldapsearch -x -H "$LDAP_SERVER" -b "$LDAP_BASE_DN" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" "(ou=$OU_NAME)" > /dev/null 2>&1
    return $?
}

create_ou() {
    local OU_NAME=$1
    local OU_DN="ou=$OU_NAME,$LDAP_BASE_DN"

    local LDIF=$(cat <<EOF
dn: $OU_DN
objectClass: organizationalUnit
ou: $OU_NAME
EOF
)
    echo "$LDIF" | ldapadd -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" > /dev/null 2>&1
}

# ==============================================================================
# INICIO
# ==============================================================================

# 1. Verificar archivo
if [ ! -f "$INPUT_FILE" ]; then
    log "CRITICAL" "No se encuentra el archivo CSV: $INPUT_FILE"
    exit 1
fi

# 2. Detectar separador
FIRST_LINE=$(head -n 1 "$INPUT_FILE")
if [[ "$FIRST_LINE" == *";"* ]]; then
    SEP=";"
    log "INFO" "Separador detectado: Punto y coma (;)"
else
    SEP=","
    log "INFO" "Separador detectado: Coma (,)"
fi

log "INFO" "Iniciando alta masiva..."

# 3. Procesar CSV línea a línea (saltando cabecera)
tail -n +2 "$INPUT_FILE" | while IFS="$SEP" read -r RAW_NOM RAW_COGNOM RAW_DEPARTAMENT RAW_PASSWORD; do
    
    # Limpieza básica de la línea (Windows CR)
    RAW_NOM=$(echo "$RAW_NOM" | tr -d '\r')
    RAW_COGNOM=$(echo "$RAW_COGNOM" | tr -d '\r')
    RAW_DEPARTAMENT=$(echo "$RAW_DEPARTAMENT" | tr -d '\r')
    RAW_PASSWORD=$(echo "$RAW_PASSWORD" | tr -d '\r')

    # Limpieza robusta de campos
    NOM=$(clean_field "$RAW_NOM")
    COGNOM=$(clean_field "$RAW_COGNOM")
    DEPARTAMENT=$(clean_field "$RAW_DEPARTAMENT")
    PASSWORD=$(clean_field "$RAW_PASSWORD")

    # Saltar líneas vacías
    if [[ -z "$NOM" || -z "$COGNOM" || -z "$DEPARTAMENT" ]]; then
        continue
    fi

    # 4. Gestión de OU (Unidad Organizativa)
    check_ou_exists "$DEPARTAMENT"
    if [ $? -ne 0 ]; then
        log "INFO" "OU '$DEPARTAMENT' no existe. Creando..."
        create_ou "$DEPARTAMENT"
        if [ $? -eq 0 ]; then
            log "SUCCESS" "OU '$DEPARTAMENT' creada."
            sleep 1 # Espera de seguridad para propagación
        else
            log "ERROR" "Fallo crítico al crear OU '$DEPARTAMENT'. Saltando usuario $NOM."
            continue
        fi
    fi

    # 5. Generar datos de usuario
    CLEAN_NOM=$(normalize "$NOM")
    CLEAN_COGNOM=$(normalize "$COGNOM")
    UID_USER="${CLEAN_NOM}${CLEAN_COGNOM}"
    USER_DN="uid=$UID_USER,ou=$DEPARTAMENT,$LDAP_BASE_DN"
    UID_NUMBER=$(shuf -i 10000-60000 -n 1)

    # 6. Generar LDIF
    LDIF_USER=$(cat <<EOF
dn: $USER_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: $NOM $COGNOM
sn: $COGNOM
uid: $UID_USER
userPassword: $PASSWORD
gidNumber: 1000
uidNumber: $UID_NUMBER
homeDirectory: /home/$UID_USER
loginShell: /bin/bash
EOF
)

    # 7. Inyectar usuario
    echo "$LDIF_USER" | ldapadd -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log "SUCCESS" "Usuario creado: $UID_USER ($DEPARTAMENT)"
    else
        # Verificamos si ya existe para dar un mensaje más claro
        ldapsearch -x -H "$LDAP_SERVER" -b "$LDAP_BASE_DN" "(uid=$UID_USER)" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log "WARN" "El usuario $UID_USER ya existe. Omitido."
        else
            log "ERROR" "Fallo al crear usuario $UID_USER. Revisa conexión o permisos."
        fi
    fi

done

log "INFO" "Proceso finalizado."
