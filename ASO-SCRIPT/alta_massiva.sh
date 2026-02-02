#!/bin/bash

# ==============================================================================
# Script: alta_massiva.sh
# Misión: Automatización de altas de usuarios en LDAP para Tecnosolutions.
# Requisitos Actualizados: 
#   - Detección automática de separador CSV (, o ;).
#   - Limpieza exhaustiva de espacios en OU.
#   - Espera (sleep) tras crear OU.
# ==============================================================================

# ==============================================================================
# CONFIGURACIÓN DEL ENTORNO
# ==============================================================================
LDAP_SERVER="ldap://ldap-server"              # Nombre del servicio en docker-compose
LDAP_BASE_DN="dc=tecnosolutions,dc=com"    # Dominio de la empresa
LDAP_BIND_DN="cn=admin,$LDAP_BASE_DN"      # Usuario Admin
LDAP_BIND_PW="admin"                       # Contraseña Admin

INPUT_FILE="nuevos_empleados.xlsx - Automatizar Alta de Usuarios en.csv"
LOG_FILE="alta_usuaris.log"

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================

# Loguear mensajes
log() {
    local TYPE=$1
    local MSG=$2
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] [$TYPE] $MSG" | tee -a "$LOG_FILE"
}

# Normalizar texto para UIDs (minúsculas, sin acentos, sin espacios)
normalize() {
    echo "$1" | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[áàäâ]/a/g;s/[éèëê]/e/g;s/[íìïî]/i/g;s/[óòöô]/o/g;s/[úùüû]/u/g;s/ñ/n/g' | \
    tr -d ' '
}

# Check y Crear OU
check_and_create_ou() {
    local OU_NAME=$1
    local OU_DN="ou=$OU_NAME,$LDAP_BASE_DN"

    # Buscamos la OU
    ldapsearch -x -H "$LDAP_SERVER" -b "$LDAP_BASE_DN" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" "(ou=$OU_NAME)" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        log "INFO" "OU '$OU_NAME' no existe. Creando..."
        
        local LDIF_OU=$(cat <<EOF
dn: $OU_DN
objectClass: organizationalUnit
ou: $OU_NAME
EOF
)
        echo "$LDIF_OU" | ldapadd -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log "SUCCESS" "OU '$OU_NAME' creada."
            # Mágica espera para asegurar consistencia
            sleep 1
        else
            log "ERROR" "Fallo al crear OU '$OU_NAME'."
            return 1
        fi
    fi
    return 0
}

# ==============================================================================
# LÓGICA PRINCIPAL
# ==============================================================================

if [ ! -f "$INPUT_FILE" ]; then
    log "CRITICAL" "El archivo $INPUT_FILE no existe."
    exit 1
fi

# Detectar separador leyendo la primera línea header
FIRST_LINE=$(head -n 1 "$INPUT_FILE")
if [[ "$FIRST_LINE" == *";"* ]]; then
    SEP=";"
    log "INFO" "Detectado separador: Punto y coma (;)"
else
    SEP=","
    log "INFO" "Detectado separador: Coma (,)"
fi

log "INFO" "Iniciando proceso..."

# Leer archivo usando el separador detectado
tail -n +2 "$INPUT_FILE" | while IFS="$SEP" read -r NOM COGNOM DEPARTAMENT CONTRASENYA; do
    
    # 1. Limpieza inicial universal (CR, comillas extra si las hubiera)
    NOM=$(echo "$NOM" | tr -d '\r' | sed 's/^"//;s/"$//')
    COGNOM=$(echo "$COGNOM" | tr -d '\r' | sed 's/^"//;s/"$//')
    DEPARTAMENT=$(echo "$DEPARTAMENT" | tr -d '\r' | sed 's/^"//;s/"$//')
    CONTRASENYA=$(echo "$CONTRASENYA" | tr -d '\r' | sed 's/^"//;s/"$//')

    # 2. Trim de espacios en blanco (especialmente para Departament)
    # Esto elimina espacios al inicio y final
    NOM=$(echo "$NOM" | sed 's/^[ \t]*//;s/[ \t]*$//')
    COGNOM=$(echo "$COGNOM" | sed 's/^[ \t]*//;s/[ \t]*$//')
    DEPARTAMENT=$(echo "$DEPARTAMENT" | sed 's/^[ \t]*//;s/[ \t]*$//')
    CONTRASENYA=$(echo "$CONTRASENYA" | sed 's/^[ \t]*//;s/[ \t]*$//')

    if [[ -z "$NOM" || -z "$COGNOM" || -z "$DEPARTAMENT" ]]; then
        continue
    fi

    # 3. Verificar OU con el nombre limpio
    check_and_create_ou "$DEPARTAMENT"
    if [ $? -ne 0 ]; then
        continue
    fi

    # 4. Generar datos usuario
    CLEAN_NOM=$(normalize "$NOM")
    CLEAN_COGNOM=$(normalize "$COGNOM")
    UID_USER="${CLEAN_NOM}${CLEAN_COGNOM}"
    USER_DN="uid=$UID_USER,ou=$DEPARTAMENT,$LDAP_BASE_DN"

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

    echo "$LDIF_USER" | ldapadd -x -H "$LDAP_SERVER" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log "SUCCESS" "Usuario creado: $UID_USER"
    else
        log "ERROR" "Error al crear usuario: $UID_USER ($USER_DN)"
    fi

done

log "INFO" "Fin del proceso."
