#!/bin/bash

# =============================================================
# Script de inicializacion para Messaging Stack
# Configura automaticamente: Evolution, Chatwoot, Mautic
# =============================================================

set -e

echo "=== Inicializando Messaging Stack ==="

# Crear directorios de datos
echo "Creando directorios de datos..."
mkdir -p stack_data/postfix/{spool,mail}
mkdir -p stack_data/postgres/data
mkdir -p stack_data/redis/data
mkdir -p stack_data/mariadb/data
mkdir -p stack_data/evolution/instances
mkdir -p stack_data/chatwoot/storage
mkdir -p stack_data/mautic/{config,logs,media}

# Copiar archivo de entorno si no existe
if [ ! -f .env ]; then
    echo "Creando .env desde plantilla..."
    cp .env.example .env

    # Generar claves y passwords automaticamente
    echo "Generando claves y passwords seguras..."
    EVOLUTION_KEY=$(openssl rand -hex 32)
    CHATWOOT_KEY=$(openssl rand -hex 64)
    # Password alfanumerico sin caracteres especiales (evita problemas de URL encoding)
    DB_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)

    # Reemplazar claves API
    sed -i "s/GENERAR_API_KEY_SEGURA/$EVOLUTION_KEY/" .env
    sed -i "s/GENERAR_SECRET_KEY/$CHATWOOT_KEY/" .env

    # Reemplazar passwords (mismo password para simplificar)
    sed -i "s/CAMBIAR_PASSWORD_ENCODE/$DB_PASSWORD/g" .env
    sed -i "s/CAMBIAR_PASSWORD/$DB_PASSWORD/g" .env

    echo ""
    echo "=== Credenciales Generadas ==="
    echo "Password BD/Redis: $DB_PASSWORD"
    echo "Evolution API Key: $EVOLUTION_KEY"
    echo ""
    echo "IMPORTANTE: Guarda estas credenciales en un lugar seguro"
    echo "            Tambien puedes verlas en el archivo .env"
    echo ""
fi

# Cargar variables de entorno
source .env

# Verificar variables requeridas
if [ -z "$TEL_SOPORTE" ] || [ "$TEL_SOPORTE" = "521XXXXXXXXXX" ]; then
    echo "ERROR: Configura TEL_SOPORTE en .env (ej: 5215510771180)"
    exit 1
fi

if [ -z "$EMAIL_SOPORTE" ] || [ "$EMAIL_SOPORTE" = "admin@tudominio.com" ]; then
    echo "ERROR: Configura EMAIL_SOPORTE en .env (ej: admin@empresa.com)"
    exit 1
fi

# Verificar red externa
if ! docker network inspect vpn-proxy >/dev/null 2>&1; then
    echo "ADVERTENCIA: La red 'vpn-proxy' no existe"
    echo "Creala con: docker network create vpn-proxy"
    exit 1
fi

# Construir imagenes
echo "Construyendo imagenes..."
docker compose build

# Iniciar servicios
echo "Iniciando servicios..."
docker compose up -d

# =============================================================
# POSTGRESQL
# =============================================================
echo ""
echo "Esperando a que PostgreSQL este listo..."
until docker exec postgres-messaging pg_isready -U evolution -d evolutiondb > /dev/null 2>&1; do
    sleep 2
done
echo "PostgreSQL listo."

# =============================================================
# CHATWOOT
# =============================================================
echo ""
echo "=== Configurando Chatwoot ==="
echo "Creando base de datos chatwoot..."
docker exec postgres-messaging psql -U evolution -d evolutiondb -c "CREATE DATABASE chatwoot;" 2>/dev/null || true

echo "Ejecutando migraciones (esto puede tardar 1-2 minutos)..."
docker compose run --rm chatwoot bundle exec rails db:chatwoot_prepare 2>&1 | tail -5

echo "Reiniciando Chatwoot..."
docker compose restart chatwoot chatwoot-sidekiq

echo "Esperando a que Chatwoot este listo..."
sleep 10
until docker exec chatwoot wget -q --spider http://127.0.0.1:3000/api 2>/dev/null; do
    sleep 5
done
echo "Chatwoot listo."

