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

Das Script fragt Domain + E-Mail-Adresse ab, generiert ein sicheres Dashboard-Passwort, erzeugt den bcrypt-Hash, schreibt `.env` + `acme.json` + `logs/`-Verzeichnis und legt eine `credentials.txt` mit dem Klartext-Passwort an.

**Voraussetzung:** Docker-Netz `traefik-public` existiert (wird in `host-setup.md` Schritt 7 angelegt).

Anschließend Traefik starten:

```bash
docker compose up -d
tail -f logs/traefik.log
```

**Manuell (falls Setup ohne init.sh bevorzugt):**

```bash
cp .env.example .env
docker run --rm httpd:alpine htpasswd -nbB admin "EinSicheresPasswort"
# Ergebnis in .env unter DASHBOARD_AUTH eintragen — jedes $ verdoppeln ($$ statt $)
touch acme.json && chmod 600 acme.json
mkdir -p logs
docker compose up -d
```

## Eine NC-Instanz hinzufügen

→ siehe `instances/example/` als Vorlage. Die Instanz muss am Netzwerk `traefik-public` hängen und passende Labels haben (`traefik.enable=true`, `traefik.http.routers.<NAME>.rule=Host(\`...\`)` usw.).

## Wartung

```bash
docker compose pull && docker compose up -d   # Update
tail -f logs/traefik.log                      # Live-Logs (Traefik schreibt in File, nicht stdout)
tail -f logs/access.log                       # HTTP-Zugriffe
```

`docker compose logs traefik` zeigt nur das Allernötigste (Container-Start), die eigentlichen Traefik-Events landen wegen der `filePath`-Konfiguration in `traefik.yml` direkt im File-Log.
