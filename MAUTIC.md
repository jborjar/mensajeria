# Guia Rapida de Mautic

Mautic es una plataforma de marketing automation open source para crear campanas de email, gestionar contactos y automatizar flujos de marketing.

## Que es Mautic?

- **Email Marketing**: Campanas masivas, newsletters, emails transaccionales
- **Lead Management**: Captura, scoring y segmentacion de contactos
- **Landing Pages**: Crear paginas de aterrizaje sin codigo
- **Formularios**: Capturar leads desde tu sitio web
- **Automatizacion**: Flujos de trabajo basados en comportamiento

## Acceso

| Servicio | URL Interna | Puerto |
|----------|-------------|--------|
| Mautic Web | http://mautic:80 | 80 |

Configurar proxy en NPM: `marketing.tudominio.com -> http://mautic:80`

## Primer Inicio

### 1. Esperar inicializacion

La primera vez, Mautic tarda ~2-3 minutos en:
- Crear tablas en MySQL
- Configurar cache
- Generar assets

```bash
# Ver progreso
docker compose logs -f mautic
```

### 2. Acceder al panel

1. Ir a `http://mautic:80` (o tu dominio)
2. Usuario: valor de `MAUTIC_ADMIN_USER` (.env)
3. Password: valor de `MAUTIC_ADMIN_PASSWORD` (.env)

### 3. Configurar correo saliente (SMTP)

1. Ir a **Settings (engranaje) > Configuration > Email Settings**
2. Configurar:
   - Mailer: `smtp`
   - Host: `postfix`
   - Port: `25`
   - Encryption: `None`
   - Authentication: `No`

3. Guardar y probar con "Send test email"

## Conceptos Basicos

### Contactos
Personas en tu base de datos. Campos principales:
- Email (obligatorio)
- Nombre, Apellido
- Empresa, Telefono
- Campos personalizados

### Segmentos
Grupos de contactos basados en criterios:
- Por ubicacion
- Por comportamiento (abrio email, visito pagina)
- Por datos demograficos

### Campanas (Campaigns)
Flujos automatizados. Ejemplo:
1. Contacto llena formulario
2. Esperar 1 dia
3. Enviar email de bienvenida
4. Si abre email -> enviar oferta
5. Si no abre -> enviar recordatorio

### Emails
Tipos de emails:
- **Template Emails**: Plantillas reutilizables
- **Segment Emails**: Envio masivo a un segmento
- **Campaign Emails**: Parte de una campana automatizada

### Formularios
Capturar informacion de visitantes:
- Formularios standalone
- Formularios embebidos en tu sitio

### Landing Pages
Paginas de aterrizaje para campanas:
- Editor drag & drop
- Plantillas predefinidas
- Tracking de conversiones

## Ejemplos Practicos

### Crear un formulario de contacto

1. Ir a **Components > Forms > New**
2. Agregar campos:
   - Email (obligatorio)
   - Nombre
   - Mensaje (texto largo)
3. En **Actions**:
   - Add to segment: "Leads Web"
   - Send email to contact: "Gracias por contactarnos"
4. Guardar y copiar codigo de embed

```html
<script type="text/javascript" src="http://mautic/form/generate.js?id=1"></script>
```

### Crear campana de bienvenida

1. Ir a **Campaigns > New**
2. Nombre: "Bienvenida Nuevos Contactos"
3. Agregar **Contact Source**:
   - Segment: "Leads Web"
4. Agregar **Action**:
   - Send Email: "Email de Bienvenida"
5. Agregar **Decision** (despues del email):
   - Opens Email
   - Si -> enviar "Oferta Especial" (esperar 2 dias)
   - No -> enviar "Recordatorio" (esperar 3 dias)
6. Publicar campana

### Crear segmento dinamico

1. Ir a **Segments > New**
2. Nombre: "Clientes Activos"
3. Filtros:
   - Email opened > 0 (ultimos 30 dias)
   - Country = Mexico
4. El segmento se actualiza automaticamente

### Importar contactos desde CSV

1. Ir a **Contacts > Import**
2. Subir archivo CSV con columnas:
   ```
   email,firstname,lastname,company
   juan@example.com,Juan,Perez,Acme Inc
   ```