# Crear SuperAdmin en Chatwoot
echo "Creando SuperAdmin en Chatwoot..."
CHATWOOT_ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
docker exec chatwoot bundle exec rails runner "SuperAdmin.create!(email: '$EMAIL_SOPORTE', password: '$CHATWOOT_ADMIN_PASSWORD', name: 'Admin')" 2>/dev/null || echo "SuperAdmin ya existe"

# Crear Account, User y obtener access_token
echo "Configurando cuenta y usuario en Chatwoot..."
# Password con caracter especial (requerido por Chatwoot)
CHATWOOT_USER_PASSWORD="${CHATWOOT_ADMIN_PASSWORD}@"

# Crear script Ruby temporal (evita problemas de escape en bash)
cat > /tmp/chatwoot_setup.rb << 'RUBY_EOF'
account = Account.find_or_create_by!(name: "Soporte")
puts "ACCOUNT_ID=#{account.id}"

user = User.find_by(email: ENV["CW_EMAIL"])
if user.nil?
  user = User.create!(
    email: ENV["CW_EMAIL"],
    password: ENV["CW_PASSWORD"],
    name: "Admin",
    confirmed_at: Time.now
  )
end

unless AccountUser.exists?(account: account, user: user)
  AccountUser.create!(account: account, user: user, role: :administrator)
end

user.create_access_token! if user.access_token.nil?
puts "ACCESS_TOKEN=#{user.access_token.token}"
RUBY_EOF

docker cp /tmp/chatwoot_setup.rb chatwoot:/tmp/chatwoot_setup.rb
CHATWOOT_SETUP=$(docker exec -e CW_EMAIL="$EMAIL_SOPORTE" -e CW_PASSWORD="$CHATWOOT_USER_PASSWORD" chatwoot bundle exec rails runner /tmp/chatwoot_setup.rb 2>/dev/null)

# Extraer valores
CHATWOOT_ACCOUNT_ID=$(echo "$CHATWOOT_SETUP" | grep "ACCOUNT_ID=" | cut -d'=' -f2)
CHATWOOT_ACCESS_TOKEN=$(echo "$CHATWOOT_SETUP" | grep "ACCESS_TOKEN=" | cut -d'=' -f2)

if [ -n "$CHATWOOT_ACCOUNT_ID" ] && [ -n "$CHATWOOT_ACCESS_TOKEN" ]; then
    echo "Account ID: $CHATWOOT_ACCOUNT_ID"
    echo "Access Token obtenido."
else
    echo "Error obteniendo credenciales de Chatwoot. Integracion manual requerida."
fi

# =============================================================
# POSTFIX
# =============================================================
echo ""
echo "Esperando a que Postfix este listo..."
until docker exec postfix postfix status > /dev/null 2>&1; do
    sleep 2
done
echo "Postfix listo."

# =============================================================
# EVOLUTION API (WhatsApp)
# =============================================================
echo ""
echo "=== Configurando Evolution API ==="
echo "Esperando a que Evolution API este listo..."
until docker exec mautic curl -s http://evolution:8080/ > /dev/null 2>&1; do
    sleep 5
done
echo "Evolution API listo."

# Crear instancia de WhatsApp
echo "Creando instancia de WhatsApp..."
INSTANCE_RESPONSE=$(docker exec mautic curl -s -X POST "http://evolution:8080/instance/create" \
    -H "apikey: $AUTHENTICATION_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "instanceName": "whatsapp_main",
        "integration": "WHATSAPP-BAILEYS",
        "qrcode": false,
        "number": "'"$TEL_SOPORTE"'"
    }' 2>/dev/null || echo '{"error":"exists"}')

if echo "$INSTANCE_RESPONSE" | grep -q "error"; then
    echo "Instancia ya existe o error: $INSTANCE_RESPONSE"
else
    echo "Instancia creada."
fi

# Obtener codigo de emparejamiento
echo "Generando codigo de emparejamiento..."
sleep 3
PAIRING_RESPONSE=$(docker exec mautic curl -s -X GET "http://evolution:8080/instance/connect/whatsapp_main?number=$TEL_SOPORTE" \
    -H "apikey: $AUTHENTICATION_API_KEY" 2>/dev/null)

