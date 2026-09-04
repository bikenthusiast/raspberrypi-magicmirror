# Setup von null

Vollständiger Neuaufbau auf einer frischen microSD-Karte. Dieses Dokument ist
zugleich die Probe aufs Exempel: Was hier fehlt, fehlt auch im Repo.

> [!NOTE]
> **Status: Gerüst, noch nicht durchlaufen.**
>
> Abschnitte mit `<!-- TODO -->` sind beim Nachbauen auszufüllen. Alles, wofür
> während des Durchlaufs nachgeschlagen oder überlegt werden muss, gehört
> notiert — genau diese Stellen sind die Lücken in der Dokumentation.
>
> Empfehlung: Die SSH-Sitzung mitprotokollieren und die Doku hinterher aus dem
> Transkript destillieren, nicht aus dem Gedächtnis:
>
> ```bash
> script -f ~/setup-log.txt
> ```

**Zuletzt vollständig durchlaufen:** <!-- TODO: Datum -->
**Dauer:** <!-- TODO -->

---

## 0 · Voraussetzungen

### Hardware

| Teil | Anforderung |
|---|---|
| Raspberry Pi | 4B, 8 GB RAM |
| microSD | 128 GB, <!-- TODO: Modell und Geschwindigkeitsklasse --> |
| Netzteil | offizielles USB-C, 5,1 V / 3,0 A |
| Netzwerk | WLAN oder Ethernet |

### Auf dem Entwicklungsrechner

| Werkzeug | Zweck | Installation |
|---|---|---|
| Raspberry Pi Imager | Karte beschreiben | <!-- TODO --> |
| SSH-Schlüssel | Zugang ohne Passwort | vorhanden unter `~/.ssh/` |

---

## 1 · Karte beschreiben

> [!IMPORTANT]
> Die erweiterten Einstellungen im Imager (Zahnrad bzw. `Strg+Shift+X`) sind
> **nicht optional**. Ohne sie hat der Pi keinen SSH-Zugang und kein WLAN — dann
> braucht es Monitor und Tastatur, um überhaupt hineinzukommen.

### OS-Auswahl

| Feld | Wert |
|---|---|
| Gerät | Raspberry Pi 4 |
| Betriebssystem | <!-- TODO: exakte Bezeichnung, 64-bit, mit oder ohne Desktop --> |
| Speicher | microSD |

**Entscheidung Desktop oder Lite:** <!-- TODO -->

Der Spiegel läuft aktuell im Server-Modus ohne grafische Session, braucht also
zunächst keinen Desktop. Für den späteren Electron-Betrieb am HDMI-Ausgang wird
ein Compositor gebraucht. Welche Variante gewählt wurde und warum, hier
festhalten.

### Erweiterte Einstellungen

| Feld | Wert | Anmerkung |
|---|---|---|
| Hostname | `raspberrypi` | wird für `raspberrypi.local` gebraucht |
| Benutzername | `tobiask` | Pfade in allen Skripten hängen daran |
| SSH aktivieren | ja, **mit Public-Key** | Passwort-Login vermeiden |
| Public Key | <!-- TODO: welcher Key, wo liegt er --> | |
| WLAN-SSID | <!-- TODO --> | |
| WLAN-Land | DE | ohne dies bleibt das WLAN teils deaktiviert |
| Locale | Europe/Berlin, de-DE | |
| Tastaturlayout | de | |

> [!CAUTION]
> Der Benutzername muss `tobiask` lauten. Sämtliche Pfade in Skripten,
> systemd-Units und in der `deploy.sh` sind darauf verdrahtet. Ein anderer Name
> bedeutet Nacharbeit an mehreren Stellen.

**Notieren, welchen Public Key du hinterlegt hast** — auf einem dritten Rechner
kommst du sonst nicht hinein.

---

## 2 · Erste Verbindung

```bash
ssh tobiask@raspberrypi.local
```

> [!TIP]
> Bei mDNS- oder IPv6-Problemen hilft `AddressFamily inet` in `~/.ssh/config`,
> das erzwingt IPv4. Die vorhandene Konfiguration nutzt den Alias `pi`:
>
> ```
> Host pi
>     HostName raspberrypi.local
>     User tobiask
>     AddressFamily inet
> ```

<!-- TODO: Hat die Verbindung auf Anhieb geklappt? Wenn nein, was war nötig? -->

### Grundaktualisierung

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

<!-- TODO: Dauer notieren -->

---

## 3 · Systemeinstellungen

> [!CAUTION]
> Diese Einstellungen sind **vor** dem Aufstecken des Witty Pi vorzunehmen. Ein
> fehlkonfigurierter Pi fährt mit aufgestecktem Board nach jedem Boot sofort
> wieder herunter, ohne dass ein Login möglich ist.
>
> Details und Begründungen in [`hardware.md`](hardware.md).

