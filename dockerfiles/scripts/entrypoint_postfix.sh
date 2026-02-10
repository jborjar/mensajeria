#!/bin/bash
set -e

# Configuración base de Postfix
HOSTNAME=${POSTFIX_HOSTNAME:-mail.local}
DOMAIN=${POSTFIX_DOMAIN:-local}
NETWORKS=${POSTFIX_NETWORKS:-"172.16.0.0/12 192.168.0.0/16 10.0.0.0/8"}
FROM_ADDRESS=${POSTFIX_FROM_ADDRESS:-noreply@$DOMAIN}

# Configuración de relay (opcional)
RELAY_HOST=${POSTFIX_RELAY_HOST:-}
RELAY_PORT=${POSTFIX_RELAY_PORT:-587}
RELAY_USER=${POSTFIX_RELAY_USER:-}
RELAY_PASSWORD=${POSTFIX_RELAY_PASSWORD:-}

echo "Configurando Postfix..."
echo "  Hostname: $HOSTNAME"
echo "  Domain: $DOMAIN"
echo "  Networks: $NETWORKS"
echo "  From: $FROM_ADDRESS"

# Configuración principal
postconf -e "myhostname = $HOSTNAME"
postconf -e "mydomain = $DOMAIN"
postconf -e "myorigin = \$mydomain"

# Reescribir remitente para correos locales (envelope y headers)
postconf -e "smtp_generic_maps = hash:/etc/postfix/generic"
postconf -e "smtp_header_checks = regexp:/etc/postfix/header_checks"
echo "root@postfix $FROM_ADDRESS" > /etc/postfix/generic
echo "root $FROM_ADDRESS" >> /etc/postfix/generic
echo "@postfix @$DOMAIN" >> /etc/postfix/generic
postmap /etc/postfix/generic

# Reescribir header From (cualquier remitente local)
cat > /etc/postfix/header_checks << EOF
/^From:.*root.*/ REPLACE From: $FROM_ADDRESS
/^From:.*@postfix.*/ REPLACE From: $FROM_ADDRESS
/^From:.*@localhost.*/ REPLACE From: $FROM_ADDRESS
EOF
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
postconf -e "mynetworks = 127.0.0.0/8 $NETWORKS"
postconf -e "smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination"

# Configuración de seguridad básica
postconf -e "smtpd_banner = \$myhostname ESMTP"
postconf -e "biff = no"
postconf -e "append_dot_mydomain = no"
postconf -e "readme_directory = no"

# Configuración de relay externo (si está configurado)
if [ -n "$RELAY_HOST" ]; then
    echo "Configurando relay externo: $RELAY_HOST:$RELAY_PORT"
    postconf -e "relayhost = [$RELAY_HOST]:$RELAY_PORT"

    if [ -n "$RELAY_USER" ] && [ -n "$RELAY_PASSWORD" ]; then
        echo "Configurando autenticación SASL para relay..."
        postconf -e "smtp_sasl_auth_enable = yes"
        postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
        postconf -e "smtp_sasl_security_options = noanonymous"
        postconf -e "smtp_tls_security_level = encrypt"
        postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

        # Crear archivo de credenciales
        echo "[$RELAY_HOST]:$RELAY_PORT $RELAY_USER:$RELAY_PASSWORD" > /etc/postfix/sasl_passwd
        postmap /etc/postfix/sasl_passwd
        chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
    fi
else
    echo "Modo envío directo (sin relay)"
    postconf -e "relayhost ="
fi

# Usar DNS interno de Docker (funciona con VPN)
# No sobrescribir /etc/resolv.conf - Docker lo configura correctamente

# Crear directorios necesarios
mkdir -p /var/spool/postfix/pid
mkdir -p /var/spool/postfix/etc

# Copiar resolv.conf al chroot de Postfix
cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf
chown root:root /var/spool/postfix/pid

# Iniciar Postfix en primer plano
echo "Iniciando Postfix..."
postfix start-fg
