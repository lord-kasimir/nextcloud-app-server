# Storage-Server-Setup

Zwei Wege — Empfehlung **Hetzner Storage-Box**. Eigener V-Server mit NFS als Alternative für Sonderfälle.

## Variante A: Hetzner Storage-Box (empfohlen)

Wartungsfrei, Snapshots inklusive, günstig pro TB, hochverfügbar. Für die typische Nextcloud-Nutzung (Dokumente, gelegentliche Foto-Uploads) absolut ausreichend.

### A.1 — Storage-Box bestellen

In der Hetzner Console:
- **Storage Box** auswählen, gewünschte Größe (BX11 100 GB / BX21 1 TB / BX31 5 TB / …)
- Region: idealerweise **gleiche Region** wie der App-Server (für niedrige Latenz)

### A.2 — Subaccount mit SSH-Key anlegen

Subaccounts sind nötig, weil der Haupt-Login der Storage-Box keine NFS-Konfiguration erlaubt:

1. In der Storage-Box-Übersicht → **"Subaccounts"** → **"Subaccount erzeugen"**
2. Name vergeben (z. B. `nc-storage`)
3. Verzeichnis (Home) festlegen — z. B. `/home/nc-storage` (Subaccount sieht nur sein eigenes Verzeichnis)
4. Protokoll-Auswahl:
   - **NFS**: anhaken (das ist der Schlüssel)
   - SSH: anhaken (für Verwaltung der Permissions per Kommandozeile)
   - Optional: SMB
5. SSH-Key hinzufügen — den **Public-Key des App-Servers** (`/root/.ssh/id_ed25519.pub` oder einen dedizierten Key) eintragen

### A.3 — NFS-Export-Berechtigung setzen

Hetzner verwaltet Zugriffe in der Console:
- Subaccount → **"NFS"-Tab**
- IP des App-Servers eintragen (am besten die **private Cloud-Network-IP**, falls Storage-Box im Cloud-Network liegt; sonst die öffentliche)
- Subnet-Maske `/32` für eine einzelne IP

### A.4 — Verzeichnis und Permissions vorbereiten

Die Storage-Box arbeitet intern mit Linux-Permissions. UID/GID 33 muss dem `www-data`-User auf dem App-Server entsprechen.

```bash
# Vom Mac/Workstation per SSH zur Storage-Box:
ssh -p 23 nc-storage@<storage-box-host>.your-storagebox.de

# In der Box-Shell:
mkdir nextcloud
chown 33:33 nextcloud
chmod 750 nextcloud
ls -la
exit
```

(Hetzner Storage-Box: SSH läuft auf Port 23, nicht 22)

### A.5 — Auf dem App-Server mounten

Auf dem App-Server, in `/etc/fstab`:

```
<storage-box-host>.your-storagebox.de:/home/nc-storage/nextcloud /mnt/nextcloud-data nfs defaults,rw,_netdev,bg,hard,intr 0 0
```

Dann:
```bash
mkdir -p /mnt/nextcloud-data
mount -a
ls -la /mnt/nextcloud-data
```

### A.6 — Mehrere NC-Instanzen auf einer Storage-Box

Eine Storage-Box reicht für viele NC-Instanzen — pro Instanz ein eigenes Unterverzeichnis:

```bash
# Auf der Storage-Box per SSH:
mkdir nextcloud/cloudrms nextcloud/beispielschule
chown 33:33 nextcloud/*
chmod 750 nextcloud/*
```

Auf dem App-Server entsprechend pro Instanz einen eigenen Mount-Punkt einrichten oder einen gemeinsamen Mount mit Unterverzeichnissen verwenden.

---

## Variante B: Eigener V-Server mit NFS (Alternative)

Sinnvoll wenn:
- Höhere IO-Last erwartet wird (Video-Streaming, viele parallele Uploads)
- Spezielle Permissions-Anforderungen (ACLs, etc.)
- Zusätzliche Dienste auf dem Storage-Server laufen sollen
- Mehr Kontrolle gewünscht ist

### B.1 — Server vorbereiten

```bash
apt-get update -qq
apt-get -y dist-upgrade
apt-get install -y nfs-kernel-server nano htop mc less ufw
```

### B.2 — NFS-Verzeichnis anlegen

```bash
mkdir -p /srv/nextcloud
chown 33:33 /srv/nextcloud
chmod 750 /srv/nextcloud
```

### B.3 — Export konfigurieren

```bash
echo "/srv/nextcloud <APP_SERVER_PRIVATE_IP>(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -ra
systemctl enable --now nfs-kernel-server
exportfs -v
```

**Optionen-Erklärung:**
- `rw` — Lesen + Schreiben
- `sync` — Schreibvorgänge synchron auf Disk (sicherer, etwas langsamer)
- `no_subtree_check` — Performance-Verbesserung, Standard
- `no_root_squash` — root auf der App-Server-Seite kann auch root-Operationen ausführen (wichtig für `chown` etc. — bei Bedarf einschränken)

### B.4 — UFW

```bash
ufw default allow outgoing
ufw default deny incoming
ufw allow 22/tcp
ufw allow from <APP_SERVER_PRIVATE_IP> to any port 2049 proto tcp
ufw --force enable
```

### B.5 — Auf dem App-Server mounten

```
<NFS_SERVER_PRIVATE_IP>:/srv/nextcloud /mnt/nextcloud-data nfs defaults,rw,_netdev,bg,hard,intr 0 0
```

```bash
mkdir -p /mnt/nextcloud-data
mount -a
ls -la /mnt/nextcloud-data
```

### B.6 — Pro NC-Instanz eigenes Unterverzeichnis

```bash
# Auf dem NFS-Server:
mkdir /srv/nextcloud/cloudrms /srv/nextcloud/beispielschule
chown 33:33 /srv/nextcloud/*
chmod 750 /srv/nextcloud/*
```

---

## Hinweis zu UID/GID 33

Nextcloud im Container läuft als `www-data` mit UID/GID 33. Der NFS-Server (egal ob Storage-Box oder eigener Server) muss die Verzeichnisse mit dieser UID/GID anlegen, sonst gibt es Permission-Fehler.
