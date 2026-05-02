#!/usr/bin/env bash
# Automatische Verifikation der Pilot-Setup-Abschluss-Checkliste.
# Führt alle SSH-/curl-basierten Tests durch und meldet PASS/FAIL/MANUAL pro Punkt.
# Browser-basierte Tests werden als MANUAL markiert.
#
# Nutzung:
#   1. cp abschluss-check.env.example abschluss-check.env
#   2. abschluss-check.env mit echten Werten füllen
#   3. ./abschluss-check.sh
#
# Voraussetzung: id_cloudrms (oder anderer Key aus SSH_KEY) auf lokalem Rechner,
# auf allen drei Servern als authorized_keys eingetragen, sowie auf dem App-Server
# zusätzlich als Private-Key in /root/.ssh/id_cloudrms vorhanden (für nested SSH).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/abschluss-check.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "FEHLER: $ENV_FILE nicht gefunden."
    echo "Erstelle sie zuerst: cp abschluss-check.env.example abschluss-check.env"
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Pflicht-Variablen prüfen
required_vars=(APP_SERVER_IPv4_PUBLIC APP_SERVER_IPv4_PRIVATE DB_SERVER_PRIVATE_IP
               FILE_SERVER_IPv4_PRIVATE NEUE_SUBDOMAIN TRAEFIK_DOMAIN INSTANCE_NAME
               DB_NAME SSH_KEY APP_REPO_PATH)
for v in "${required_vars[@]}"; do
    if [ -z "${!v:-}" ]; then
        echo "FEHLER: Variable $v nicht gesetzt in $ENV_FILE"
        exit 1
    fi
done

# Farben (deaktiviert wenn NO_COLOR gesetzt oder nicht-TTY)
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    GREEN='' RED='' YELLOW='' BLUE='' RESET=''
else
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;36m'
    RESET='\033[0m'
fi

PASS_COUNT=0
FAIL_COUNT=0
MANUAL_COUNT=0
FAILED_TESTS=()

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new
          -o BatchMode=yes -o ConnectTimeout=10)

# Test-Helfer: erwartet einen Befehl + ein Pattern, das im Output stehen muss
test_pass() {
    local title="$1"; shift
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "${GREEN}[PASS]${RESET} %s\n" "$title"
}
test_fail() {
    local title="$1" detail="${2:-}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_TESTS+=("$title")
    printf "${RED}[FAIL]${RESET} %s\n" "$title"
    [ -n "$detail" ] && printf "        ${RED}└─${RESET} %s\n" "$detail"
}
test_manual() {
    local title="$1" hint="${2:-}"
    MANUAL_COUNT=$((MANUAL_COUNT + 1))
    printf "${YELLOW}[MANUAL]${RESET} %s\n" "$title"
    [ -n "$hint" ] && printf "         ${YELLOW}└─${RESET} %s\n" "$hint"
}
section() {
    printf "\n${BLUE}── %s ──${RESET}\n" "$1"
}

# --- Helfer für SSH zu privaten Servern (über App-Server hindurch) ---
# Verschachteltes SSH: lokal → App-Server → Ziel
ssh_via_app() {
    local target="$1"; shift
    local cmd="$*"
    # Die einfachsten Anführungszeichen funktionieren wenn cmd keine Single-Quotes enthält.
    # Wir verwenden konsequent doppelte Quotes für inneren Befehl.
    ssh "${SSH_OPTS[@]}" "root@${APP_SERVER_IPv4_PUBLIC}" \
        "ssh -i ~/.ssh/id_cloudrms -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 root@${target} \"${cmd}\""
}

ssh_app() {
    ssh "${SSH_OPTS[@]}" "root@${APP_SERVER_IPv4_PUBLIC}" "$@"
}

echo
echo "═══════════════════════════════════════════════════════"
echo "  Pilot-Setup-Verifikation"
echo "  Instanz: ${INSTANCE_NAME}  ·  Domain: ${NEUE_SUBDOMAIN}"
echo "═══════════════════════════════════════════════════════"

# ════════════════════════════════════════════════
section "DB-Server (${DB_SERVER_PRIVATE_IP})"
# ════════════════════════════════════════════════