PAIRING_CODE=$(echo "$PAIRING_RESPONSE" | grep -o '"pairingCode":"[^"]*"' | cut -d'"' -f4)

if [ -n "$PAIRING_CODE" ]; then
    echo ""
    echo "=================================================="
    echo "  CODIGO DE EMPAREJAMIENTO: $PAIRING_CODE"
    echo "=================================================="
    echo ""

    # Enviar codigo por correo via Postfix
    echo "Enviando codigo por correo a $EMAIL_SOPORTE..."
    docker exec postfix sh -c "echo 'Subject: Codigo WhatsApp Messaging Stack
From: noreply@$POSTFIX_DOMAIN
To: $EMAIL_SOPORTE
Content-Type: text/plain; charset=UTF-8

Codigo de emparejamiento WhatsApp: $PAIRING_CODE

Instrucciones:
1. Abre WhatsApp en tu celular
2. Ve a Dispositivos vinculados
3. Selecciona Vincular con numero de telefono
4. Ingresa el codigo: $PAIRING_CODE

El codigo expira en 60 segundos.

---
Messaging Stack' | sendmail -t" 2>/dev/null && echo "Correo enviado." || echo "Error enviando correo."

else
    echo "No se pudo obtener codigo. Respuesta: $PAIRING_RESPONSE"
    echo "Puedes generar uno manualmente mas tarde."
fi

# =============================================================
# INTEGRACION CHATWOOT + EVOLUTION
# =============================================================
echo ""
echo "=== Configurando integracion Chatwoot + Evolution ==="

if [ -n "$CHATWOOT_ACCOUNT_ID" ] && [ -n "$CHATWOOT_ACCESS_TOKEN" ]; then
    # Crear inbox API en Chatwoot para WhatsApp y asignar agente
    echo "Creando inbox WhatsApp en Chatwoot..."

    # Script Ruby para crear inbox y asignar agente
    cat > /tmp/chatwoot_inbox.rb << 'RUBY_EOF'
account = Account.find(ENV["CW_ACCOUNT_ID"].to_i)

inbox = account.inboxes.find_by(name: "WhatsApp")
if inbox.nil?
  channel = Channel::Api.create!(account: account)
  inbox = Inbox.create!(
    name: "WhatsApp",
    account: account,
    channel: channel,
    enable_auto_assignment: true
  )
  puts "INBOX_ID=#{inbox.id}"
  puts "CREATED=true"
else
  puts "INBOX_ID=#{inbox.id}"
  puts "CREATED=false"
end

# Asignar agente al inbox
user = account.users.first
unless InboxMember.exists?(inbox: inbox, user: user)
  InboxMember.create!(inbox: inbox, user: user)
  puts "AGENT_ASSIGNED=true"
else
  puts "AGENT_ASSIGNED=false"
end
RUBY_EOF

    docker cp /tmp/chatwoot_inbox.rb chatwoot:/tmp/chatwoot_inbox.rb
    INBOX_RESPONSE=$(docker exec -e CW_ACCOUNT_ID="$CHATWOOT_ACCOUNT_ID" chatwoot bundle exec rails runner /tmp/chatwoot_inbox.rb 2>/dev/null)

    CHATWOOT_INBOX_ID=$(echo "$INBOX_RESPONSE" | grep "INBOX_ID=" | cut -d'=' -f2)
    INBOX_CREATED=$(echo "$INBOX_RESPONSE" | grep "CREATED=" | cut -d'=' -f2)

    if [ "$INBOX_CREATED" = "true" ]; then
        echo "Inbox WhatsApp creado (ID: $CHATWOOT_INBOX_ID)"
    else
        echo "Inbox WhatsApp ya existe (ID: $CHATWOOT_INBOX_ID)"
    fi
    echo "Agente asignado al inbox."

    # Configurar Evolution API con Chatwoot
    if [ -n "$CHATWOOT_INBOX_ID" ]; then
        echo "Configurando Evolution con Chatwoot..."

        # Determinar URL de Chatwoot (interna Docker)
        CHATWOOT_INTERNAL_URL="http://chatwoot:3000"

        EVOLUTION_CHATWOOT_RESPONSE=$(docker exec mautic curl -s -X POST "http://evolution:8080/chatwoot/set/whatsapp_main" \
            -H "apikey: $AUTHENTICATION_API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "enabled": true,
                "accountId": "'"$CHATWOOT_ACCOUNT_ID"'",
                "token": "'"$CHATWOOT_ACCESS_TOKEN"'",
                "url": "'"$CHATWOOT_INTERNAL_URL"'",
                "signMsg": true,
                "reopenConversation": true,
                "conversationPending": false,
                "nameInbox": "WhatsApp",
                "mergeBrazilContacts": true,
                "importContacts": true,
                "importMessages": true,
                "daysLimitImportMessages": 3,
                "autoCreate": true
            }' 2>/dev/null)

        if echo "$EVOLUTION_CHATWOOT_RESPONSE" | grep -q '"enabled":true'; then
            echo "Integracion Chatwoot + Evolution configurada correctamente."
        else
            echo "Error configurando integracion: $EVOLUTION_CHATWOOT_RESPONSE"
        fi
    fi
