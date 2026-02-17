#!/bin/bash

################################################################################
# Script: configurar_rclone.sh
# Descripción: Configura rclone automáticamente para conectar con MinIO
# Autor: Sistema de Disaster Recovery
# Fecha: 2026-02-17
################################################################################

echo "=========================================="
echo "Configurando rclone para MinIO"
echo "=========================================="

# Crear directorio de configuración de rclone
mkdir -p ~/.config/rclone

# Crear archivo de configuración de rclone
cat > ~/.config/rclone/rclone.conf << 'EOF'
[corporate_s3]
type = s3
provider = Minio
access_key_id = admin
secret_access_key = password123
endpoint = http://minio:9000
EOF

echo "✓ Configuración de rclone creada exitosamente"
echo ""
echo "Verificando configuración..."
rclone config show corporate_s3

echo ""
echo "Creando bucket 'backups-ldap' en MinIO..."
rclone mkdir corporate_s3:backups-ldap

if [ $? -eq 0 ]; then
    echo "✓ Bucket 'backups-ldap' creado exitosamente"
else
    echo "⚠ El bucket puede ya existir o hubo un error"
fi

echo ""
echo "=========================================="
echo "Configuración completada"
echo "=========================================="
echo ""
echo "Puedes verificar la conexión con:"
echo "  rclone lsd corporate_s3:"