# 1. MariaDB lauscht auf privater IP
out=$(ssh_via_app "$DB_SERVER_PRIVATE_IP" "ss -tlnp | grep 3306" 2>&1 || true)
if echo "$out" | grep -qE "${DB_SERVER_PRIVATE_IP}:3306"; then
    test_pass "MariaDB lauscht nur auf privater IP (${DB_SERVER_PRIVATE_IP}:3306)"
elif echo "$out" | grep -qE "0\.0\.0\.0:3306"; then
    test_fail "MariaDB lauscht auf allen Interfaces (0.0.0.0:3306) — Hardening fehlt" "$out"
else
    test_fail "MariaDB-Listen-Status nicht erkennbar" "$out"
fi

# 2. DB + User existieren
out=$(ssh_via_app "$DB_SERVER_PRIVATE_IP" "mysql -uroot -BNe 'SHOW DATABASES; SELECT user, host FROM mysql.user WHERE user LIKE \\\"user_%\\\";'" 2>&1 || true)
if echo "$out" | grep -qE "^${DB_NAME}$"; then
    test_pass "Datenbank ${DB_NAME} existiert"
else
    test_fail "Datenbank ${DB_NAME} fehlt" "$out"
fi
if echo "$out" | grep -qE "${APP_SERVER_IPv4_PRIVATE}"; then
    test_pass "DB-User mit Host ${APP_SERVER_IPv4_PRIVATE} existiert"
else
    test_fail "DB-User mit Host ${APP_SERVER_IPv4_PRIVATE} fehlt"
fi

# 3. Tabellen vorhanden
count=$(ssh_via_app "$DB_SERVER_PRIVATE_IP" "mysql -uroot -BNe 'USE ${DB_NAME}; SHOW TABLES;' | wc -l" 2>&1 || echo "0")
count=$(echo "$count" | tail -1 | tr -d ' ')
if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 100 ]; then
    test_pass "DB-Tabellen vorhanden (${count} Stück)"
else
    test_fail "Zu wenige DB-Tabellen (${count}) — NC nicht installiert?"
fi

# 4. UFW: nur App-Server-IP erlaubt auf 3306
out=$(ssh_via_app "$DB_SERVER_PRIVATE_IP" "ufw status verbose" 2>&1 || true)
if echo "$out" | grep -qE "deny \(incoming\)" && echo "$out" | grep -qE "3306.*ALLOW.*${APP_SERVER_IPv4_PRIVATE}"; then
    test_pass "UFW: Default deny + 3306 ALLOW nur von ${APP_SERVER_IPv4_PRIVATE}"
else
    test_fail "UFW-Regeln auf DB-Server unvollständig"
fi

# ════════════════════════════════════════════════
section "File-Server (${FILE_SERVER_IPv4_PRIVATE})"
# ════════════════════════════════════════════════

# 5. NFS-Server aktiv
out=$(ssh_via_app "$FILE_SERVER_IPv4_PRIVATE" "systemctl is-active nfs-server" 2>&1 || true)
if [ "$(echo "$out" | tail -1)" = "active" ]; then
    test_pass "NFS-Server-Dienst ist aktiv"
else
    test_fail "NFS-Server inaktiv (Status: $out)"
fi

# 6. Export-Konfiguration
out=$(ssh_via_app "$FILE_SERVER_IPv4_PRIVATE" "exportfs -v" 2>&1 || true)
if echo "$out" | grep -qE "/srv/nc-data" && echo "$out" | grep -qE "10\.0\.0\.0/16" && echo "$out" | grep -qE "rw" && echo "$out" | grep -qE "no_root_squash"; then
    test_pass "NFS-Export auf 10.0.0.0/16 mit rw + no_root_squash"
else
    test_fail "NFS-Export-Konfiguration nicht wie erwartet" "$out"
fi
if echo "$out" | grep -qE "(\*|0\.0\.0\.0/0)"; then
    test_fail "NFS-Export ist weltweit offen — kritisch!"
fi

