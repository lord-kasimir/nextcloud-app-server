# Nextcloud-Instanz: cloud.example.com

Eine NC-Instanz im Multi-Domain-Setup. Wird vom zentralen Traefik (siehe `../../proxy`) automatisch erkannt und mit Let's-Encrypt-Zertifikat versorgt.

## Voraussetzungen

- Traefik-Stack läuft (siehe `proxy/README.md`)
- Docker-Netz `traefik-public` existiert
- DNS-A-Record für `cloud.example.com` zeigt auf die App-Server-IP
- NFS-Mount auf `/mnt/nextcloud-data` ist eingerichtet
- DB auf DB-Server (<DB_SERVER_IP>, MariaDB) erreichbar via Cloud Network

## Setup

**Empfohlen: Setup-Script:**

```bash
chmod +x init.sh
./init.sh
```

Das Script fragt Domain + DB-Server-IP ab, generiert ein sicheres DB-Passwort und ein NC-Admin-Passwort, schreibt `.env` und `db-create.sql` (für den DB-Server) und legt eine `credentials.txt` an.

```bash
# 1. db-create.sql an den DB-Server senden, <APP_SERVER_PRIVATE_IP> ersetzen, ausführen
#    (siehe Anleitung im init.sh-Output)

# 2. NFS-Mount /mnt/nextcloud-data muss aktiv sein (siehe ../../host-setup.md)

# 3. Stack starten — NC-Admin-Account wird automatisch beim ersten Start angelegt
docker compose up -d

# 4. Logs prüfen, Traefik holt SSL-Zertifikat (kann 30–60 Sek dauern)
docker compose logs -f

# 5. Aufruf: https://<deine-domain>  → Login mit Admin-Credentials aus credentials.txt
```

**Manuell:** `cp .env.example .env`, alle Werte selbst eintragen, dann oben weiter ab Schritt 1.

## Nextcloud-CLI (occ)

```bash
docker compose exec --user www-data nextcloud php occ status
docker compose exec --user www-data nextcloud php occ files:scan --all
docker compose exec --user www-data nextcloud php occ db:add-missing-indices
```

## Hardening nach dem ersten Start

Nach erfolgreichem ersten Login die folgenden Befehle ausführen — verbessern Sicherheit und Performance:

```bash
# Alias zur Vereinfachung (für die Shell-Session)
alias nocc='docker compose exec --user www-data nextcloud php occ'

# Brute-Force-Schutz aktivieren
nocc config:system:set auth.bruteforce.protection.enabled --type=bool --value=true

# Hintergrund-Cron statt AJAX (haben wir per Cron-Container, hier nur das Setting)
nocc background:cron

# Memcache: APCu lokal, Redis distributed/locking (deutlich schneller)
nocc config:system:set memcache.local --value='\OC\Memcache\APCu'
nocc config:system:set memcache.distributed --value='\OC\Memcache\Redis'
nocc config:system:set memcache.locking --value='\OC\Memcache\Redis'

# Log-Rotation einstellen (100 MB pro Datei)
nocc config:system:set log_rotate_size --value='104857600'

# Privacy / UX
nocc config:system:set simpleSignUpLink.shown --type=bool --value=false
nocc app:disable survey_client
nocc app:disable firstrunwizard

# Optionale Konsistenzprüfung (kann Stunden dauern bei großem Datadir)
nocc maintenance:repair --include-expensive
```

### config.php-Eintrag für Redis (sollte automatisch korrekt sein durch REDIS_HOST-env, hier zur Kontrolle)

```php
'redis' => [
    'host' => 'redis',
    'port' => 6379,
],
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
