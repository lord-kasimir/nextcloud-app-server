# Host-Vorbereitung (Ubuntu V-Server)

Was vor dem ersten `docker compose up` auf einem frischen Ubuntu-Server gemacht werden muss. Getestet auf Ubuntu 24.04 LTS, läuft auch auf 22.04.

Alle Befehle laufen als Root oder mit `sudo`.

## 1. System-Updates

```bash
apt-get update -qq
apt-get -y dist-upgrade
apt-get -y autoremove
```

## 2. Basis-Pakete

```bash
apt-get install -y curl ca-certificates gnupg lsb-release nfs-common htop nano less mc
```

## 3. Docker + Compose installieren

```bash
# Offizielle Docker-Repo einbinden
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verifizieren
docker --version
docker compose version
```

## 4. UFW (Firewall)

```bash
apt-get install -y ufw

# Standard-Policy: alles ausgehend erlaubt, eingehend gesperrt
ufw default allow outgoing
ufw default deny incoming

# SSH freischalten — WICHTIG: Port an deine Konfiguration anpassen!
ufw allow 22/tcp           # oder dein eigener SSH-Port

# Web (Traefik)
ufw allow 80/tcp
ufw allow 443/tcp

# Aktivieren
ufw --force enable
ufw status verbose
```

**Achtung:** Wenn Docker direkt auf eine Port-Bindung zugreift, umgeht es UFW. Für Container, die nur intern erreichbar sein sollen, NIEMALS `ports:` im docker-compose verwenden — nur `expose:` oder Netz-Aliase.

## 5. CrowdSec (Brute-Force-Schutz)

CrowdSec ersetzt fail2ban — moderner, communitybasiert, integriert sich gut mit Traefik.

```bash
# Repo einbinden
curl -s https://install.crowdsec.net | bash

# Installieren
apt-get install -y crowdsec

# Bouncer für UFW (blockt erkannte Angreifer)
apt-get install -y crowdsec-firewall-bouncer-iptables

# Status
systemctl status crowdsec --no-pager
cscli metrics
```

Empfohlene Collections + Scenarios für Nextcloud + Traefik installieren:
```bash
cscli collections install crowdsecurity/traefik
cscli collections install crowdsecurity/nginx
cscli collections install crowdsecurity/nextcloud
cscli scenarios install crowdsecurity/nextcloud-bf
systemctl restart crowdsec
cscli collections list
```

## 6. NFS-Mount der Storage-Box

```bash
# Mount-Punkt anlegen
mkdir -p /mnt/nextcloud-data

# Eintrag in /etc/fstab
echo "<NFS_SERVER_IP>:/<EXPORT_PFAD> /mnt/nextcloud-data nfs defaults,rw,_netdev,bg,hard,intr 0 0" >> /etc/fstab

# Mounten
mount -a

# Prüfen
mount | grep nextcloud-data
ls -la /mnt/nextcloud-data
```

`<NFS_SERVER_IP>` ist die private IP des Storage-Servers (Hetzner Cloud Network). `<EXPORT_PFAD>` der freigegebene Ordner auf dem NFS-Server (z. B. `/nextcloud/instance-name`).

**Wichtig:** Nextcloud läuft im Container als `www-data` mit UID/GID 33. Das Verzeichnis auf der NFS-Seite muss `chown 33:33` und `chmod 750` haben, sonst gibt es Permission-Errors.

## 7. Docker-Netzwerk für Traefik

```bash
docker network create traefik-public
```

Dieses Netz wird vom Traefik-Stack und von allen NC-Instanzen verwendet.

## 8. DNS-Records setzen

Bei deinem DNS-Anbieter A-Records anlegen, die auf die öffentliche IP des App-Servers zeigen:

- `cloud.example.com` → `<APP_SERVER_PUBLIC_IP>`
- `traefik.example.com` → `<APP_SERVER_PUBLIC_IP>` (für das Traefik-Dashboard)

Pro neue NC-Instanz: ein weiterer A-Record.

## 9. Repo klonen

```bash
cd /opt
git clone https://github.com/lord-kasimir/nextcloud-app-server.git
cd nextcloud-app-server
```

Danach: `proxy/README.md` für den Reverse-Proxy folgen, dann `instances/example/README.md` für die erste Instanz.

## 10. Kernel-/TCP-Stack-Hardening

Zusätzliche Sicherheitsmaßnahmen auf Kernel-Ebene, sinnvoll für öffentlich erreichbare Server.

```bash
cat > /etc/sysctl.d/100-nextcloud.conf << 'CNF'
# SYN-Flood-Schutz
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096

# IP-Spoofing-Schutz
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP-Redirects ignorieren
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Source-Routing deaktivieren
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Connection-Tracking-Limit erhöhen
net.core.somaxconn = 1024

# Bogus ICMP ignorieren
net.ipv4.icmp_ignore_bogus_error_responses = 1
CNF

sysctl --system
```

## Sicherheits-Hinweis

Auf einem öffentlich erreichbaren Server zusätzlich empfohlen:

- SSH-Port von 22 weg verschieben (in `/etc/ssh/sshd_config`)
- `PermitRootLogin no` setzen, eigenen User mit `sudo` anlegen
- SSH nur per Public-Key, kein Passwort-Login
- `unattended-upgrades` für automatische Sicherheits-Patches