3. Mapear campos
4. Seleccionar segmento destino
5. Iniciar importacion

### Configurar tracking en tu sitio

Agregar este script en todas las paginas:

```html
<script>
    (function(w,d,t,u,n,a,m){w['MauticTrackingObject']=n;
        w[n]=w[n]||function(){(w[n].q=w[n].q||[]).push(arguments)},a=d.createElement(t),
        m=d.getElementsByTagName(t)[0];a.async=1;a.src=u;m.parentNode.insertBefore(a,m)
    })(window,document,'script','http://mautic/mtc.js','mt');
    mt('send', 'pageview');
</script>
```

Esto permite:
- Trackear paginas visitadas
- Identificar contactos por email
- Activar campanas por comportamiento

## Integracion con Postfix

Mautic ya esta configurado para enviar correo via Postfix (`postfix:25`). No necesitas cambiar nada en Mautic.

### Cambiar a relay (Gmail, SendGrid, etc)

Solo modifica las variables de Postfix en `.env`:

```bash
POSTFIX_RELAY_HOST=smtp.gmail.com
POSTFIX_RELAY_PORT=587
POSTFIX_RELAY_USER=tucuenta@gmail.com
POSTFIX_RELAY_PASSWORD=tu_app_password
```

Y reinicia Postfix:
```bash
docker compose restart postfix
```

**Mautic sigue enviando a `postfix:25`** - Postfix se encarga de reenviar al relay. No necesitas cambiar configuracion de Mautic.

## Comandos Utiles

```bash
# Ver logs de Mautic
docker compose logs -f mautic

# Ver logs del cron (tareas programadas)
docker compose logs -f mautic-cron

# Ver logs del worker (emails en cola)
docker compose logs -f mautic-worker

# Reiniciar Mautic
docker compose restart mautic mautic-cron mautic-worker

# Limpiar cache (si hay problemas)
docker exec -it mautic php bin/console cache:clear

# Procesar cola de emails manualmente
docker exec -it mautic php bin/console messenger:consume email

# Actualizar segmentos manualmente
docker exec -it mautic php bin/console mautic:segments:update
```

## Tareas Programadas (Cron)

El contenedor `mautic-cron` ejecuta automaticamente:
- Actualizar segmentos
- Procesar campanas
- Enviar emails programados
- Limpiar logs antiguos

Si necesitas ejecutar manualmente:

```bash
# Actualizar segmentos
docker exec mautic php bin/console mautic:segments:update

# Activar campanas
docker exec mautic php bin/console mautic:campaigns:trigger

# Procesar emails en cola
docker exec mautic php bin/console mautic:emails:send
```

## Troubleshooting

### No se envian emails
```bash
# Verificar cola de emails
docker exec -it mautic php bin/console messenger:stats

# Ver errores
docker compose logs mautic-worker | grep -i error

# Probar conexion SMTP
docker exec -it mautic php bin/console swiftmailer:email:send --to=test@example.com
```

### Campanas no se ejecutan
```bash
# Verificar cron esta corriendo
docker compose ps mautic-cron

# Ejecutar manualmente
docker exec -it mautic php bin/console mautic:campaigns:trigger --force
```

### Error de permisos
```bash
# Arreglar permisos
docker exec -it mautic chown -R www-data:www-data /var/www/html/var
docker exec -it mautic chmod -R 755 /var/www/html/var
```

### Cache corrupta
```bash
# Limpiar cache completamente
docker exec -it mautic rm -rf var/cache/*
docker compose restart mautic
```

## Buenas Practicas

### Email
- Usa autenticacion SPF, DKIM, DMARC en tu dominio
- Mantener lista limpia (remover bounces)
- Ratio recomendado: max 50 emails/hora por IP nueva

### Segmentos
- No crear segmentos con mas de 3-4 filtros
- Usar campos indexados para filtros frecuentes
- Revisar segmentos huerfanos periodicamente

### Campanas
- Probar con segmento pequeno primero
- Usar A/B testing para asuntos de email
- Monitorear tasas de apertura y clicks

## Recursos

- Documentacion oficial: https://docs.mautic.org
- Foro comunidad: https://forum.mautic.org
- GitHub: https://github.com/mautic/mautic
- Slack: https://mautic.org/slack
