# Guia Rapida de Chatwoot

Chatwoot es un centro de atencion al cliente open source que permite gestionar conversaciones de multiples canales en una sola interfaz.

## Que es Chatwoot?

- **Bandeja unificada**: WhatsApp, Email, Chat web, Facebook, Twitter en un solo lugar
- **Agentes**: Asignar conversaciones a miembros del equipo
- **Automatizaciones**: Respuestas automaticas, etiquetas, macros
- **Reportes**: Metricas de rendimiento del equipo

## Acceso

| Servicio | URL Interna | Puerto |
|----------|-------------|--------|
| Chatwoot Web | http://chatwoot:3000 | 3000 |

Configurar proxy en NPM: `chat.tudominio.com -> http://chatwoot:3000`

## Primer Inicio

### 1. Preparar la base de datos

Chatwoot usa PostgreSQL (compartido con Evolution API). La primera vez debes crear la base de datos:

```bash
# Crear base de datos chatwoot (usar -d evolutiondb para conectar)
docker exec -it postgres-messaging psql -U evolution -d evolutiondb -c "CREATE DATABASE chatwoot;"

# Ejecutar migraciones (usar docker compose run para evitar conflictos)
docker compose run --rm chatwoot bundle exec rails db:chatwoot_prepare
```

> **Nota**: Las migraciones pueden tardar 1-2 minutos. Espera a que termine antes de continuar.

### 2. Crear cuenta de administrador

```bash
# Crear cuenta super admin
docker exec -it chatwoot bundle exec rails c

# En la consola de Rails:
SuperAdmin.create!(email: 'admin@tudominio.com', password: 'TuPasswordSeguro', name: 'Admin')
exit
```

### 3. Acceder a Chatwoot

1. Ir a `http://chatwoot:3000` (o tu dominio configurado)
2. Iniciar sesion con el email y password creados
3. Crear una cuenta/organizacion

## Integrar con WhatsApp (Evolution API)

### Opcion A: Desde Chatwoot (Recomendado)

1. En Chatwoot ir a **Settings > Inboxes > Add Inbox**
2. Seleccionar **API Channel**
3. Configurar:
   - Name: `WhatsApp`
   - Webhook URL: Copiar la URL generada

4. En Evolution API, crear webhook apuntando a Chatwoot:
```bash
curl -X POST "http://evolution:8080/webhook/set/whatsapp_main" \
  -H "apikey: TU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "url": "http://chatwoot:3000/webhooks/whatsapp",
    "events": ["messages.upsert", "messages.update", "connection.update"]
  }'
```

### Opcion B: Usando integracion nativa

1. En Chatwoot, crear inbox tipo **API**
2. Copiar el `Account ID` y `Access Token`
3. En `.env` del stack, configurar:

```bash
CHATWOOT_ENABLED=true
CHATWOOT_ACCOUNT_ID=1
CHATWOOT_TOKEN=tu_token_de_chatwoot
CHATWOOT_URL_API=http://chatwoot:3000
CHATWOOT_SIGN_MSG=true
```

4. Reiniciar Evolution API:
```bash
docker compose restart evolution
```

## Conceptos Basicos

### Inboxes (Bandejas)
Cada canal de comunicacion es un inbox:
- WhatsApp
- Email
- Chat en vivo (widget web)
- Facebook Messenger
- Twitter

### Conversaciones
Cada chat con un cliente. Estados:
- **Open**: Activa, esperando respuesta
- **Resolved**: Cerrada/resuelta
- **Pending**: En espera

### Agentes
Usuarios que responden mensajes. Roles:
- **Administrator**: Acceso total
- **Agent**: Solo responder mensajes

### Etiquetas (Labels)
Categorizar conversaciones: `urgente`, `ventas`, `soporte`, etc.

### Respuestas Predefinidas (Canned Responses)
Plantillas de respuesta rapida. Ejemplo:
- `/saludo` -> "Hola! Gracias por contactarnos..."
- `/horario` -> "Nuestro horario es de 9am a 6pm..."

## Ejemplos Practicos

### Crear respuesta predefinida

1. Ir a **Settings > Canned Responses > Add**
2. Short Code: `saludo`
3. Content: `Hola {{contact.name}}! Gracias por contactarnos. En que podemos ayudarte?`

### Crear automatizacion

1. Ir a **Settings > Automation > Add Rule**
2. Ejemplo: Asignar etiqueta automatica
   - When: Conversation Created
   - Conditions: Message contains "urgente"
   - Actions: Add Label "urgente"

### Configurar widget de chat web

1. Ir a **Settings > Inboxes > Add Inbox > Website**
2. Configurar nombre y color
3. Copiar el script generado
4. Pegar en tu sitio web:

```html
<script>
  (function(d,t) {
    var BASE_URL="https://chat.tudominio.com";
    var g=d.createElement(t),s=d.getElementsByTagName(t)[0];
    g.src=BASE_URL+"/packs/js/sdk.js";
    g.defer = true;
    g.async = true;
    s.parentNode.insertBefore(g,s);
    g.onload=function(){
      window.chatwootSDK.run({
        websiteToken: 'TU_TOKEN',
        baseUrl: BASE_URL
      })
    }
  })(document,"script");
</script>
```

## Correo Saliente

Chatwoot ya esta configurado para enviar correo via Postfix (`postfix:25`). No necesitas cambiar nada en Chatwoot.

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

**Chatwoot sigue enviando a `postfix:25`** - Postfix se encarga de reenviar al relay.

## Comandos Utiles

```bash
# Ver logs de Chatwoot
docker compose logs -f chatwoot

# Ver logs del worker (Sidekiq)
docker compose logs -f chatwoot-sidekiq

# Reiniciar Chatwoot
docker compose restart chatwoot chatwoot-sidekiq

# Consola de Rails (para comandos avanzados)
docker exec -it chatwoot bundle exec rails c

# Limpiar cache
docker exec -it chatwoot bundle exec rails cache:clear
```

## Troubleshooting

### Error de conexion a base de datos
```bash
# Verificar que PostgreSQL esta corriendo
docker compose ps postgres

# Verificar conexion
docker exec -it chatwoot bundle exec rails db:version
```

### Sidekiq no procesa trabajos
```bash
# Ver estado de Sidekiq
docker compose logs chatwoot-sidekiq

# Reiniciar
docker compose restart chatwoot-sidekiq
```

### Error 500 al acceder
```bash
# Ver logs detallados
docker compose logs -f chatwoot | grep -i error

# Verificar SECRET_KEY_BASE
docker exec chatwoot printenv | grep SECRET
```

## Recursos

- Documentacion oficial: https://www.chatwoot.com/docs
- API Reference: https://www.chatwoot.com/developers/api
- GitHub: https://github.com/chatwoot/chatwoot
