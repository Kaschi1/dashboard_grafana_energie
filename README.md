# Grafana Energie-Dashboards

Grafana-Dashboards und Tools für die Energie-Übersicht (Shelly Pro 3EM, Wallbox, Wärmepumpe / Panasonic Aquarea) mit InfluxDB 1.x.

## Dateien

| Datei | Beschreibung |
|---|---|
| `grafana/energy_dashboard_v3.2.json` | **Energieübersicht v3.2** – Kennzahlen (Netzbezug, Einspeisung, Solar, Wallbox, Wärmepumpe, Hausverbrauch, Eigenverbrauch, Autarkie, Kosten) mit umschaltbarer Datenquelle (15-Minuten- oder Tages-Aggregat), Momentanwerte aus Rohdaten, Leistungsverlauf und Tages-Energie über unbegrenzte Historie |
| `grafana/energy_data_diagnose_dashboard.json` | **Energie-Daten Diagnose** – prüft, ob 15-Minuten- und Tages-Aggregate vorhanden und plausibel sind (Punkte pro Tag, letzter Datenpunkt, Raw-vs-Aggregat-Vergleich) |

## Installation

1. Grafana → **Dashboards → New → Import** → JSON-Datei aus `grafana/` auswählen
2. Datasource-UID: `eetzzgckh0lxcf` (bei Bedarf im JSON an die eigene Installation anpassen: `"uid": "..."`)

## Datenmodell (InfluxDB 1.x)

Datenbank `Energy-HA` (Shelly) und `heatpump` (Panasonic Aquarea):

| Retention Policy | Dauer | Zweck |
|---|---|---|
| `raw_7d` | 7 Tage | Rohdaten, Momentanwerte |
| `agg_6m_15min` | ~6 Monate | 15-Minuten-Aggregate (Continuous Queries) |
| `agg_inf_1d` | unbegrenzt | Tages-Aggregate (Continuous Queries) |

Wichtige Messungen: `power_total`, `solar_total`, `Ladegerät_total` (raw) → `*_15min`, `*_daily` (Aggregate). Wärmepumpe: `heatpump_15min` / `heatpump_daily` mit Tag `topic='Watt/1'` (Feld `mean_value` / `daily_mean_value`).

## Wichtige Hinweise

- **Solar-Vorzeichen:** Der Shelly speichert Solarerzeugung negativ; die Dashboards drehen das Vorzeichen in den Queries (`* -1`).
- **Datenquelle-Variable:** Bei Zeiträumen bis ~6 Monate „15 Minuten" wählen, darüber „Tage" (15-min-Daten werden nach 6 Monaten gelöscht).
- **Autarkie/Eigenverbrauchsquote:** Ohne Solar im Zeitraum zeigt das Panel „No data" (Division durch 0).

## Diagnose-Script

```bash
```

Sammelt: Version, Datenbanken, Retention Policies, Continuous Queries, Messungen pro Policy, Feld-Keys, ersten/letzten Datenpunkt, Shards und Log-Fehler der letzten 3 Tage.
