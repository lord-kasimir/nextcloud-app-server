#!/bin/bash
# Setup-Script für den Traefik-Stack:
# - generiert Passwort + bcrypt-Hash für Dashboard-Auth
# - schreibt .env automatisch
# - speichert Klartext-Credentials in credentials.txt
# - zeigt am Ende alle Werte am Bildschirm

set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Traefik-Setup ===${NC}"
echo ""

# Sicherheits-Check: bestehende .env nicht überschreiben
if [ -f .env ]; then
    echo -e "${RED}.env existiert bereits.${NC} Vorher entfernen oder Backup machen falls neu erzeugt werden soll."
    exit 1
fi

# Eingaben
read -rp "Domain für das Traefik-Dashboard (z. B. traefik.example.com): " TRAEFIK_DOMAIN
read -rp "E-Mail-Adresse für Let's-Encrypt-Account: " ACME_EMAIL
read -rp "Username für das Dashboard [admin]: " DASHBOARD_USER
DASHBOARD_USER=${DASHBOARD_USER:-admin}

# Passwort generieren
DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

echo ""
echo "Generiere bcrypt-Hash für Dashboard-Auth..."

# bcrypt-Hash via httpd:alpine erzeugen (kein lokales htpasswd nötig)
HASH=$(docker run --rm httpd:alpine htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASSWORD" | cut -d: -f2)

# In Traefik-Labels werden $-Zeichen verdoppelt benötigt
HASH_ESCAPED=$(echo "$HASH" | sed 's/\$/\$\$/g')

# .env schreiben
cat > .env <<EOF
ACME_EMAIL=$ACME_EMAIL
TRAEFIK_DOMAIN=$TRAEFIK_DOMAIN
DASHBOARD_AUTH=$DASHBOARD_USER:$HASH_ESCAPED
EOF
chmod 600 .env

# acme.json + Logs-Verzeichnis vorbereiten
touch acme.json
chmod 600 acme.json
mkdir -p logs

# Klartext-Credentials zusätzlich speichern
cat > credentials.txt <<EOF
=== Traefik Dashboard ===
URL:      https://$TRAEFIK_DOMAIN
User:     $DASHBOARD_USER
Passwort: $DASHBOARD_PASSWORD

=== Let's Encrypt ===
E-Mail:   $ACME_EMAIL

Erstellt: $(date '+%Y-%m-%d %H:%M:%S')
EOF
chmod 600 credentials.txt

# Anzeige am Bildschirm
echo ""
echo -e "${GREEN}=== Erstellt ===${NC}"
echo ""
cat credentials.txt
echo ""
echo -e "${YELLOW}WICHTIG:${NC} credentials.txt enthält die Klartext-Passwörter (chmod 600). Sicher aufbewahren oder nach Notation löschen."
echo ""
echo "Nächster Schritt: Traefik starten mit"
echo "  docker compose up -d"
echo ""
echo "Voraussetzung: Docker-Netzwerk 'traefik-public' existiert (siehe host-setup.md)."