# 7. Daten-Verzeichnis Owner + Permissions
# Akzeptiert: 33:33 (Debian-www-data) ODER 82:82 (Alpine-www-data, fpm-alpine)
out=$(ssh_via_app "$FILE_SERVER_IPv4_PRIVATE" "stat -c '%a %u %g' /srv/nc-data" 2>&1 || true)
out=$(echo "$out" | tail -1)
if [ "$out" = "770 33 33" ] || [ "$out" = "770 82 82" ]; then
    test_pass "/srv/nc-data: 770, Owner $(echo "$out" | awk '{print $2":"$3}') (NC-www-data)"
else
    test_fail "/srv/nc-data hat falsche Permissions/Owner: '$out' (erwartet '770 33 33' oder '770 82 82')"
fi

# 8. UFW auf File-Server
out=$(ssh_via_app "$FILE_SERVER_IPv4_PRIVATE" "ufw status verbose" 2>&1 || true)
if echo "$out" | grep -qE "deny \(incoming\)" && echo "$out" | grep -qE "(2049|nfs).*ALLOW.*10\.0\.0\.0/16"; then
    test_pass "UFW auf File-Server: NFS nur aus 10.0.0.0/16"
else
    test_fail "UFW-Regeln auf File-Server unvollständig"
fi

# ════════════════════════════════════════════════
section "App-Server (${APP_SERVER_IPv4_PUBLIC})"
# ════════════════════════════════════════════════

# 9. Traefik läuft
out=$(ssh_app "cd ${APP_REPO_PATH}/proxy && docker compose ps --format json 2>/dev/null" 2>&1 || true)
if echo "$out" | grep -qE '"State":"running"'; then
    test_pass "Traefik-Container läuft"
else
    test_fail "Traefik-Container läuft nicht oder Compose-Status nicht lesbar"
fi

# 10. acme.json Größe + Domains drin
out=$(ssh_app "stat -c '%s' ${APP_REPO_PATH}/proxy/acme.json && grep -oE '${TRAEFIK_DOMAIN}|${NEUE_SUBDOMAIN}' ${APP_REPO_PATH}/proxy/acme.json | sort -u" 2>&1 || true)
size=$(echo "$out" | head -1)
if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 1024 ]; then
    test_pass "acme.json ist ${size} Byte groß (Cert vorhanden)"
else
    test_fail "acme.json ist leer oder nicht erreichbar"
fi
if echo "$out" | grep -qF "$NEUE_SUBDOMAIN"; then
    test_pass "Cert für ${NEUE_SUBDOMAIN} vorhanden"
else
    test_fail "Kein Cert für ${NEUE_SUBDOMAIN} in acme.json"
fi
if echo "$out" | grep -qF "$TRAEFIK_DOMAIN"; then
    test_pass "Cert für ${TRAEFIK_DOMAIN} vorhanden"
else
    test_fail "Kein Cert für ${TRAEFIK_DOMAIN} in acme.json"
fi

# 11. Pilot-Stack: 4 Container Up
out=$(ssh_app "cd ${APP_REPO_PATH}/instances/${INSTANCE_NAME} && docker compose ps --format json 2>/dev/null" 2>&1 || true)
running=$(echo "$out" | grep -oE '"State":"running"' | wc -l | tr -d ' ')
if [ "$running" -eq 4 ]; then
    test_pass "Pilot-Stack: 4 Container laufen (${INSTANCE_NAME}-app/web/redis/cron)"
else
    test_fail "Pilot-Stack: ${running}/4 Container laufen"
fi

# 12. NFS-Mount auf App-Server
out=$(ssh_app "mount | grep nextcloud-data" 2>&1 || true)
if echo "$out" | grep -qE "${FILE_SERVER_IPv4_PRIVATE}:/srv/nc-data" && echo "$out" | grep -qE "type nfs"; then
    test_pass "App-Server: NFS-Mount aktiv vom File-Server"
else
    test_fail "NFS-Mount auf App-Server fehlt oder zeigt falsche Quelle" "$out"
fi