else
    echo "No se pudo configurar integracion (faltan credenciales Chatwoot)."
    echo "Configura manualmente desde la UI de Chatwoot."
fi

# =============================================================
# ORQUESTADOR - WEBHOOK
# =============================================================
echo ""
echo "=== Configurando webhook Orquestador ==="

# Configurar webhook en Evolution para Orquestador (se registra aunque no este disponible)
ORQUESTADOR_URL="http://orquestador:80"
echo "Registrando webhook: $ORQUESTADOR_URL/webhook/evolution"

WEBHOOK_RESPONSE=$(docker exec mautic curl -s -X POST "http://evolution:8080/webhook/set/whatsapp_main" \
    -H "apikey: $AUTHENTICATION_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "webhook": {
            "enabled": true,
            "url": "'"$ORQUESTADOR_URL"'/webhook/evolution",
            "webhookByEvents": true,
            "webhookBase64": true,
            "events": ["MESSAGES_UPSERT"]
        }
    }' 2>/dev/null)

if echo "$WEBHOOK_RESPONSE" | grep -q '"enabled":true'; then
    echo "Webhook Orquestador configurado correctamente."
    echo "  URL: $ORQUESTADOR_URL/webhook/evolution"
    echo "  Eventos: MESSAGES_UPSERT"
else
    echo "Error configurando webhook: $WEBHOOK_RESPONSE"
fi

# Verificar disponibilidad del orquestador (solo informativo)
if docker exec mautic curl -s "$ORQUESTADOR_URL/health" > /dev/null 2>&1; then
    echo "Orquestador: DISPONIBLE"
else
    echo "Orquestador: NO DISPONIBLE (se activara cuando inicie el stack orquestador)"
fi

# =============================================================
# MAUTIC
# =============================================================
echo ""
echo "=== Verificando Mautic ==="
echo "Esperando a que Mautic este listo (puede tardar 2-3 min)..."
MAUTIC_TRIES=0
until docker exec mautic curl -s http://localhost/s/login | grep -q "Mautic" 2>/dev/null; do
    sleep 10
    MAUTIC_TRIES=$((MAUTIC_TRIES + 1))
    if [ $MAUTIC_TRIES -gt 18 ]; then
        echo "Mautic tarda en iniciar, continuando..."
        break
    fi
done
echo "Mautic listo."

# =============================================================
# MENSAJES DE PRUEBA
# =============================================================
echo ""
echo "=== Enviando mensajes de prueba ==="

# Usar TEL_TEST si esta definido, si no usar TEL_SOPORTE
DESTINATARIO_TEST="${TEL_TEST:-$TEL_SOPORTE}"

# Esperar a que WhatsApp se conecte (si el codigo fue ingresado)
echo "Esperando 30 segundos para conexion de WhatsApp..."
sleep 30

# Verificar estado de WhatsApp
WA_STATUS=$(docker exec mautic curl -s "http://evolution:8080/instance/connectionState/whatsapp_main" \
    -H "apikey: $AUTHENTICATION_API_KEY" 2>/dev/null)

