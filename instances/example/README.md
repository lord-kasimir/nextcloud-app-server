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

**Vorab:** A-Record für die neue Domain auf die App-Server-IP setzen — sonst kann Traefik kein Let's-Encrypt-Zertifikat holen.

```bash
# Im /instances Ordner: bestehenden Ordner duplizieren
cp -r example beispielschule
cd beispielschule

# Container-/Router-Namen umbenennen: example → beispielschule
sed -i 's/example/beispielschule/g' docker-compose.yml

# .env aus Vorlage anlegen
cp .env.example .env
nano .env   # neue DOMAIN, eigene DB-Werte
```

Datenbank auf dem DB-Server anlegen:
```sql
CREATE DATABASE db_beispiel CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'user_beispiel'@'<APP_SERVER_PRIVATE_IP>' IDENTIFIED BY '<NEUES_PASSWORT>';
GRANT ALL PRIVILEGES ON db_beispiel.* TO 'user_beispiel'@'<APP_SERVER_PRIVATE_IP>';
FLUSH PRIVILEGES;
```

Datenverzeichnis auf der Storage-Box anlegen und auf dem Host als zusätzlichen Mount-Punkt einbinden (z. B. `/mnt/beispielschule-data`). Im docker-compose.yml die Volume-Pfade entsprechend anpassen.

Starten:
```bash
docker compose up -d
```

Traefik erkennt die neue Instanz automatisch über die Labels und holt ein eigenes SSL-Zertifikat.
