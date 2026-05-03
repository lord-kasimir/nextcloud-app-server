# Nextcloud App-Server

Schlankes Multi-Domain-Setup für eine oder mehrere Nextcloud-Instanzen auf einem Hetzner V-Server. Externe MariaDB auf eigenem DB-Server und externer NFS-Storage auf eigenem File-Server, beide ausschließlich übers private Hetzner Cloud Network erreichbar.

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
   │ DB-Server│  │ File-Server  │
   │ MariaDB  │  │ NFS-Export   │
   └──────────┘  └──────────────┘
```

**Sicherheit:** Nur der App-Server hat eine öffentliche IP. DB und Storage sind ausschließlich über das private Hetzner Cloud Network erreichbar.

## Repo-Struktur

```
.
├── README.md                       # diese Datei
├── db-server-setup.md              # MariaDB-Server vorbereiten
├── storage-server-setup.md         # NFS-File-Server vorbereiten
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
3. **File-Server vorbereiten:** [storage-server-setup.md](storage-server-setup.md) — eigener NFS-Server im Cloud-Network
4. **App-Server vorbereiten:** [host-setup.md](host-setup.md) — Docker, UFW, CrowdSec, NFS-Mount, DNS
5. **Traefik starten** (einmal pro App-Server): [proxy/README.md](proxy/README.md)
6. **Erste NC-Instanz starten:** [instances/example/README.md](instances/example/README.md)
7. **Weitere Instanzen:** `instances/example` als Vorlage kopieren — Schritt-für-Schritt in der Instanz-README

## Optional: AI-Stack (Nextcloud Assistant + RAG)

Für den vollen Nextcloud-AI-Stack mit Chat (Assistant) und RAG (Frage-zu-Dokumenten) vier Apps in dieser Reihenfolge installieren:

| # | App | Typ | Funktion |
|---|---|---|---|
| 1 | `integration_openai` | regular PHP-App (`occ app:install`) | Brücke NC↔OpenAI-kompatible API (Ollama, lokales LLM, OpenAI etc.) |
| 2 | `assistant` | regular PHP-App | UI für Chat / Free-Prompt / Übersetzen |
| 3 | `context_chat` | regular PHP-App | PHP-Frontend für RAG |
| 4 | `context_chat_backend` | ExApp (`occ app_api:app:register`) | Container-Backend für Embedding + Vektor-Index |

**Voraussetzungen:**
- DSP-Daemon installiert + registriert (siehe `proxy/README.md` → AppAPI-Sektion)
- Embedding+LLM-Endpoint erreichbar (z.B. Ollama auf separatem GPU-Server)
- 4 TaskProcessing-Worker pro Instanz (`aiworker1-4` in der Instance-`docker-compose.yml`, siehe `instances/example/`)

**Bekannter Bug `integration_openai` 4.x unter NC 33+:** Alle App-Configs müssen als `string` gesetzt werden, auch `*_enabled` und `request_timeout` (sonst 500 auf `/settings/admin/ai`). Beispiel:

```bash
for k in chat_endpoint_enabled llm_provider_enabled translation_provider_enabled; do
  docker exec -u www-data nc-<INST>-app php occ config:app:set integration_openai $k --value="1" --type=string
done
```

**ExApp-Deploy-Beispiel `context_chat_backend` mit externem Ollama-Embedding:**

```bash
docker exec -u www-data nc-<INST>-app php occ app_api:app:register context_chat_backend dsp_local \
  --env CC_EM_BASE_URL=http://<OLLAMA-HOST>:11434/v1 \
  --env CC_EM_APIKEY=ollama \
  --env CC_EM_MODEL_NAME=bge-m3 \
  --env CC_EM_BATCH_SIZE=32 \
  --env CC_DOWNLOAD_MODELS_FROM_HF=false \
  --wait-finish -v
```

Empfohlene Chunk-Size für deutsche Tabellen-Dokumente: `embedding_chunk_size: 600` in `persistent_storage/config.yaml` (Default 2000 zerschneidet Tabellen).

## Architektur-Prinzipien

- **Trennung der Verantwortung:** App, DB und Storage je eigener Server
- **Sicherheit:** Nur der App-Server hat eine öffentliche IP. DB und Storage sind ausschließlich über das private Cloud Network erreichbar
- **Skalierbarkeit:** Ein File-Server (mit nachträglich erweiterbarem Cloud-Volume) bedient viele NC-Instanzen, ein DB-Server bedient viele NC-Datenbanken
- **Multi-Domain:** Traefik routet anhand der Domain und holt automatisch SSL-Zertifikate
- **Reproduzierbarkeit:** Alles als Code im Git, sensible Werte nur in `.env`-Dateien (gitignored)