```bash
sudo raspi-config nonint do_i2c 0          # I²C aktivieren
sudo raspi-config nonint do_serial_hw 0    # Hardware-UART aktivieren
sudo raspi-config nonint do_serial_cons 1  # serielle Login-Shell deaktivieren
```

In `/boot/firmware/config.txt` ergänzen:

```
dtoverlay=disable-bt
enable_uart=1
```

Prüfen nach dem Neustart:

```bash
ls -l /dev/serial*                 # serial0 -> ttyAMA0
sudo raspi-config nonint get_i2c   # 0 = aktiv
grep -n "w1-gpio" /boot/firmware/config.txt   # muss leer bleiben
```

<!-- TODO: Ausgaben notieren -->

---

## 4 · Werkzeuge

<!-- TODO: Welche Pakete wurden tatsächlich gebraucht? -->

```bash
sudo apt install -y git tmux zsh qrencode gettext-base
```

### zsh und oh-my-zsh

<!-- TODO: falls verwendet, Installationsschritte hier -->

Syntax-Highlighting und Autosuggestions:

```bash
sudo apt install -y zsh-autosuggestions zsh-syntax-highlighting
```

Am **Ende** der `~/.zshrc`, Reihenfolge ist relevant — syntax-highlighting muss
zuletzt kommen, sonst brechen die ZLE-Widgets:

```zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

---

## 5 · Node.js

> [!IMPORTANT]
> Die Version ist kritisch. Der aktuelle Stand läuft auf **Node 24.19**, was
> `apt install nodejs` unter Trixie **nicht** liefert.

<!-- TODO: Wie wurde Node 24 tatsächlich installiert? NodeSource, nvm, fnm? -->

```bash
# TODO: konkrete Befehle
node --version    # erwartet: v24.x
npm --version
```

---

## 6 · MagicMirror

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/MagicMirrorOrg/MagicMirror.git
cd MagicMirror
npm install --omit=dev
```

<!-- TODO: Dauer, Warnungen, benötigter Speicherplatz -->

> [!NOTE]
> `npm install` auf dem Pi dauert spürbar länger als auf dem Entwicklungsrechner.
> Hier in `tmux` arbeiten, damit ein Verbindungsabbruch den Vorgang nicht
> abbricht.

---

## 7 · Eigenes Repo

```bash
cd ~/Projects
git clone git@github.com:bikenthusiast/raspberrypi-magicmirror.git
cd raspberrypi-magicmirror
git config core.hooksPath .githooks
```

> [!IMPORTANT]
> `core.hooksPath` ist eine **lokale** Einstellung und wandert nicht mit dem
> Repo. Ohne diesen Befehl läuft der Pre-Commit-Hook nicht, und Secrets können
> unbemerkt committet werden.

<!-- TODO: Ging der Klon per SSH oder war ein Deploy-Key nötig? -->

---

## 8 · Module installieren

```bash
./scripts/bootstrap.sh ~/Projects/MagicMirror
```

<!-- TODO: Lief das Skript durch? Welche Module brauchten Nacharbeit? -->

Falls von Hand, die Liste steht in `modules.txt`. Für jedes Modul:

```bash
cd ~/Projects/MagicMirror/modules
git clone <url>
cd <modul> && npm install --omit=dev   # nur wenn package.json Abhängigkeiten hat
```

> [!CAUTION]
> Der Ordnername muss **exakt** dem Modulnamen in der Config entsprechen,
> Groß- und Kleinschreibung inklusive. Ein konfiguriertes, aber nicht
> auffindbares Modul führt zu einem 404 im Loader — die Script-Kette bricht ab
> und **alle** nachfolgenden Module starten nicht mehr. Der Spiegel bleibt
> komplett schwarz.
>
> Siehe [`troubleshooting.md`](troubleshooting.md).

---

## 9 · Secrets

Die echten Werte liegen ausschließlich lokal und sind nirgends im Repo.

```bash
cp ~/Projects/raspberrypi-magicmirror/.env.example ~/Projects/MagicMirror/.env
chmod 600 ~/Projects/MagicMirror/.env
$EDITOR ~/Projects/MagicMirror/.env
```

Zu beschaffen:

| Wert | Quelle |
|---|---|
| `MM_REMOTE_API_KEY` | selbst erzeugen: `openssl rand -hex 16` |
| `GUEST_WIFI_SSID`, `GUEST_WIFI_PASS` | FRITZ!Box → WLAN → Gastzugang |
| `GCAL_ICAL_URL` | Google Kalender → Einstellungen → Privatadresse im iCal-Format |
| Spotify Client ID / Secret | developer.spotify.com/dashboard |
| Spotify Access / Refresh Token | Autorisierungslauf, siehe unten |

