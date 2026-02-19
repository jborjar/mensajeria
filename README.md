# Messaging Stack

Stack completo de mensajeria y marketing: correo (SMTP), WhatsApp, atencion al cliente y marketing automation.

## Componentes

| Servicio | Puerto | Funcion |
|----------|--------|---------|
| **Postfix** | 25 | Servidor SMTP para envio de correos |
| **Evolution API** | 8080 | WhatsApp Business API |
| **Chatwoot** | 3000 | Centro de atencion al cliente |
| **Mautic** | 80 | Marketing automation |
| **PostgreSQL** | 5432 | Base de datos (Evolution + Chatwoot) - con pgvector |
| **MariaDB** | 3306 | Base de datos (Mautic) - requiere 10.11+ |
| **Redis** | 6379 | Cache |

## Arquitectura

```mermaid
flowchart TB
%%{ init: { 'flowchart': { 'curve': 'linear' } } }%%
    subgraph external["🌍 ACCESO EXTERNO"]
        NPM[Nginx Proxy Manager]
    end

    subgraph messaging["📬 MENSAJERÍA"]
        POSTFIX["Postfix<br/>Puerto: 25<br/>Función: SMTP"]
        EVOLUTION["Evolution API<br/>Puerto: 8080<br/>Función: WhatsApp"]
    end

    subgraph crm["👥 CRM & MARKETING"]
        CHATWOOT["Chatwoot<br/>Puerto: 3000<br/>Función: Soporte"]
        MAUTIC["Mautic<br/>Puerto: 80<br/>Función: Automation"]
    end

    subgraph storage["💾 ALMACENAMIENTO"]
        POSTGRES["PostgreSQL<br/>Puerto: 5432<br/>BDs: evolutiondb, chatwoot<br/>Extensión: pgvector"]
        REDIS["Redis<br/>Puerto: 6379<br/>Función: Cache"]
        MARIADB["MariaDB 10.11+<br/>Puerto: 3306<br/>BD: mautic"]
    end

    NPM --> POSTFIX
    NPM --> EVOLUTION
    NPM --> CHATWOOT
    NPM --> MAUTIC

    EVOLUTION --> POSTGRES
    EVOLUTION --> REDIS
    CHATWOOT --> POSTGRES
    CHATWOOT --> REDIS
    CHATWOOT --> POSTFIX
    MAUTIC --> MARIADB
    MAUTIC --> POSTFIX

    style external fill:#bbdefb
    style messaging fill:#c8e6c9
    style crm fill:#ffe0b2
    style storage fill:#f8bbd0
```

## Guias Rapidas

- [CHATWOOT.md](CHATWOOT.md) - Guia de uso de Chatwoot
- [MAUTIC.md](MAUTIC.md) - Guia de uso de Mautic

## Requisitos

- Docker y Docker Compose
- Red externa `vpn-proxy` (o modificar NETWORK_NAME en .env)

## Notas Tecnicas

### PostgreSQL con pgvector

Este stack usa `pgvector/pgvector:pg15` en lugar de `postgres:15-alpine` porque **Chatwoot requiere la extension pgvector** para funcionalidades de AI. Esta extension no viene incluida en la imagen oficial de PostgreSQL.

### Passwords con caracteres especiales

