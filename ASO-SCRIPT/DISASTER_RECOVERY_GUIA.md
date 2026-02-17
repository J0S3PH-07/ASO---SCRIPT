# Fase 3: Disaster Recovery - Guía de Uso

## 📋 Resumen de Cambios Implementados

### 1. Servicio MinIO añadido a docker-compose.yml
- **Imagen**: `minio/minio`
- **Contenedor**: `minio-server`
- **Puertos**: 
  - `9000` - API de MinIO
  - `9001` - Consola web de MinIO
- **Credenciales**:
  - Usuario: `admin`
  - Contraseña: `password123`

### 2. Scripts Creados

#### backup_cloud.sh
Script que realiza:
- Volcado de la base de datos LDAP usando `ldapsearch`
- Genera archivo `backup_YYYYMMDD.ldif`
- Sube el backup a MinIO usando rclone
- Validación con mensajes de éxito/error

#### configurar_rclone.sh
Script que configura automáticamente:
- Conexión rclone con MinIO
- Remote llamado `corporate_s3`
- Crea el bucket `backups-ldap`

---

## 🚀 Instrucciones de Uso

### Paso 1: Iniciar los servicios

```bash
docker-compose up -d
```

Esto iniciará todos los servicios incluyendo MinIO.

### Paso 2: Acceder al contenedor ldap-client

```bash
docker exec -it ldap-client bash
```

### Paso 3: Configurar rclone (SOLO LA PRIMERA VEZ)

Dentro del contenedor ldap-client:

```bash
cd /scripts
chmod +x configurar_rclone.sh
./configurar_rclone.sh
```

Este script creará automáticamente la configuración de rclone con los siguientes parámetros:
- **Nombre del remote**: `corporate_s3`
- **Tipo**: `s3`
- **Proveedor**: `Minio`
- **Endpoint**: `http://minio:9000`
- **Access Key**: `admin`
- **Secret Key**: `password123`

### Paso 4: Dar permisos de ejecución al script de backup

```bash
chmod +x backup_cloud.sh
```

### Paso 5: Ejecutar backup manual (prueba)

```bash
./backup_cloud.sh
```

Deberías ver una salida similar a:
```
==========================================
Iniciando backup LDAP - Mon Feb 17 16:10:00 UTC 2026
==========================================
Generando volcado de LDAP...
✓ Volcado LDAP generado exitosamente: /scripts/backups/backup_20260217.ldif
  Tamaño del archivo: 2.3K

Subiendo backup a MinIO...
✓ Backup subido exitosamente a MinIO
  Destino: corporate_s3:backups-ldap/backup_20260217.ldif

==========================================
Backup completado con éxito - Mon Feb 17 16:10:05 UTC 2026
==========================================
```

### Paso 6: Verificar el backup en MinIO

Puedes acceder a la consola web de MinIO en:
- **URL**: http://localhost:9001
- **Usuario**: `admin`
- **Contraseña**: `password123`

O verificar desde la línea de comandos:
```bash
rclone ls corporate_s3:backups-ldap
```

---

## ⏰ Configuración de Tarea Cron

Para ejecutar el backup automáticamente cada día a las **23:55h**, añade la siguiente línea al crontab:

### Línea exacta para crontab:

```
55 23 * * * /scripts/backup_cloud.sh >> /scripts/backups/backup.log 2>&1
```

### Cómo añadir la tarea cron:

1. Dentro del contenedor ldap-client, edita el crontab:
```bash
crontab -e
```

2. Añade la línea indicada arriba

3. Guarda y cierra el editor

4. Verifica que la tarea se añadió correctamente:
```bash
crontab -l
```

### Explicación de la línea cron:
- `55 23 * * *` - Ejecutar a las 23:55 todos los días
- `/scripts/backup_cloud.sh` - Script a ejecutar
- `>> /scripts/backups/backup.log 2>&1` - Redirigir salida y errores al log

---

## 📁 Estructura de Archivos

```
ASO-SCRIPT/
├── docker-compose.yml          # Configuración con MinIO añadido
├── backup_cloud.sh             # Script de backup automático
├── configurar_rclone.sh        # Script de configuración de rclone
├── alta_massiva.sh             # Script existente
├── empleados.csv               # Datos existentes
└── backups/                    # Directorio de backups (se crea automáticamente)
    ├── backup_20260217.ldif
    └── backup.log
```

---

## 🔍 Verificación y Troubleshooting

### Verificar que MinIO está corriendo:
```bash
docker ps | grep minio
```

### Verificar conectividad con MinIO:
```bash
rclone lsd corporate_s3:
```

### Ver logs del contenedor MinIO:
```bash
docker logs minio-server
```

### Ver logs de backups:
```bash
cat /scripts/backups/backup.log
```

---

## 📝 Notas Importantes

1. **Primera ejecución**: Asegúrate de ejecutar `configurar_rclone.sh` antes del primer backup
2. **Permisos**: Los scripts deben tener permisos de ejecución (`chmod +x`)
3. **Espacio**: Verifica que hay suficiente espacio para los backups
4. **Retención**: Considera implementar una política de retención para eliminar backups antiguos
5. **Seguridad**: En producción, usa credenciales más seguras que `admin/password123`

---

## ✅ Checklist de Implementación

- [x] MinIO añadido a docker-compose.yml
- [x] Script backup_cloud.sh creado
- [x] Script configurar_rclone.sh creado
- [ ] Servicios iniciados con docker-compose
- [ ] Rclone configurado en ldap-client
- [ ] Backup manual ejecutado exitosamente
- [ ] Tarea cron configurada
- [ ] Verificación en consola MinIO
