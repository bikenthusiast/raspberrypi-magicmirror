# raspberrypi-magicmirror

Reproduzierbares MagicMirror²-Setup auf einem Raspberry Pi 4B — Konfiguration,
Betriebsskripte und Dokumentation. Der Spiegel dient zugleich als Ausgabefläche
für die Gestenerkennung aus [`pi-edge-ai`](https://github.com/bikenthusiast/pi-edge-ai):
eine erkannte Handgeste blendet über die HTTP-API von MMM-Remote-Control eine
versteckte Seite ein.

Dieses Repo enthält **keinen fremden Code**. MagicMirror² und alle Module haben
eigene Repos mit eigener Historie und Lizenz; hier steht nur, *welche* Module in
*welcher Version* installiert werden.

## Hardware

| Komponente | Details |
|---|---|
| Rechner | Raspberry Pi 4B Rev 1.4, 8 GB RAM |
| OS | Debian GNU/Linux 13 (Trixie), arm64, Kernel 6.18 |
| Runtime | Node 24.19, npm 11.18 |
| Display | 27″ 16:9, hochkant (aktive Fläche 33,6 × 59,8 cm) |
| Compositor | labwc (Wayland) |

## Schnellstart

```bash
git clone https://github.com/bikenthusiast/raspberrypi-magicmirror.git
cd raspberrypi-magicmirror

# 1. Module installieren (MagicMirror² muss bereits vorhanden sein)
./scripts/bootstrap.sh ~/Projects/MagicMirror

# 2. Secrets anlegen
cp .env.example ~/Projects/MagicMirror/.env
chmod 600 ~/Projects/MagicMirror/.env
$EDITOR ~/Projects/MagicMirror/.env

# 3. Starten
./scripts/start-server.sh
```

Aufruf vom Entwicklungsrechner aus über einen SSH-Tunnel:

```bash
ssh -N -L 8080:[::1]:8080 pi
```

Dann `http://localhost:8080` im Browser. Der Server bindet auf IPv6-Loopback —
`-L 8080:localhost:8080` löst auf dem Pi unter Umständen zu `127.0.0.1` auf und
läuft ins Leere.

## Aufbau

```
├── modules.txt              Modul-Manifest mit Repo-URLs und Commit-Pins
├── .env.example             Variablennamen ohne Werte
├── config/
│   ├── config.js.template   Konfiguration mit ${PLATZHALTER}
│   └── custom.css           eigene Stilanpassungen
├── scripts/
│   ├── bootstrap.sh         Module klonen/aktualisieren + npm install
│   ├── start-server.sh      envsubst + node --run server
│   └── deploy.sh            rsync vom Entwicklungsrechner auf den Pi
├── systemd/
│   └── magicmirror.service  Autostart im Server-Modus
└── docs/
    ├── troubleshooting.md
    └── adr/                 Architecture Decision Records
```

### Secrets

Drei Werte sind geheim und dürfen nicht ins Repo: der API-Key von
MMM-Remote-Control, das Gast-WLAN-Passwort und die private iCal-URL des Google
Kalenders (sie enthält einen Token, mit dem der Kalender ohne Login lesbar ist).

Sie stehen ausschließlich in `~/Projects/MagicMirror/.env` (Modus 600, in
`.gitignore`). `start-server.sh` rendert daraus per `envsubst` die
`config.js` — die ebenfalls ignoriert wird, weil sie die eingesetzten Werte
enthält.

Bearbeitet wird also `config/config.js.template`, nicht `config/config.js`.

## Eingesetzte Module

| Modul | Upstream | Zweck |
|---|---|---|
| MagicMirror² | [MagicMirrorOrg/MagicMirror](https://github.com/MagicMirrorOrg/MagicMirror) | Core, v2.37.0 |
| MMM-MVG | [KoblerS/MMM-MVG](https://github.com/KoblerS/MMM-MVG) | Münchner ÖPNV-Abfahrten |
| MMM-RAIN-MAP | [jalibu/MMM-RAIN-MAP](https://github.com/jalibu/MMM-RAIN-MAP) | Regenradar |
| MMM-QRCode | [uxigene/MMM-QRCode](https://github.com/uxigene/MMM-QRCode) | Gast-WLAN als QR-Code |
| MMM-Remote-Control | [Jopyth/MMM-Remote-Control](https://github.com/Jopyth/MMM-Remote-Control) | HTTP-API zur Steuerung |
| MMM-pages | [edward-shen/MMM-pages](https://github.com/edward-shen/MMM-pages) | Seitenrotation |
| MMM-page-indicator | [edward-shen/MMM-page-indicator](https://github.com/edward-shen/MMM-page-indicator) | Seitenpunkte |
| MMM-Globe | [Eunanibus/MMM-Globe](https://github.com/Eunanibus/MMM-Globe) | rotierender Hexagon-Globus |
| MMM-MyGCalendar | [johnster000/MMM-MyGCalendar](https://github.com/johnster000/MMM-MyGCalendar) | Monatskalender via iCal |

Wetter (Open-Meteo), Nachrichten (SZ, Tagesschau), Uhr und Alert sind
Standardmodule von MagicMirror².

## Seitenaufteilung

Rotation alle 10 Sekunden zwischen zwei Seiten. Dauerhaft sichtbar bleiben Uhr,
Wetter, MVG, Nachrichten, Regenradar und die Seitenpunkte.

| Seite | Inhalt |
|---|---|
| 0 | MMM-Globe |
| 1 | MMM-MyGCalendar |
| `gast` (versteckt) | MMM-QRCode |

Die Gast-Seite ist nicht Teil der Rotation und wird nur per Notification
aufgerufen:

```bash
KEY=$(grep MM_REMOTE_API_KEY ~/Projects/MagicMirror/.env | cut -d= -f2)
BASE=http://localhost:8080/api/notification

curl -X POST "$BASE/SHOW_HIDDEN_PAGE" \
     -H 'content-type: application/json' \
     -H "Authorization: apiKey $KEY" \
     -d '{"payload": "gast"}'

curl "$BASE/LEAVE_HIDDEN_PAGE?apiKey=$KEY"
```

Manuelles Weiterblättern in der Rotation: `PAGE_INCREMENT` / `PAGE_DECREMENT`.

## Eigenanteil

Fremdcode ist referenziert, nicht kopiert. Von mir stammen:

- **Integration** — Konfiguration von neun Modulen, Seitenaufteilung mit
  `fixed`/`hiddenPages`, deutsche Lokalisierung, MVG-Linienfilterung
- **Secrets-Handling** — Template + `.env` + `envsubst`, damit das Repo
  öffentlich sein kann
- **Betriebsmechanik** — Bootstrap mit Commit-Pins, Startskript mit Prüfung auf
  leere Variablen, systemd-Unit, rsync-Deploy
- **Dokumentation** — Troubleshooting und ADRs zu den getroffenen Entscheidungen
- **Anbindung an `pi-edge-ai`** — Gestenerkennung als Auslöser für die
  versteckte Gast-Seite

## Lizenz

MIT — siehe `LICENSE`. Die eingesetzten Module stehen unter ihren eigenen
Lizenzen, nachzulesen in den jeweils verlinkten Repos.
