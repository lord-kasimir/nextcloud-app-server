# Traefik Reverse Proxy

Zentraler Eingangspunkt für alle Nextcloud-Instanzen auf diesem App-Server. Läuft genau **einmal** pro Server.

## Was Traefik macht

- Hört auf Port 80 (HTTP) und 443 (HTTPS) öffentlich
- Erkennt Container im Docker-Netz `traefik-public` automatisch über Labels
- Routet eingehende Anfragen anhand der Domain zum richtigen Container
- Holt + erneuert automatisch Let's-Encrypt-Zertifikate für jede neue Domain
- Bietet ein Dashboard zur Beobachtung (https://traefik.deine-domain)

## Setup (einmalig)

**Empfohlen: Setup-Script:**

```bash
chmod +x init.sh
./init.sh
```

Das Script fragt Domain + E-Mail-Adresse ab, generiert ein sicheres Dashboard-Passwort, erzeugt den bcrypt-Hash, schreibt `.env` + `acme.json` + `logs/`-Verzeichnis und legt eine `credentials.txt` mit dem Klartext-Passwort an. Anschließend:

```bash
docker network create traefik-public  # einmalig pro Server
docker compose up -d
docker compose logs -f
```

**Manuell (falls bevorzugt):**

```bash
cp .env.example .env
docker run --rm httpd:alpine htpasswd -nbB admin "EinSicheresPasswort"
# Ergebnis in .env unter DASHBOARD_AUTH eintragen — jedes $ verdoppeln ($$ statt $)
docker network create traefik-public
touch acme.json && chmod 600 acme.json
mkdir -p logs
docker compose up -d
```

## Eine NC-Instanz hinzufügen

→ siehe `instances/example/` als Vorlage. Die Instanz muss am Netzwerk `traefik-public` hängen und passende Labels haben (`traefik.enable=true`, `traefik.http.routers.<NAME>.rule=Host(\`...\`)` usw.).

## Wartung

```bash
docker compose pull && docker compose up -d   # Update
docker compose logs -f traefik                # Live-Logs
tail -f logs/traefik.log                      # File-Log
```
