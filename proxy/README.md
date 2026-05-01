# Traefik Reverse Proxy

Zentraler Eingangspunkt für alle Nextcloud-Instanzen auf diesem App-Server. Läuft genau **einmal** pro Server.

## Was Traefik macht

- Hört auf Port 80 (HTTP) und 443 (HTTPS) öffentlich
- Erkennt Container im Docker-Netz `traefik-public` automatisch über Labels
- Routet eingehende Anfragen anhand der Domain zum richtigen Container
- Holt + erneuert automatisch Let's-Encrypt-Zertifikate für jede neue Domain
- Bietet ein Dashboard zur Beobachtung (https://traefik.deine-domain)

## Setup (einmalig)

```bash
# 1. .env aus Vorlage erstellen
cp .env.example .env

# 2. Basic-Auth-Hash für das Dashboard erzeugen
docker run --rm httpd:alpine htpasswd -nbB admin "EinSicheresPasswort"
# Ergebnis in .env unter DASHBOARD_AUTH eintragen
# WICHTIG: jedes $ verdoppeln (aus $2y$05$… wird $$2y$$05$$…)

# 3. Traefik-Public-Netz anlegen (einmalig)
docker network create traefik-public

# 4. Acme-Datei vorbereiten (Let's-Encrypt-Zertifikate)
touch acme.json && chmod 600 acme.json

# 5. Logs-Verzeichnis
mkdir -p logs

# 6. Starten
docker compose up -d

# 7. Logs prüfen
docker compose logs -f
```

## Eine NC-Instanz hinzufügen

→ siehe `instances/example/` als Vorlage. Die Instanz muss am Netzwerk `traefik-public` hängen und passende Labels haben (`traefik.enable=true`, `traefik.http.routers.<NAME>.rule=Host(\`...\`)` usw.).

## Wartung

```bash
docker compose pull && docker compose up -d   # Update
docker compose logs -f traefik                # Live-Logs
tail -f logs/traefik.log                      # File-Log
```