# 13. UFW auf App-Server: nur 22, 80, 443
out=$(ssh_app "ufw status verbose" 2>&1 || true)
ports_ok=0
echo "$out" | grep -qE "22/tcp.*ALLOW" && ports_ok=$((ports_ok+1))
echo "$out" | grep -qE "80/tcp.*ALLOW"  && ports_ok=$((ports_ok+1))
echo "$out" | grep -qE "443/tcp.*ALLOW" && ports_ok=$((ports_ok+1))
if [ "$ports_ok" -eq 3 ] && echo "$out" | grep -qE "deny \(incoming\)"; then
    test_pass "App-Server-UFW: 22 + 80 + 443 ALLOW, Default deny"
else
    test_fail "App-Server-UFW: nicht alle drei Ports erlaubt (${ports_ok}/3)"
fi

# 14. CrowdSec aktiv
out=$(ssh_app "systemctl is-active crowdsec" 2>&1 || true)
if [ "$(echo "$out" | tail -1)" = "active" ]; then
    test_pass "CrowdSec ist aktiv"
else
    test_fail "CrowdSec inaktiv"
fi

# 15. Bouncer angeschlossen
out=$(ssh_app "cscli bouncers list -o human 2>&1" 2>&1 || true)
if echo "$out" | grep -qE "cs-firewall-bouncer"; then
    test_pass "CrowdSec-Bouncer angeschlossen"
else
    test_fail "Kein CrowdSec-Bouncer registriert"
fi

# ════════════════════════════════════════════════
section "End-to-End (lokal vom Setup-Rechner)"
# ════════════════════════════════════════════════

# 16. SSL + Security-Header
headers=$(curl -sI --max-time 10 "https://${NEUE_SUBDOMAIN}/" 2>&1 || true)
expected=("strict-transport-security" "x-robots-tag" "x-frame-options"
          "x-permitted-cross-domain-policies" "content-security-policy")
missing=()
for h in "${expected[@]}"; do
    if ! echo "$headers" | grep -qiE "^${h}:"; then
        missing+=("$h")
    fi
done
if [ ${#missing[@]} -eq 0 ]; then
    test_pass "Alle 5 Security-Header gesetzt"
else
    test_fail "Fehlende Header: ${missing[*]}"
fi

# 17. status.php — installed:true, maintenance:false
status=$(curl -sf --max-time 10 "https://${NEUE_SUBDOMAIN}/status.php" 2>&1 || true)
if echo "$status" | grep -qE '"installed":true' && echo "$status" | grep -qE '"maintenance":false'; then
    test_pass "Nextcloud status.php: installed=true, maintenance=false"
else
    test_fail "status.php-Antwort unerwartet" "$status"
fi

# ════════════════════════════════════════════════
section "Manuell zu prüfen"
# ════════════════════════════════════════════════

test_manual "Login als Admin im Browser" "https://${NEUE_SUBDOMAIN}/ — Login mit credentials.txt"
test_manual "Datei (~10 MB) hochladen" "Im Browser via + → Datei hochladen"
test_manual "Datei landet wirklich auf File-Server" "ssh nested-Befehl, beide Listings vergleichen"
test_manual "Datei wieder herunterladen + Größe vergleichen" "Im Browser Download-Button"
test_manual "Traefik-Dashboard erreichbar" "https://${TRAEFIK_DOMAIN}/"
test_manual "NC-Sicherheits-Check sauber" "https://${NEUE_SUBDOMAIN}/index.php/settings/admin/overview"
test_manual "Credentials in Vaultwarden gesichert" "proxy/credentials.txt + instances/${INSTANCE_NAME}/credentials.txt"

# ════════════════════════════════════════════════
echo
echo "═══════════════════════════════════════════════════════"
total=$((PASS_COUNT + FAIL_COUNT))
printf "  Auto-Checks: ${GREEN}${PASS_COUNT}/${total} grün${RESET}"
[ "$FAIL_COUNT" -gt 0 ] && printf " ${RED}(${FAIL_COUNT} fehlgeschlagen)${RESET}"
echo
printf "  Manuell zu prüfen: ${YELLOW}${MANUAL_COUNT} Punkte${RESET}\n"
echo "═══════════════════════════════════════════════════════"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo
    echo "Fehlgeschlagene Tests:"
    for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
    exit 1
fi
exit 0
