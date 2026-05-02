# File-Server-Setup (NFS)

Eigener kleiner V-Server im Hetzner Cloud Network, exportiert per NFS einen Daten-Ordner. Der App-Server mountet diesen Ordner als `/mnt/nextcloud-data` und Nextcloud schreibt seine User-Dateien dort hinein.

**Warum eigener Server, nicht Hetzner Storage-Box?** Die Hetzner Storage-Box unterstützt NFS schlicht nicht — nur SMB/CIFS, FTP/SFTP, WebDAV, SCP. Für Nextcloud-Daten ist NFS auf einem eigenen V-Server klar im Vorteil: SSD statt HDD, Mount-Optionen frei wählbar, IP-Whitelist möglich, später per Cloud-Volume erweiterbar.

Alle Befehle laufen als Root oder mit `sudo`.

## 1. Server bestellen

In der Hetzner Cloud Console:
- **CX22** reicht für den Pilot (2 vCPU, 4 GB RAM, 40 GB NVMe lokal). Für produktive Nutzung mit mehreren Instanzen: CX32 oder dediziertes CCX23.
- **Region:** dieselbe wie der App-Server (für niedrige Latenz)
- **Networking:** beim Bestellen das Cloud-Network mit anhaken — Server bekommt automatisch eine private IP wie `10.0.0.x`
- **SSH-Key:** Public-Key des Admin-Rechners hinterlegen (kein Passwort-Login)

Cloud-Volume kann später jederzeit hinzugefügt werden, wenn der Bord-NVMe knapp wird.

## 2. System-Updates und Basis-Pakete

```bash
apt-get update -qq
apt-get -y dist-upgrade
apt-get install -y nfs-kernel-server ufw nano htop mc less
```

## 3. NFS-Verzeichnis anlegen

Nextcloud läuft im Container als `www-data` mit UID/GID 33 — der Daten-Ordner muss exakt diesem User/Group gehören.

```bash
mkdir -p /srv/nc-data
chown 33:33 /srv/nc-data
chmod 770 /srv/nc-data
```

## 4. Export konfigurieren

Export nur ans Cloud-Network freigeben (10.0.0.0/16) — nicht ans öffentliche Internet. `no_root_squash` ist nötig, weil der App-Server-Container intern als root in den Mount schreiben darf, ohne die UID/GID-Mapping zu zerstören.

```bash
echo "/srv/nc-data 10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)" > /etc/exports
exportfs -ra
systemctl enable --now nfs-server
exportfs -v
```

**Optionen-Erklärung:**
- `rw` — Lesen + Schreiben
- `sync` — Schreibvorgänge synchron auf Disk (sicherer, etwas langsamer)
- `no_subtree_check` — Performance, Standard
- `no_root_squash` — root auf der App-Server-Seite kann auch root-Operationen ausführen (wichtig für `chown` etc.)

## 5. UFW-Firewall

```bash
ufw default allow outgoing
ufw default deny incoming
ufw allow 22/tcp
ufw allow from 10.0.0.0/16 to any port nfs
ufw --force enable
ufw status verbose
```

NFS belegt mehrere Ports (2049 + rpcbind 111 + statd dynamisch). `ufw allow from <subnet> to any port nfs` öffnet das gesamte NFS-Service-Bündel sauber.

## 6. Pro NC-Instanz eigenes Unterverzeichnis (optional)

Bei mehreren NC-Instanzen pro Instanz ein eigenes Unterverzeichnis anlegen:

```bash
mkdir /srv/nc-data/pilot /srv/nc-data/instanz2
chown 33:33 /srv/nc-data/*
chmod 770 /srv/nc-data/*
```

Auf dem App-Server pro Instanz einen eigenen Mount-Punkt einhängen, oder einen gemeinsamen Mount mit Unterverzeichnissen verwenden.

## 7. Backup-Strategie

Eigener File-Server = eigene Backup-Verantwortung. Optionen:

- **Hetzner Storage-Box als Backup-Ziel** (NICHT als Live-Storage): Storage-Box per SMB/CIFS mounten oder per `rsync` über SSH/Port 23 ansprechen, täglich Snapshot ziehen. Kosten ab ~4,50 €/Monat für 1 TB.
- **Cloud-Volume Snapshots:** wenn ein Cloud-Volume angehängt ist, in der Hetzner-Console Snapshots aktivieren
- **borgbackup** mit Deduplizierung auf eine Storage-Box oder externes Ziel
- **rsnapshot** für inkrementelle Datei-Backups auf separates Volume

In jedem Fall: **Datenbank-Backup separat vom DB-Server** (siehe `db-server-setup.md`), beide zusammen ergeben ein konsistentes NC-Backup.

## 8. Verifikation vom App-Server aus

```bash
# Auf dem APP-Server testen:
showmount -e <FILE_SERVER_PRIVATE_IP>
# → Muss /srv/nc-data 10.0.0.0/16 zeigen

mount -t nfs <FILE_SERVER_PRIVATE_IP>:/srv/nc-data /mnt/nextcloud-data
ls -la /mnt/nextcloud-data
# → Owner muss 33:33 sein, leer
```

## Hinweis zu UID/GID 33

Nextcloud im Container läuft als `www-data` mit UID/GID 33. Auf dem File-Server muss der Daten-Ordner mit `chown 33:33` angelegt werden. Auch wenn der File-Server selbst keinen `www-data`-User mit dieser ID hat: NFS überträgt die numerischen IDs, nicht die Namen. Hauptsache 33:33 — der Container kommt damit klar.