### Spotify autorisieren

> [!WARNING]
> Redirect-URI muss `http://127.0.0.1:8888/callback` lauten. `localhost` wird
> von Spotify seit 2025 abgelehnt — sowohl im Dashboard als auch im Modulcode.
>
> Die Autorisierung auf dem **Entwicklungsrechner** durchführen, nicht auf dem
> Pi. Sie erzeugt nur Tokens, die anschließend kopiert werden. Das spart einen
> zweiten SSH-Tunnel für Port 8888.

<!-- TODO: Konkrete Schritte, sobald einmal durchlaufen -->

---

## 10 · Symlinks

> [!CAUTION]
> Dieser Schritt wird beim Nachbauen garantiert vergessen. Ohne ihn findet
> MagicMirror weder die Konfiguration noch das eigene Modul.

Die echte `config.js` und das eigene Modul liegen im Repo, MagicMirror bekommt
nur Verweise darauf. So gibt es genau eine Datei zum Bearbeiten.

```bash
# Konfiguration
ln -sfn ~/Projects/raspberrypi-magicmirror/config/config.js \
        ~/Projects/MagicMirror/config/config.js

# eigenes Modul
ln -sfn ~/Projects/raspberrypi-magicmirror/modules/MMM-SpotifyPages \
        ~/Projects/MagicMirror/modules/MMM-SpotifyPages
```

> [!TIP]
> `ln -sfn` statt `ln -s`. Existiert das Ziel bereits als Verzeichnis, legt
> `ln -s` den Link **darin** an statt ihn zu ersetzen — dann liegt alles eine
> Ebene zu tief und wird nicht gefunden.

Prüfen — `-L` folgt dem Link und zeigt die Zieldatei:

```bash
ls -l  ~/Projects/MagicMirror/modules/ | grep SpotifyPages
ls -lL ~/Projects/MagicMirror/config/config.js
```

Da die echte `config.js` in `.gitignore` steht, muss sie auf einem frischen
System aus der Beispieldatei erzeugt werden:

```bash
cd ~/Projects/raspberrypi-magicmirror
cp config/config.js.example config/config.js
$EDITOR config/config.js    # Platzhalter durch echte Werte ersetzen
```

<!-- TODO: Oder wird config.js aus dem Template gerendert? Entscheidung festhalten. -->

---

## 11 · Erster Start

```bash
tmux new -s mm
cd ~/Projects/MagicMirror
node --run server
```

Vom Entwicklungsrechner aus, in einem **eigenen** Terminal:

```bash
ssh -N -L 8080:[::1]:8080 pi
```

Dann `http://localhost:8080` **im Inkognito-Fenster** öffnen.

> [!WARNING]
> Inkognito ist keine Marotte. MMM-Remote-Control registriert einen Service
> Worker, der eine kaputte Seite cachen und harte Reloads überleben kann. Im
> normalen Fenster ist „Seite bleibt schwarz" dann kein verlässliches Signal
> über den Zustand der Konfiguration.
>
> Siehe [`troubleshooting.md`](troubleshooting.md).

### Verifikation

| Prüfung | Erwartung |
|---|---|
| Uhr sichtbar | rendert rein im Browser, funktioniert immer |
| Wetter | Log zeigt `Weather provider openmeteo initialized` |
| Newsfeed | Log zeigt `Broadcasting N items` |
| MVG | Abfahrten für die konfigurierte Haltestelle |
| Seitenrotation | Wechsel alle 10 s zwischen Kalender und Globus |
| Spotify | Musik starten → Wechsel auf Seite 2 mit Songtext |
| Gast-WLAN | QR-Code per Notification einblenden und scannen |
| Remote-Control-API | `curl` mit dem API-Key antwortet |

<!-- TODO: Was hat beim ersten Durchlauf nicht funktioniert? -->

---

## 12 · Autostart

<!-- TODO: systemd-Unit oder Electron-Autostart? Entscheidung und Schritte -->

---

## Nacharbeit an der Dokumentation

Nach dem Durchlauf zu aktualisieren:

- [ ] Alle `<!-- TODO -->` ersetzt
- [ ] Datum und Dauer oben eingetragen
- [ ] Neu entdeckte Stolpersteine in `troubleshooting.md` ergänzt
- [ ] `modules.txt` um Commit-Pins ergänzt, falls noch offen
- [ ] README verweist auf dieses Dokument

> [!NOTE]
> Wenn beim Durchlaufen an einer Stelle in alten Notizen oder Chatverläufen
> nachgeschlagen werden musste, ist genau das eine Lücke. Sofort notieren, nicht
> am Abend rekonstruieren.