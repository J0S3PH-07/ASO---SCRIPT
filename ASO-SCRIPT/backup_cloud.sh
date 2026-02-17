#!/bin/bash

################################################################################
# Script: backup_cloud.sh
# Descripción: Realiza backup de la base de datos LDAP y lo sube a MinIO
# Autor: Sistema de Disaster Recovery
# Fecha: 2026-02-17
################################################################################

# Variables de configuración
LDAP_HOST="openldap"
LDAP_BASE_DN="dc=tecnosolutions,dc=com"
LDAP_ADMIN_DN="cn=admin,dc=tecnosolutions,dc=com"
LDAP_ADMIN_PASSWORD="admin"
BACKUP_DIR="/scripts/backups"
RCLONE_REMOTE="corporate_s3"
BUCKET_NAME="backups-ldap"

# Generar nombre de archivo con fecha actual
FECHA=$(date +%Y%m%d)
BACKUP_FILE="${BACKUP_DIR}/backup_${FECHA}.ldif"

# Crear directorio de backups si no existe
mkdir -p "${BACKUP_DIR}"

echo "=========================================="
echo "Iniciando backup LDAP - $(date)"
echo "=========================================="

# Realizar volcado de la base de datos LDAP
echo "Generando volcado de LDAP..."
ldapsearch -x -H ldap://${LDAP_HOST} \
  -D "${LDAP_ADMIN_DN}" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "${LDAP_BASE_DN}" \
  > "${BACKUP_FILE}"

# Verificar si el volcado fue exitoso
if [ $? -eq 0 ]; then
    echo "✓ Volcado LDAP generado exitosamente: ${BACKUP_FILE}"
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo "  Tamaño del archivo: ${BACKUP_SIZE}"
else
    echo "✗ ERROR: Fallo al generar el volcado LDAP"
    exit 1
fi

# Subir backup a MinIO usando rclone
echo ""
echo "Subiendo backup a MinIO..."
rclone copy "${BACKUP_FILE}" "${RCLONE_REMOTE}:${BUCKET_NAME}/" --progress

# Verificar si la subida fue exitosa
if [ $? -eq 0 ]; then
    echo "✓ Backup subido exitosamente a MinIO"
    echo "  Destino: ${RCLONE_REMOTE}:${BUCKET_NAME}/backup_${FECHA}.ldif"
    echo ""
    echo "=========================================="
    echo "Backup completado con éxito - $(date)"
    echo "=========================================="
    exit 0
else
    echo "✗ ERROR: Fallo al subir el backup a MinIO"
    echo ""
    echo "=========================================="
    echo "Backup FALLÓ - $(date)"
    echo "=========================================="
    exit 1
fi