Si usas passwords con caracteres especiales (`@`, `#`, `:`, `/`, `?`), debes usar URL encoding en las variables `*_PASSWORD_ENCODE`. Ver seccion [Passwords con Caracteres Especiales](#passwords-con-caracteres-especiales).

### Bases de datos separadas

- **PostgreSQL**: Usado por Evolution API (evolutiondb) y Chatwoot (chatwoot)
- **MariaDB**: Usado exclusivamente por Mautic (requiere MariaDB 10.11+ o MySQL 8.4+)

## Instalacion

Hay dos formas de levantar el stack:

| Metodo | Comando | Descripcion |
|--------|---------|-------------|
| **Automatico** | `./init.sh` | Configura todo: genera claves, crea BD, configura servicios, envia pruebas |
| **Manual** | `docker compose up -d` | Solo levanta contenedores, debes configurar cada servicio manualmente |

### Instalacion Automatica (Recomendado)

El script `init.sh` usa las variables `TEL_SOPORTE` y `EMAIL_SOPORTE` para configurar automaticamente:

| Variable | Uso en init.sh |
|----------|----------------|
| `TEL_SOPORTE` | Crear instancia WhatsApp, enviar mensaje de prueba |
| `EMAIL_SOPORTE` | Crear SuperAdmin en Chatwoot, enviar codigo y credenciales por correo |

**Que hace init.sh:**
1. Genera passwords y API keys seguras (si no existen en .env)
2. Inicia todos los servicios con `docker compose up -d`
3. Crea base de datos `chatwoot` y ejecuta migraciones
4. Crea SuperAdmin en Chatwoot con email `EMAIL_SOPORTE`
5. Crea instancia WhatsApp con numero `TEL_SOPORTE`
6. Genera codigo de emparejamiento y lo envia por correo a `EMAIL_SOPORTE`
7. Configura integracion Chatwoot + Evolution (mensajes WhatsApp en Chatwoot)
8. **Configura webhook AgentAI** (respuestas automaticas con IA)
9. Espera 30 segundos para que ingreses el codigo
10. Envia mensajes de prueba (WhatsApp + correo)
11. Muestra todas las credenciales generadas

```bash
# 1. Clonar el repositorio
git clone https://github.com/jborjar/messaging.git
cd messaging

# 2. Copiar y configurar el archivo de entorno
cp .env.example .env
nano .env

# 3. Configurar variables REQUERIDAS:
#    TEL_SOPORTE=521XXXXXXXXXX   (tu telefono con codigo de pais)
#    EMAIL_SOPORTE=admin@empresa.com   (tu correo)

# 4. Ejecutar el script de inicializacion
chmod +x init.sh
./init.sh
```

> **Nota**: El script valida que `TEL_SOPORTE` y `EMAIL_SOPORTE` esten configurados. Si no lo estan, muestra un error y no continua.

### Instalacion Manual (Solo levantar contenedores)

Si prefieres configurar cada servicio manualmente:

```bash
# 1. Copiar y configurar .env
cp .env.example .env
nano .env

# 2. Generar passwords y API keys manualmente
openssl rand -hex 32   # Para AUTHENTICATION_API_KEY
openssl rand -hex 64   # Para CHATWOOT_SECRET_KEY

# 3. Solo levantar contenedores (sin configurar servicios)
docker compose up -d

# 4. Configurar Chatwoot manualmente (ver CHATWOOT.md)
# 5. Configurar Evolution manualmente (ver seccion Evolution API)
# 6. Configurar Mautic manualmente (ver MAUTIC.md)
```

> **Importante**: Con `docker compose up -d` los contenedores se levantan pero NO se configura nada: no se crea SuperAdmin, no se crea instancia WhatsApp, no se ejecutan migraciones de Chatwoot.

## Acceso a Servicios

Los servicios estan expuestos en los siguientes puertos:

| Servicio | Puerto | URL Local | Ejemplo NPM |
|----------|--------|-----------|-------------|
| Postfix | 25 (interno) | smtp://postfix:25 | - |
| Evolution API | 8080 | http://IP_SERVIDOR:8080 | api.tudominio.com |
| Chatwoot | 3000 | http://IP_SERVIDOR:3000 | chat.tudominio.com |
| Mautic | 8081 | http://IP_SERVIDOR:8081 | marketing.tudominio.com |

> **Nota**: Los puertos estan expuestos directamente para facilitar la integracion con servicios externos (como el Orquestador en otro servidor).

## Estructura de Archivos

```
messaging/
├── docker-compose.yaml      # Definicion de servicios
├── dockerfiles/             # Dockerfiles personalizados
│   ├── Dockerfile.postfix
│   └── scripts/
│       └── entrypoint_postfix.sh
├── .env                     # Configuracion (no commitear)
├── .env.example             # Plantilla de configuracion
├── init.sh                  # Script de inicializacion
├── README.md                # Este archivo
├── CHATWOOT.md              # Guia de Chatwoot
├── MAUTIC.md                # Guia de Mautic
└── stack_data/              # Datos persistentes
    ├── postfix/
    │   ├── spool/
    │   └── mail/
    ├── postgres/
    │   └── data/
    ├── redis/
    │   └── data/
    ├── mariadb/
    │   └── data/
    ├── evolution/
    │   └── instances/
    ├── chatwoot/
    │   └── storage/
    └── mautic/
        ├── config/
        ├── logs/
        └── media/
```

## Configuracion

### Variables de Entorno (.env)

#### General

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `TZ` | Zona horaria | America/Mexico_City |
| `DATA_PATH` | Ruta de datos persistentes | ./stack_data |
| `NETWORK_NAME` | Red Docker externa | vpn-proxy |

#### Datos de Soporte (para configuracion automatica)

| Variable | Descripcion | Ejemplo |
|----------|-------------|---------|
| `TEL_SOPORTE` | Telefono con codigo de pais | 5215510771180 |
| `EMAIL_SOPORTE` | Email del administrador | admin@empresa.com |

> Estas variables son **requeridas** para la configuracion automatica via `init.sh`.

#### Postfix

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `POSTFIX_HOSTNAME` | Hostname del servidor | mail.local |
| `POSTFIX_DOMAIN` | Dominio principal | local |
| `POSTFIX_FROM_ADDRESS` | Direccion remitente | noreply@local |
| `POSTFIX_NETWORKS` | Redes permitidas | 172.16.0.0/12 ... |
| `POSTFIX_RELAY_HOST` | Servidor SMTP relay | - |
| `POSTFIX_RELAY_PORT` | Puerto del relay | 587 |
| `POSTFIX_RELAY_USER` | Usuario para relay | - |
| `POSTFIX_RELAY_PASSWORD` | Password/App password | - |

#### PostgreSQL

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `POSTGRES_HOST` | Hostname del contenedor | postgres-messaging |
| `POSTGRES_PORT` | Puerto de PostgreSQL | 5432 |
| `POSTGRES_USER` | Usuario de BD | evolution |
| `POSTGRES_PASSWORD` | Password de BD | - |
| `POSTGRES_PASSWORD_ENCODE` | Password con URL encoding | - |
| `POSTGRES_DB` | Nombre de BD | evolutiondb |

#### Redis

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `REDIS_HOST` | Hostname del contenedor | redis-messaging |
| `REDIS_PORT` | Puerto de Redis | 6379 |
| `REDIS_PASSWORD` | Password de Redis | - |
| `REDIS_PASSWORD_ENCODE` | Password con URL encoding | - |

#### Evolution API

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `AUTHENTICATION_API_KEY` | API Key de autenticacion | - |
| `DATABASE_ENABLED` | Habilitar persistencia en BD | true |
| `DATABASE_PROVIDER` | Tipo de base de datos | postgresql |
| `DATABASE_CONNECTION_URI` | URI de conexion a PostgreSQL | - |
| `CACHE_REDIS_ENABLED` | Habilitar cache en Redis | true |
| `CACHE_REDIS_URI` | URI de conexion a Redis | - |

#### Chatwoot

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `CHATWOOT_SECRET_KEY` | Clave secreta (openssl rand -hex 64) | - |
| `CHATWOOT_URL` | URL publica de Chatwoot | http://localhost:3000 |
| `CHATWOOT_MAILER_EMAIL` | Email remitente | soporte@tudominio.com |

#### MariaDB (para Mautic)

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `MYSQL_ROOT_PASSWORD` | Password de root | - |

#### Mautic

| Variable | Descripcion | Valor por defecto |
|----------|-------------|-------------------|
| `MAUTIC_DB_NAME` | Nombre de BD | mautic |
| `MAUTIC_DB_USER` | Usuario de BD | mautic |
| `MAUTIC_DB_PASSWORD` | Password de BD | - |
| `MAUTIC_ADMIN_USER` | Usuario admin inicial | admin |
| `MAUTIC_ADMIN_PASSWORD` | Password admin inicial | - |
| `MAUTIC_ADMIN_EMAIL` | Email del admin | - |

### Passwords con Caracteres Especiales

Si tu password contiene caracteres especiales (`@`, `#`, `:`, `/`, `?`), debes usar la version URL-encoded en las URIs de conexion (`DATABASE_CONNECTION_URI` y `CACHE_REDIS_URI`).

| Caracter | URL Encode |
|----------|------------|
| `@` | `%40` |
| `#` | `%23` |
| `:` | `%3A` |
| `/` | `%2F` |
| `?` | `%3F` |

Ejemplo con password `G3XP@Ns10n`:
```bash
# Variables normales (password sin codificar)
POSTGRES_PASSWORD=G3XP@Ns10n
REDIS_PASSWORD=G3XP@Ns10n

# Variables para URIs (password con URL encoding)
POSTGRES_PASSWORD_ENCODE=G3XP%40Ns10n
REDIS_PASSWORD_ENCODE=G3XP%40Ns10n

# URIs de conexion (usar el password codificado)
DATABASE_CONNECTION_URI=postgresql://evolution:G3XP%40Ns10n@postgres-messaging:5432/evolutiondb
CACHE_REDIS_URI=redis://:G3XP%40Ns10n@redis-messaging:6379/6
```

## Uso con Nginx Proxy Manager

Ejemplo de configuracion de proxy hosts:

```
evolution.tudominio.com -> http://evolution:8080
chat.tudominio.com -> http://chatwoot:3000
marketing.tudominio.com -> http://mautic:80
```

## Correo Saliente (SMTP)

Todos los servicios (Chatwoot, Mautic) envian correo a traves de Postfix (`postfix:25`). Esto permite cambiar el metodo de envio sin modificar cada servicio.

### Modo Local (por defecto)

Postfix envia correos directamente. Util para pruebas pero puede tener problemas de entregabilidad.

### Modo Relay (recomendado para produccion)

Configura Postfix para reenviar a un servidor externo (Gmail, SendGrid, etc):

```bash
# En .env
POSTFIX_RELAY_HOST=smtp.gmail.com
POSTFIX_RELAY_PORT=587
POSTFIX_RELAY_USER=tucuenta@gmail.com
POSTFIX_RELAY_PASSWORD=tu_app_password
```

Reiniciar solo Postfix:
```bash
docker compose restart postfix
```

**Chatwoot y Mautic no necesitan cambios** - siguen enviando a `postfix:25` que reenvía al relay.

## Evolution API - Primeros Pasos

> **Nota**: Si usaste `init.sh`, la instancia de WhatsApp ya esta creada y el codigo de emparejamiento se envio por correo.

### Conectar WhatsApp via Codigo (recomendado)

```bash
# 1. Crear instancia
API_KEY=$(grep AUTHENTICATION_API_KEY .env | cut -d= -f2)
TEL=$(grep TEL_SOPORTE .env | cut -d= -f2)

docker exec mautic curl -s -X POST "http://evolution:8080/instance/create" \
  -H "apikey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "whatsapp_main",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": false,
    "number": "'"$TEL"'"
  }'

# 2. Obtener codigo de emparejamiento
docker exec mautic curl -s -X GET "http://evolution:8080/instance/connect/whatsapp_main?number=$TEL" \
  -H "apikey: $API_KEY"
```

El codigo tiene 60 segundos de validez. Ingresalo en:
1. WhatsApp → Dispositivos vinculados
2. Vincular un dispositivo
3. Vincular con numero de telefono
4. Ingresar el codigo

### Verificar conexion

```bash
docker exec mautic curl -s "http://evolution:8080/instance/connectionState/whatsapp_main" \
  -H "apikey: $API_KEY"
# Debe mostrar: {"state":"open"}
```

Documentacion oficial: https://doc.evolution-api.com

## Integracion con Orquestador

El stack messaging se integra con el stack `orquestador` (puede estar en otro servidor) para respuestas automaticas con inteligencia artificial.

### Arquitectura Multi-Servidor

```
Servidor 172.16.1.58 (mensajeria)     Servidor 172.16.1.57 (IA)
┌─────────────────────────┐           ┌─────────────────────────┐
│  Evolution API :8080    │◄─────────►│  Orquestador :8000      │
│  Chatwoot :3000         │  webhook  │  Agente IA (STT/LLM/TTS)│
│  Mautic :8081           │           │                         │
└─────────────────────────┘           └─────────────────────────┘
```

### Webhooks multiples

Evolution API soporta multiples webhooks por instancia:

| Webhook | URL | Funcion |
|---------|-----|---------|
| **Chatwoot** | Integracion nativa | Mensajes aparecen en centro de soporte |
| **Orquestador** | `http://172.16.1.57:8000/webhook/evolution` | Respuestas automaticas con IA |

Ambos webhooks funcionan en paralelo:
- Los mensajes llegan a Chatwoot para gestion humana
- El orquestador procesa mensajes y responde con IA

### Como funciona

```
Usuario WhatsApp
       │
       ▼
┌─────────────────┐
│  Evolution API  │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
Chatwoot   Orquestador
(Soporte)  (orquestador)
    │         │
    │         ▼
    │    Workers → IA
    │         │
    └────┬────┘
         ▼
   Usuario recibe
   respuesta IA
```

### Configuracion del Webhook

Configurar el webhook en Evolution Manager (`http://IP_SERVIDOR:8080/manager`):

1. Entrar a la instancia de WhatsApp
2. Ir a la seccion **Webhooks**
3. Agregar webhook:
   - **URL**: `http://172.16.1.57:8000/webhook/evolution`
   - **Events**: `MESSAGES_UPSERT`, `CONNECTION_UPDATE`

O via API:

```bash
source .env
curl -X POST "http://localhost:8080/webhook/set/whatsapp_main" \
  -H "apikey: $AUTHENTICATION_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "webhook": {
        "enabled": true,
        "url": "http://172.16.1.57:8000/webhook/evolution",
        "webhookByEvents": true,
        "webhookBase64": true,
        "events": ["MESSAGES_UPSERT"]
    }
}'
```

### Requisitos

- Orquestador debe estar corriendo en `172.16.1.57:8000`
- Stack `agente_ia` debe estar corriendo para servicios de IA (STT, LLM, TTS)
- Conectividad de red entre ambos servidores

### Verificar integracion

```bash
source .env

# Verificar webhook Orquestador
curl -s "http://localhost:8080/webhook/find/whatsapp_main" \
  -H "apikey: $AUTHENTICATION_API_KEY"

# Verificar integracion Chatwoot
curl -s "http://localhost:8080/chatwoot/find/whatsapp_main" \
  -H "apikey: $AUTHENTICATION_API_KEY"

# Verificar que orquestador responde (desde este servidor)
curl -s "http://172.16.1.57:8000/health"
```

### Tipos de mensaje soportados

| Tipo | Procesamiento |
|------|---------------|
| Texto | LLM con historial de conversacion |
| Audio | STT → LLM → TTS (responde con audio) |
| Imagen | Vision LLM (analisis de imagen) |
| Documento | PDF/Office → Vision LLM |

Ver documentacion completa en: [orquestador/README.md](../orquestador/README.md)

## Chatwoot - Primeros Pasos

> **Nota**: Si usaste `init.sh`, Chatwoot ya esta configurado. Las credenciales se muestran al final del script y se envian por correo.

### Configuracion manual (si no usaste init.sh)

```bash
# 1. Crear base de datos (usar -d evolutiondb para conectar)
docker exec -it postgres-messaging psql -U evolution -d evolutiondb -c "CREATE DATABASE chatwoot;"

# 2. Ejecutar migraciones (puede tardar 1-2 minutos)
docker compose run --rm chatwoot bundle exec rails db:chatwoot_prepare

# 3. Reiniciar Chatwoot
docker compose restart chatwoot chatwoot-sidekiq

# 4. Crear SuperAdmin
docker exec chatwoot bundle exec rails runner "SuperAdmin.create!(email: 'admin@tudominio.com', password: 'TuPassword', name: 'Admin')"
```

Ver guia completa: [CHATWOOT.md](CHATWOOT.md)

## Mautic - Primeros Pasos

Mautic requiere instalacion via CLI la primera vez:

```bash
# Instalar Mautic (esperar ~2 min a que inicie primero)
docker exec -w /var/www/html mautic sh -c 'php bin/console mautic:install "http://localhost" \
  --db_driver="pdo_mysql" \
  --db_host="mariadb-messaging" \
  --db_port="3306" \
  --db_name="mautic" \
  --db_user="mautic" \
  --db_password="TU_PASSWORD" \
  --admin_email="admin@tudominio.com" \
  --admin_password="TU_PASSWORD" \
  --admin_firstname="Admin" \
  --admin_lastname="Mautic" \
  --admin_username="admin" \
  --force'

# Habilitar API (opcional, para integraciones)
docker exec mautic sed -i "s/);/\t'api_enabled' => true,\n\t'api_enable_basic_auth' => true,\n);/" /var/www/html/config/local.php
```

Ver guia completa: [MAUTIC.md](MAUTIC.md)

## Configuracion Test Rapido

Comandos probados para verificar que el stack funciona correctamente.

> **Tip**: Para usar las variables de .env en los comandos, ejecuta primero: `source .env`

### Estado de Servicios

Cuando el stack esta funcionando correctamente, todos los servicios deben mostrar estado `healthy`:

| Contenedor | Estado | Descripcion |
|------------|--------|-------------|
| postfix | healthy | SMTP :25 |
| postgres-messaging | healthy | PostgreSQL :5432 |
| redis-messaging | healthy | Cache :6379 |
| evolution | healthy | WhatsApp API :8080 |
| chatwoot | healthy | Centro Soporte :3000 |
| chatwoot-sidekiq | running | Worker de Chatwoot |
| mariadb-messaging | healthy | MariaDB 10.11 :3306 |
| mautic | healthy | Marketing :80 |
| mautic-cron | running | Cron de Mautic |
| mautic-worker | running | Worker de Mautic |

Verificar con:
```bash
docker compose ps
```

### Regenerar codigo de WhatsApp

Si el codigo de emparejamiento expiro (60 segundos), puedes generar uno nuevo:

```bash
source .env
docker exec mautic curl -s -X GET "http://evolution:8080/instance/connect/whatsapp_main?number=$TEL_SOPORTE" \
  -H "apikey: $AUTHENTICATION_API_KEY"
```

### Nota sobre SSL en Chatwoot

Chatwoot requiere `SMTP_OPENSSL_VERIFY_MODE=none` para enviar correos a traves de Postfix (certificado auto-firmado). Esta variable ya esta configurada en `docker-compose.yaml`.

### WhatsApp (Evolution API)

```bash
# Cargar variables de entorno
source .env

# Generar nuevo codigo de emparejamiento
docker exec mautic curl -s -X GET "http://evolution:8080/instance/connect/whatsapp_main?number=$TEL_SOPORTE" \
  -H "apikey: $AUTHENTICATION_API_KEY"

# Verificar estado de conexion
docker exec mautic curl -s "http://evolution:8080/instance/connectionState/whatsapp_main" \
  -H "apikey: $AUTHENTICATION_API_KEY"

# Enviar mensaje de WhatsApp (requiere instancia conectada)
docker exec mautic curl -s -X POST "http://evolution:8080/message/sendText/whatsapp_main" \
  -H "apikey: $AUTHENTICATION_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "'"$TEL_SOPORTE"'",
    "text": "Mensaje de prueba desde Evolution API"
  }'
```

### Email (Postfix)

```bash
# Cargar variables de entorno
source .env

# Enviar correo de prueba directo via Postfix
docker exec postfix sh -c "echo 'Subject: Prueba Messaging Stack
From: noreply@$POSTFIX_DOMAIN
To: $EMAIL_SOPORTE
Content-Type: text/plain; charset=UTF-8

Este es un mensaje de prueba desde Postfix.

---
Messaging Stack' | sendmail -t"
```

### Chatwoot

```bash
# Crear SuperAdmin (via archivo para evitar problemas de escape)
docker exec chatwoot sh -c 'cat > /tmp/setup.rb << "RUBY"
SuperAdmin.create!(email: "admin@tudominio.com", password: "TuPassword", name: "Admin")
RUBY
bundle exec rails runner /tmp/setup.rb'

# Crear Account, User y obtener API Token
docker exec chatwoot sh -c 'cat > /tmp/api.rb << "RUBY"
account = Account.first || Account.create!(name: "Mi Empresa", locale: "es")
user = User.find_by(email: "admin@tudominio.com") || User.create!(
  email: "admin@tudominio.com", password: "TuPassword", name: "Admin", confirmed_at: Time.current
)
AccountUser.find_or_create_by!(user: user, account: account) { |m| m.role = :administrator }
token = user.access_token&.token || user.create_access_token!(token: SecureRandom.hex(32)).token
puts "Account ID: #{account.id}"
puts "API Token: #{token}"
RUBY
bundle exec rails runner /tmp/api.rb'

# Crear inbox de email
curl -X POST "http://chatwoot:3000/api/v1/accounts/1/inboxes" \
  -H "api_access_token: TU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Email","channel":{"type":"email","email":"soporte@local"}}'

# Enviar WhatsApp desde Chatwoot (via Evolution API)
docker exec chatwoot wget -q -O- \
  --post-data='{"number":"521XXXXXXXXXX","text":"Mensaje desde Chatwoot"}' \
  --header="apikey: TU_API_KEY" \
  --header="Content-Type: application/json" \
  "http://evolution:8080/message/sendText/whatsapp_main"
```

### Mautic

```bash
# Verificar instalacion
docker exec mautic curl -s http://localhost/s/login | grep -q "Mautic" && echo "Mautic OK"

# Crear contacto via API (requiere API habilitada)
curl -X POST "http://mautic:80/api/contacts/new" \
  -u "admin:TuPassword" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@ejemplo.com","firstname":"Test"}'
```

## Comandos Utiles

```bash
# Ver estado de los servicios
docker compose ps

# Ver logs de todos los servicios
docker compose logs -f

# Ver logs de un servicio especifico
docker compose logs -f evolution

# Reconstruir imagen de Postfix
docker compose build postfix

# Reiniciar Evolution API
docker compose restart evolution

# Enviar correo de prueba
docker exec -it postfix bash -c 'echo "Test" | mail -s "Prueba" usuario@example.com'

# Verificar cola de correo
docker exec -it postfix mailq
```

## Troubleshooting

### Postfix no inicia
- Verificar configuracion en `.env`
- Revisar logs: `docker compose logs postfix`

### Correos no se envian
- Verificar conectividad: `docker exec -it postfix ping smtp.gmail.com`
- Verificar credenciales del relay
- Revisar cola: `docker exec -it postfix mailq`

### Evolution API no conecta a WhatsApp
- Verificar que PostgreSQL y Redis esten healthy
- Revisar logs: `docker compose logs evolution`
- Verificar API Key correcta

### Error de base de datos
- Verificar que PostgreSQL este corriendo: `docker compose ps postgres`
- Revisar logs: `docker compose logs postgres`

### Chatwoot reinicia constantemente

1. **Falta base de datos chatwoot**:
   ```bash
   docker exec -it postgres-messaging psql -U evolution -d evolutiondb -c "CREATE DATABASE chatwoot;"
   docker compose run --rm chatwoot bundle exec rails db:chatwoot_prepare
   ```

2. **Error de Redis URL** (password con @):
   - Verificar que `REDIS_PASSWORD_ENCODE` tenga el password con URL encoding
   - El `@` debe ser `%40` en la URL

3. **Error pgvector**:
   - Verificar que PostgreSQL use imagen `pgvector/pgvector:pg15`
   - Si cambiaste de `postgres:15-alpine`, recrear el contenedor

### Mautic redirige al instalador

Esto es normal la primera vez. Completar el wizard web:
- La conexion a BD ya esta configurada via variables de entorno
- Usar credenciales de `.env` para el admin

### Mautic no envia emails

```bash
# Verificar worker
docker compose logs mautic-worker

# Procesar cola manualmente
docker exec -it mautic php bin/console messenger:consume email
```

## Licencia

MIT License
