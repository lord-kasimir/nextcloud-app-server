#!/bin/bash
# Setup-Script für eine Nextcloud-Instanz:
# - generiert sicheres DB-Passwort
# - schreibt .env automatisch
# - generiert SQL für DB+User-Anlage auf dem DB-Server
# - speichert Klartext-Credentials in credentials.txt
# - zeigt am Ende alle Werte am Bildschirm

set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTANCE=$(basename "$(pwd)")

echo -e "${GREEN}=== Nextcloud-Instanz '$INSTANCE' einrichten ===${NC}"
echo ""

# Sicherheits-Check: bestehende .env nicht überschreiben
if [ -f .env ]; then
    echo -e "${RED}.env existiert bereits.${NC} Vorher entfernen oder Backup machen falls neu erzeugt werden soll."
    exit 1
fi

# Eingaben
read -rp "Domain für diese NC-Instanz (z. B. cloud.example.com): " DOMAIN
read -rp "Private IP des DB-Servers (im Cloud Network, z. B. 10.0.0.5): " DB_HOST

# DB-Name + User aus Instanz-Namen ableiten (alphanumerisch + underscores)
# printf statt echo, damit kein abschließender Newline reinrutscht und tr ihn
# als ungültiges Zeichen durch '_' ersetzt (= trailing underscore-Bug)
SAFE_NAME=$(printf '%s' "$INSTANCE" | tr -c 'a-zA-Z0-9_' '_' | head -c 32)
DB_NAME="db_${SAFE_NAME}"
DB_USER="user_${SAFE_NAME}"

# DB-Passwort generieren
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# Optional: NC-Admin-Credentials erfragen
read -rp "Nextcloud-Admin-Username [admin]: " NC_ADMIN
NC_ADMIN=${NC_ADMIN:-admin}
NC_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# .env schreiben
cat > .env <<EOF
DOMAIN=$DOMAIN

DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD

NEXTCLOUD_ADMIN_USER=$NC_ADMIN
NEXTCLOUD_ADMIN_PASSWORD=$NC_ADMIN_PASSWORD
EOF
chmod 600 .env

# SQL-Datei für den DB-Server erzeugen
APP_SERVER_HINT='<APP_SERVER_PRIVATE_IP>'
cat > db-create.sql <<EOF
-- Auf dem DB-Server ausführen (mysql -uroot < db-create.sql)
-- Vor dem Ausführen: Platzhalter $APP_SERVER_HINT durch die private IP des App-Servers ersetzen.

CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$DB_USER'@'$APP_SERVER_HINT' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$APP_SERVER_HINT';
FLUSH PRIVILEGES;
EOF
chmod 600 db-create.sql

# Credentials-Datei
cat > credentials.txt <<EOF
=== Nextcloud-Instanz: $INSTANCE ===
URL:               https://$DOMAIN

=== Datenbank ===
Host:              $DB_HOST
Name:              $DB_NAME
User:              $DB_USER
Passwort:          $DB_PASSWORD

=== Nextcloud-Admin ===
User:              $NC_ADMIN
Passwort:          $NC_ADMIN_PASSWORD

Erstellt: $(date '+%Y-%m-%d %H:%M:%S')
EOF
chmod 600 credentials.txt

# Anzeige am Bildschirm
echo ""
echo -e "${GREEN}=== Erstellt ===${NC}"
echo ""
cat credentials.txt
echo ""
echo -e "${YELLOW}NÄCHSTE SCHRITTE:${NC}"
echo ""
echo "1. db-create.sql auf den DB-Server übertragen, '$APP_SERVER_HINT' durch private IP des App-Servers ersetzen, ausführen:"
echo "     scp db-create.sql user@db-server:/tmp/"
echo "     ssh user@db-server 'sudo sed -i \"s|<APP_SERVER_PRIVATE_IP>|10.0.0.X|g\" /tmp/db-create.sql && sudo mysql -uroot < /tmp/db-create.sql'"
echo ""
echo "2. NFS-Mount auf /mnt/nextcloud-data muss aktiv sein (siehe host-setup.md)"
echo ""
echo "3. Stack starten:"
echo "     docker compose up -d"
echo ""
echo "4. credentials.txt sicher aufbewahren — enthält alle Klartext-Passwörter (chmod 600)."
