# Nextcloud-Instanz: cloud.example.com

Eine NC-Instanz im Multi-Domain-Setup. Wird vom zentralen Traefik (siehe `../../proxy`) automatisch erkannt und mit Let's-Encrypt-Zertifikat versorgt.

## Voraussetzungen

- Traefik-Stack läuft (siehe `proxy/README.md`)
- Docker-Netz `traefik-public` existiert
- DNS-A-Record für `cloud.example.com` zeigt auf die App-Server-IP
- NFS-Mount auf `/mnt/nextcloud-data` ist eingerichtet
- DB auf DB-Server (<DB_SERVER_IP>, MariaDB) erreichbar via Cloud Network

## Setup

```bash
# 1. .env aus Vorlage erstellen und ausfüllen
cp .env.example .env
nano .env   # DB_HOST = private IP, DB_PASSWORD = neues Passwort

# 2. Stack starten
docker compose up -d

# 3. Traefik holt automatisch das Zertifikat (kann 30–60 Sek. dauern)
docker logs -f nc-example-web

# 4. Erster Aufruf: https://cloud.example.com
#    Bei Migration: config.php aus alter Instanz übernehmen, files:scan laufen lassen
```

## Nextcloud-CLI (occ)

```bash
docker compose exec --user www-data nextcloud php occ status
docker compose exec --user www-data nextcloud php occ files:scan --all
docker compose exec --user www-data nextcloud php occ db:add-missing-indices
```

## Eine zweite Instanz hinzufügen

```bash
# Im /instances Ordner: bestehenden Ordner duplizieren
cp -r example beispielschule
cd beispielschule

# .env anpassen — neuer DOMAIN, neue DB
nano .env

# In docker-compose.yml: alle Container-Namen `nc-example-*` durch
# `nc-beispielschule-*` ersetzen, ebenso die Router-Namen `example` → `beispielschule`
sed -i '' 's/example/beispielschule/g' docker-compose.yml

# Starten
docker compose up -d
```

Traefik erkennt die neue Instanz automatisch über die Labels und holt ein eigenes SSL-Zertifikat.
