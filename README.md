# Nextcloud App-Server

Schlankes Multi-Domain-Setup für eine oder mehrere Nextcloud-Instanzen auf einem Hetzner V-Server. Externe MariaDB (auf separatem DB-Server) und externer Storage (Hetzner Storage-Box per NFS).

## Architektur

```
                    [Internet]
                        │
                Port 80/443
                        ▼
              ┌───────────────────────┐
              │  Traefik (Reverse     │
              │  Proxy + Let's        │
              │  Encrypt)             │
              └────────┬──────────────┘
                       │ docker-network: traefik-public
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
  [NC-Instanz 1]  [NC-Instanz 2]  [Traefik Dashboard]
   example        (zukünftig)
   ├── nginx
   ├── nextcloud:fpm
   ├── redis
   └── cron
        │
        │ (privates Cloud Network, 10.0.0.0/24)
        ▼
   ┌──────────┐  ┌──────────────┐
   │ DB-Server│  │ Storage-Box  │
   │ MariaDB  │  │ NFS-Export   │
   └──────────┘  └──────────────┘
```

**Sicherheit:** Nur der App-Server hat eine öffentliche IP. DB und Storage sind ausschließlich über das private Hetzner Cloud Network erreichbar.

## Repo-Struktur

```
.
├── README.md                       # diese Datei
├── db-server-setup.md              # MariaDB-Server vorbereiten
├── storage-server-setup.md         # Storage-Box (oder NFS-Server) vorbereiten
├── host-setup.md                   # App-Server-Host vorbereiten
│
├── proxy/                          # Traefik — läuft EINMAL pro Server
│   ├── docker-compose.yml
│   ├── traefik.yml
│   ├── .env.example
│   └── README.md
│
└── instances/                      # Eine NC-Instanz pro Unterordner
    └── example/                    # cloud.example.com (Vorlage)
        ├── docker-compose.yml
        ├── nginx/
        │   └── nextcloud.conf
        ├── .env.example
        └── README.md
```

## Reihenfolge für ein komplettes Setup

1. **Hetzner Cloud Network** anlegen (in der Hetzner Console) und alle drei Server hineinhängen
2. **DB-Server vorbereiten:** [db-server-setup.md](db-server-setup.md) — MariaDB installieren, Tuning, bind-address, UFW
3. **Storage-Server vorbereiten:** [storage-server-setup.md](storage-server-setup.md) — Hetzner Storage-Box oder eigener NFS-Server
4. **App-Server vorbereiten:** [host-setup.md](host-setup.md) — Docker, UFW, CrowdSec, NFS-Mount, DNS
5. **Traefik starten** (einmal pro App-Server): [proxy/README.md](proxy/README.md)
6. **Erste NC-Instanz starten:** [instances/example/README.md](instances/example/README.md)
7. **Weitere Instanzen:** `instances/example` als Vorlage kopieren — Schritt-für-Schritt in der Instanz-README

## Architektur-Prinzipien

- **Trennung der Verantwortung:** App, DB und Storage je eigener Server
- **Sicherheit:** Nur der App-Server hat eine öffentliche IP. DB und Storage sind ausschließlich über das private Cloud Network erreichbar
- **Skalierbarkeit:** Eine Storage-Box bedient viele NC-Instanzen, ein DB-Server bedient viele NC-Datenbanken
- **Multi-Domain:** Traefik routet anhand der Domain und holt automatisch SSL-Zertifikate
- **Reproduzierbarkeit:** Alles als Code im Git, sensible Werte nur in `.env`-Dateien (gitignored)