if echo "$WA_STATUS" | grep -q '"state":"open"'; then
    echo "WhatsApp conectado. Enviando mensaje de prueba a $DESTINATARIO_TEST..."
    docker exec mautic curl -s -X POST "http://evolution:8080/message/sendText/whatsapp_main" \
        -H "apikey: $AUTHENTICATION_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "number": "'"$DESTINATARIO_TEST"'",
            "text": "Messaging Stack configurado correctamente.\n\nServicios activos:\n- Postfix (SMTP)\n- Evolution API (WhatsApp)\n- Chatwoot (Soporte)\n- Mautic (Marketing)"
        }' > /dev/null 2>&1 && echo "WhatsApp enviado." || echo "Error enviando WhatsApp."
else
    echo "WhatsApp no conectado aun. Estado: $WA_STATUS"
    echo "Ingresa el codigo de emparejamiento para conectar."
fi

# Enviar correo de prueba via Postfix
echo "Enviando correo de prueba..."
docker exec postfix sh -c "echo 'Subject: Messaging Stack - Configuracion Completa
From: noreply@$POSTFIX_DOMAIN
To: $EMAIL_SOPORTE
Content-Type: text/plain; charset=UTF-8

El Messaging Stack ha sido configurado correctamente.

Servicios activos:
- Postfix (SMTP)
- PostgreSQL + Redis
- Evolution API (WhatsApp)
- Chatwoot (Centro de Soporte)
- Mautic (Marketing Automation)

Credenciales Chatwoot:
- URL: http://localhost:3000
- Email: $EMAIL_SOPORTE
- Password: $CHATWOOT_ADMIN_PASSWORD

Credenciales Mautic:
- URL: http://localhost (puerto 80 interno)
- Usuario: $MAUTIC_ADMIN_USER
- Password: $MAUTIC_ADMIN_PASSWORD

Integracion Chatwoot + WhatsApp:
- Los mensajes de WhatsApp apareceran automaticamente en Chatwoot
- Inbox: WhatsApp

---
Messaging Stack' | sendmail -t" 2>/dev/null && echo "Correo enviado." || echo "Error enviando correo."

# =============================================================
# RESUMEN FINAL
# =============================================================
echo ""
echo "=========================================="
echo "   MESSAGING STACK - CONFIGURACION"
echo "=========================================="
echo ""
docker compose ps
echo ""
echo "=== Credenciales ==="
echo ""
echo "CHATWOOT:"
echo "  URL: http://localhost:3000"
echo "  Email: $EMAIL_SOPORTE"
echo "  Password: $CHATWOOT_ADMIN_PASSWORD"
echo ""
echo "MAUTIC:"
echo "  URL: http://localhost (interno)"
echo "  Usuario: $MAUTIC_ADMIN_USER"
echo "  Password: $MAUTIC_ADMIN_PASSWORD"
echo ""
echo "EVOLUTION API:"
echo "  URL: http://localhost:8080 (interno)"
echo "  API Key: $AUTHENTICATION_API_KEY"
echo ""
if [ -n "$PAIRING_CODE" ]; then
    echo "WHATSAPP:"
    echo "  Codigo: $PAIRING_CODE"
    echo "  (El codigo expira en 60 segundos)"
    echo ""
fi
echo "INTEGRACION CHATWOOT + EVOLUTION:"
if [ -n "$CHATWOOT_INBOX_ID" ]; then
    echo "  Estado: Configurada"
    echo "  Inbox: WhatsApp (ID: $CHATWOOT_INBOX_ID)"
    echo "  Los mensajes de WhatsApp apareceran en Chatwoot"
else
    echo "  Estado: No configurada (configurar manualmente)"
fi
echo ""
echo "ORQUESTADOR (si esta disponible):"
echo "  Webhook: http://orquestador:80/webhook/evolution"
echo "  Eventos: MESSAGES_UPSERT"
echo "  El orquestador procesa mensajes y responde con IA"
echo ""
echo "Se enviaron las credenciales a: $EMAIL_SOPORTE"
echo ""
echo "=========================================="
