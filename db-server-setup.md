# DB-Server-Setup (MariaDB)

Ein dedizierter Linux-Server (V-Server bei Hetzner empfohlen, im selben Hetzner Cloud Network wie der App-Server). Kann ein neuer Server sein oder ein bestehender Linux-Server, auf dem zusätzlich MariaDB installiert wird.

Alle Befehle laufen als Root oder mit `sudo`.

## 1. System-Updates und Basis-Pakete

```bash
apt-get update -qq
apt-get -y dist-upgrade
apt-get install -y nano htop mc less ufw
```

## 2. MariaDB installieren

```bash
apt-get install -y mariadb-server mariadb-client
systemctl enable --now mariadb
mariadb --version
```

## 3. MariaDB-Tuning für Nextcloud

```bash
cat > /etc/mysql/mariadb.conf.d/99-nextcloud.cnf << 'CNF'
[mysqld]
innodb_file_per_table = 1
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
transaction_isolation = READ-COMMITTED
max_allowed_packet = 512M
character_set_server = utf8mb4
collation_server = utf8mb4_general_ci
CNF
```

**Erklärung der Parameter:**
- `innodb_file_per_table = 1` — jede Tabelle eigene Datei (sauberere Backups)
- `innodb_buffer_pool_size = 1G` — RAM für Datencache. Bei mehr verfügbarem RAM erhöhen (Faustregel: ~25–50 % des RAMs, wenn der Server nur DB ist; weniger, wenn weitere Dienste laufen)
- `innodb_log_file_size = 256M` — Redo-Log-Größe; größer = weniger I/O-Spitzen bei großen Schreibvorgängen
- `transaction_isolation = READ-COMMITTED` — Nextcloud-Empfehlung: verhindert Deadlocks bei vielen parallelen Transaktionen
- `max_allowed_packet = 512M` — wichtig für große Uploads und große BLOB-Operationen
- `character_set_server = utf8mb4` + Collation — Pflicht für Nextcloud (Emoji-Support, Unicode komplett)

## 4. Bind-Address auf private IP setzen

**Wichtig:** MariaDB darf NIEMALS auf der öffentlichen IP lauschen. Nur auf der privaten Cloud-Network-IP.

```bash
# Private IP herausfinden (Cloud-Network-Interface)
ip -4 addr show | grep "10\."

# In sed-Befehl unten <PRIVATE_IP> durch die gefundene private IP ersetzen
sed -i 's/^bind-address.*/bind-address = <PRIVATE_IP>/' /etc/mysql/mariadb.conf.d/50-server.cnf

# Tuning + bind-address aktivieren
systemctl restart mariadb

# Verifizieren
ss -tlnp | grep 3306
# → muss <PRIVATE_IP>:3306 anzeigen, nicht 0.0.0.0:3306 oder die öffentliche IP
```

## 5. UFW-Firewall

```bash
ufw default allow outgoing
ufw default deny incoming

# SSH (Port anpassen falls eigener Port verwendet wird)
ufw allow 22/tcp

# MariaDB nur vom App-Server (private IP)
ufw allow from <APP_SERVER_PRIVATE_IP> to any port 3306 proto tcp

ufw --force enable
ufw status verbose
```

## 6. Datenbank und Benutzer pro Nextcloud-Instanz

Pro NC-Instanz wird eine eigene DB und ein eigener User angelegt. Wiederholen für jede neue Instanz.

```bash
mysql -uroot << 'SQL'
CREATE DATABASE db_example CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'user_example'@'<APP_SERVER_PRIVATE_IP>' IDENTIFIED BY '<NEUES_PASSWORT>';
GRANT ALL PRIVILEGES ON db_example.* TO 'user_example'@'<APP_SERVER_PRIVATE_IP>';
FLUSH PRIVILEGES;
SQL
```

Passwort generieren:
```bash
openssl rand -base64 24
```

## 7. CrowdSec (optional, empfohlen)

Brute-Force-Schutz für SSH und MariaDB:

```bash
curl -s https://install.crowdsec.net | bash
apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables
systemctl status crowdsec --no-pager
cscli metrics
```

## Verifikation vom App-Server aus

```bash
# Auf dem APP-Server testen, ob die Verbindung klappt
mariadb -h <DB_SERVER_PRIVATE_IP> -u user_example -p db_example
# → Sollte den MariaDB-Prompt anzeigen
```

## Backups

Tägliches DB-Backup empfohlen. Einfaches Skript `/usr/local/bin/nc-db-backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR=/var/backups/mariadb
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

# Pro DB ein eigener Dump
for DB in $(mysql -uroot -BNe "SHOW DATABASES" | grep -vE "^(information_schema|performance_schema|mysql|sys)$"); do
    mysqldump --single-transaction --quick --default-character-set=utf8mb4 \
        --routines --triggers --events "$DB" | gzip > "$DB-$(date +%Y%m%d).sql.gz"
done

# Alte Backups löschen (älter als 14 Tage)
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +14 -delete
```

Per Cron einmal täglich ausführen:

```bash
chmod +x /usr/local/bin/nc-db-backup.sh
echo "0 3 * * * root /usr/local/bin/nc-db-backup.sh" > /etc/cron.d/nc-db-backup
```

## Auf einem bestehenden Linux-Server (z. B. ohne dass er ausschließlich DB-Server ist)

Falls MariaDB auf einem bestehenden Server (z. B. Jitsi-Server oder ähnlich) zusätzlich installiert wird:
- Schritte 2, 3, 4, 6 unverändert
- Schritt 5 (UFW): nur die `ufw allow from <APP_SERVER_PRIVATE_IP> to any port 3306` ergänzen, bestehende Regeln nicht überschreiben
- Schritt 7 (CrowdSec): falls fail2ban schon läuft, dabei bleiben statt parallel beides
- Wichtig: `innodb_buffer_pool_size` an verfügbares RAM-Budget anpassen, ohne andere Dienste auszuhungern
