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
├── proxy/                    # Traefik — läuft EINMAL pro Server
│   ├── docker-compose.yml
│   ├── traefik.yml
│   ├── .env.example
│   └── README.md
│
└── instances/                # Eine NC-Instanz pro Unterordner
    └── example/             # cloud.example.com
        ├── docker-compose.yml
        ├── nginx/
        │   └── nextcloud.conf
        ├── .env.example
        └── README.md
```

## Reihenfolge

1. **Host vorbereiten:** Schritt-für-Schritt-Anleitung in [host-setup.md](host-setup.md) — Docker, UFW, CrowdSec, NFS-Mount, DNS
2. **Traefik starten** (einmalig): siehe `proxy/README.md`
3. **NC-Instanz starten:** siehe `instances/example/README.md`
4. **Weitere Instanzen:** `instances/example` als Vorlage kopieren, Domain + DB-Daten anpassen, starten

## Externe Abhängigkeiten

| Was | Wo | Wie erreichbar |
|---|---|---|
| MariaDB | DB-Server `<DB_SERVER_IP>` | Privates Cloud Network — `bind-address` auf private IP setzen |
| Datenverzeichnis | Hetzner Storage-Box | NFS-Mount auf dem Host unter `/mnt/nextcloud-data` |

## Stand

- Beispiel-Instanz: `cloud.example.com`
- Geplant: Multi-Domain-Setup: weitere Instanzen lassen sich einfach als Ordner-Kopie hinzufügen
