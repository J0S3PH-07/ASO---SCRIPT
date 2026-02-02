#!/bin/bash

# ==============================================================================
# Script: alta_massiva.sh
# Misión: Automatización de altas de usuarios en LDAP para Tecnosolutions.
# Requisitos: 
#   - Normalización de UIDs.
#   - Creación automática de OUs si no existen.
#   - Generación e inyección de LDIF.
#   - Logging detallado.
# ==============================================================================

# ==============================================================================
# CONFIGURACIÓN DEL ENTORNO
# ==============================================================================
LDAP_SERVER="ldap://openldap"              # Nombre del servicio en docker-compose
LDAP_BASE_DN="dc=tecnosolutions,dc=com"    # Dominio de la empresa
LDAP_BIND_DN="cn=admin,$LDAP_BASE_DN"      # Usuario Admin
LDAP_BIND_PW="admin"                       # Contraseña Admin

INPUT_FILE="usuaris.csv"
LOG_FILE="alta_usuaris.log"

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================

# Loguear mensajes en pantalla y archivo
log() {
    local TYPE=$1
    local MSG=$2
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] [$TYPE] $MSG" | tee -a "$LOG_FILE"
}

# Normalizar texto (minúsculas, sin acentos, sin espacios)
normalize() {
    echo "$1" | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[áàäâ]/a/g;s/[éèëê]/e/g;s/[íìïî]/i/g;s/[óòöô]/o/g;s/[úùüû]/u/g;s/ñ/n/g' | \
    tr -d ' '
}

# Comprobar si una OU existe, y si no, crearla
check_and_create_ou() {
    local OU_NAME=$1
    local OU_DN="ou=$OU_NAME,$LDAP_BASE_DN"

    # Buscamos la OU. -b especifica la base de búsqueda, -s base busca solo en ese nivel.
    # LDAP_SERVER usamos la variable. Si falla la búsqueda es que no existe (o error conexión).
    ldapsearch -x -H "$LDAP_SERVER" -b "$LDAP_BASE_DN" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" "(ou=$OU_NAME)" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        log "INFO" "La Unidad Organizativa '$OU_NAME' no existe. Creando..."
        
        # LDIF para la nueva OU
        local LDIF_OU=$(cat <<EOF
dn: $OU_DN
objectClass: organizationalUnit
ou: $OU_NAME
EOF
)
        echo "$LDIF_OU" | ldapadd -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log "SUCCESS" "OU '$OU_NAME' creada correctamente."
        else
            log "ERROR" "Fallo al crear la OU '$OU_NAME'. No se podrán crear usuarios en ella."
            return 1
        fi
    fi
    return 0
}

# ==============================================================================
# LÓGICA PRINCIPAL
# ==============================================================================

# 1. Verificación inicial
if [ ! -f "$INPUT_FILE" ]; then
    log "CRITICAL" "El archivo $INPUT_FILE no existe."
    exit 1
fi

log "INFO" "Iniciando script de alta masiva para Tecnosolutions..."

# 2. Procesamiento del CSV
# tail -n +2 salta la cabecera.
tail -n +2 "$INPUT_FILE" | while IFS=, read -r NOM COGNOM DEPARTAMENT CONTRASENYA; do
    
    # Limpieza de retorno de carro (por si el CSV viene de Windows)
    NOM=$(echo "$NOM" | tr -d '\r')
    COGNOM=$(echo "$COGNOM" | tr -d '\r')
    DEPARTAMENT=$(echo "$DEPARTAMENT" | tr -d '\r')
    CONTRASENYA=$(echo "$CONTRASENYA" | tr -d '\r')

    # Validar campos vacíos
    if [[ -z "$NOM" || -z "$COGNOM" || -z "$DEPARTAMENT" ]]; then
        log "WARN" "Fila inválida o vacía detectada. Saltando."
        continue
    fi

    # 3. Gestión de la Unidad Organizativa (OU)
    check_and_create_ou "$DEPARTAMENT"
    if [ $? -ne 0 ]; then
        log "ERROR" "Saltando usuario $NOM $COGNOM por error en OU."
        continue
    fi

    # 4. Generación de atributos
    CLEAN_NOM=$(normalize "$NOM")
    CLEAN_COGNOM=$(normalize "$COGNOM")
    # UID: nombre + apellido (ej. martavila)
    UID_USER="${CLEAN_NOM}${CLEAN_COGNOM}"
    USER_DN="uid=$UID_USER,ou=$DEPARTAMENT,$LDAP_BASE_DN"

    # 5. Generación del LDIF del usuario
    LDIF_USER=$(cat <<EOF
dn: $USER_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: $NOM $COGNOM
sn: $COGNOM
uid: $UID_USER
userPassword: $CONTRASENYA
gidNumber: 1000
uidNumber: $(shuf -i 10000-60000 -n 1)
homeDirectory: /home/$UID_USER
loginShell: /bin/bash
EOF
)

    # 6. Inyección en LDAP
    echo "$LDIF_USER" | ldapadd -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" > /dev/null 2>&1

    # 7. Verificación del resultado
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Usuario creado: $UID_USER ($DEPARTAMENT)"
    else
        log "ERROR" "Error al crear usuario: $UID_USER (posible duplicado o error de servidor)"
    fi

done

log "INFO" "Script finalizado. Revisa $LOG_FILE para más detalles."
