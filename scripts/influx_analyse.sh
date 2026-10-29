#!/usr/bin/env bash
#
# influx_analyse.sh - Sammelt alle InfluxDB-Diagnoseinfos fuer die
#                     Energie-Daten-Aggregation (raw_7d / agg_6m_15min / agg_inf_1d)
#
# Aufruf:
#   ./influx_analyse.sh [user@]host [weitere ssh-optionen...]
#
# Beispiele:
#   ./influx_analyse.sh 192.168.178.100
#   ./influx_analyse.sh pi@192.168.178.100
#   ./influx_analyse.sh -i ~/.ssh/id_rsa root@192.168.178.100
#
# Optional (werden an die Remote-Seite durchgereicht):
#   INFLUX_USER / INFLUX_PASS   falls InfluxDB Auth aktiviert hat
#   INFLUX_HTTP_PORT            Standard 8086
#
# Empfehlung: ./influx_analyse.sh 192.168.178.100 > report.txt 2>&1

set -uo pipefail

REMOTE="${1:-192.168.178.100}"
shift || true
SSH_OPTS=("$@")

INFLUX_USER="${INFLUX_USER:-}"
INFLUX_PASS="${INFLUX_PASS:-}"
INFLUX_HTTP_PORT="${INFLUX_HTTP_PORT:-8086}"

if [ -n "$INFLUX_USER" ]; then
  AUTH="-username '$INFLUX_USER' -password '$INFLUX_PASS'"
else
  AUTH=""
fi

ssh_cmd() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 \
      -o StrictHostKeyChecking=accept-new \
      "${SSH_OPTS[@]}" "$REMOTE" "$1"
}

section() {
  echo ""
  echo "==================================================================="
  echo "== $1"
  echo "==================================================================="
}

echo "InfluxDB Diagnose - Ziel: $REMOTE"
echo "Start: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

section "0) Systeminfo & InfluxDB-Version"
ssh_cmd "
  echo '--- uname:'; uname -a
  echo '--- influx CLI:'; command -v influx && influx -version 2>&1 | head -2 || echo 'influx CLI nicht im PATH'
  echo '--- influxd:'; command -v influxd && influxd version 2>&1 | head -2 || echo 'influxd nicht im PATH'
  echo '--- docker:'; docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -i influx || echo '(kein influx docker container oder kein docker)'
  echo '--- dienst:'; systemctl is-active influxdb 2>/dev/null || true
" || echo "SSH-Verbindung fehlgeschlagen!"

section "1) Datenbanken"
ssh_cmd "influx -port $INFLUX_HTTP_PORT $AUTH -execute 'SHOW DATABASES'" \
  || echo "FEHLER: influx CLI nicht erreichbar (Auth? Port? Docker exec noetig?)"

section "2) Retention Policies pro Datenbank (Energy-HA + heatpump)"
ssh_cmd "
  influx -port $INFLUX_HTTP_PORT $AUTH -execute 'SHOW RETENTION POLICIES ON \"Energy-HA\"'
  echo '--- heatpump:'
  influx -port $INFLUX_HTTP_PORT $AUTH -execute 'SHOW RETENTION POLICIES ON \"heatpump\"'
"

section "3) CONTINUOUS QUERIES (die Aggregations-Jobs!)"
ssh_cmd "influx -port $INFLUX_HTTP_PORT $AUTH -execute 'SHOW CONTINUOUS QUERIES'" \
  || echo "FEHLER beim Lesen der Continuous Queries"

section "4) Messungen pro Retention-Policy"
ssh_cmd "
  for rp in raw_7d agg_6m_15min agg_inf_1d; do
    echo \"### Energy-HA / \$rp:\"
    influx -port $INFLUX_HTTP_PORT $AUTH -database '\"Energy-HA\"' -execute \"SHOW MEASUREMENTS WITH IN (\\\"\$rp\\\")\" || echo '(Policy existiert nicht oder leer)'
    echo \"### heatpump / \$rp:\"
    influx -port $INFLUX_HTTP_PORT $AUTH -database 'heatpump' -execute \"SHOW MEASUREMENTS WITH IN (\\\"\$rp\\\")\" || echo '(Policy existiert nicht oder leer)'
  done
"

section "5) Feld- und Tag-Keys der relevanten Messungen"
ssh_cmd "
  for db in '\"Energy-HA\"' heatpump; do
    for rp in raw_7d agg_6m_15min agg_inf_1d; do
      ms=\$(influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SHOW MEASUREMENTS WITH IN (\\\"\$rp\\\")\" -format csv 2>/dev/null | tail -n +2 | cut -d, -f2)
      for m in \$ms; do
        echo \"### \$db /\$rp /\$m\"
        influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SHOW FIELD KEYS FROM \\\"\$rp\\\".\\\"\$m\\\"\" -format csv
        influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SHOW TAG KEYS FROM \\\"\$rp\\\".\\\"\$m\\\"\" -format csv
      done
    done
  done
"

section "6) Erster/Letzter Datenpunkt + Anzahl Punkte je Messung (letzte 180 Tage)"
ssh_cmd "
  for db in '\"Energy-HA\"' heatpump; do
    for rp in raw_7d agg_6m_15min agg_inf_1d; do
      ms=\$(influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SHOW MEASUREMENTS WITH IN (\\\"\$rp\\\")\" -format csv 2>/dev/null | tail -n +2 | cut -d, -f2)
      for m in \$ms; do
        echo \"### \$db /\$rp /\$m\"
        influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SELECT count(*), first(*, time), last(*, time) FROM \\\"\$rp\\\".\\\"\$m\\\" WHERE time > now() - 180d\" -format csv
      done
    done
  done
"

section "7) Letzte 5 Punkte je Messung (Raw + Aggregate)"
ssh_cmd "
  for db in '\"Energy-HA\"' heatpump; do
    for rp in raw_7d agg_6m_15min agg_inf_1d; do
      ms=\$(influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SHOW MEASUREMENTS WITH IN (\\\"\$rp\\\")\" -format csv 2>/dev/null | tail -n +2 | cut -d, -f2)
      for m in \$ms; do
        echo \"### \$db /\$rp /\$m (letzte 5)\"
        influx -port $INFLUX_HTTP_PORT $AUTH -database \"\$db\" -execute \"SELECT * FROM \\\"\$rp\\\".\\\"\$m\\\" ORDER BY time DESC LIMIT 5\" -format csv
      done
    done
  done
"

section "8) Shards (Zeitraeume + Groesse je Retention)"
ssh_cmd "influx -port $INFLUX_HTTP_PORT $AUTH -execute 'SHOW SHARDS' | head -60"

section "9) InfluxDB-Log der letzten 3 Tage (nur Fehler/Warnungen)"
ssh_cmd "
  if command -v journalctl >/dev/null; then
    journalctl -u influxdb --since '3 days ago' --no-pager 2>/dev/null | grep -iE 'error|warn|continuous' | tail -n 80 || echo '(keine Treffe]'
  fi
  docker_logs=\$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i influx | head -1)
  if [ -n \"\$docker_logs\" ]; then
    docker logs --since 72h \"\$docker_logs\" 2>&1 | grep -iE 'error|warn|continuous' | tail -n 80
  fi
"

echo ""
echo "==================================================================="
echo "Fertig. Bitte die komplette Ausgabe zurueckschicken."
echo "==================================================================="
