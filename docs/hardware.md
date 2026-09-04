# Hardware

Aufbau, Komponenten und Pinbelegung des Spiegels.

> [!CAUTION]
> **Offene Aufgaben vor der Montage — noch nicht erledigt.**
>
> Der Pi ist aktuell **nicht** für Witty Pi und Radarsensor vorbereitet. Geprüft
> am 27.08.2026:
>
> - [ ] **I²C aktivieren** — aktuell deaktiviert. Der Witty Pi kommuniziert
>   ausschließlich über I²C und funktioniert ohne diese Einstellung nicht.
> - [ ] **Hardware-UART aktivieren** — `/dev/serial*` existiert nicht. Ohne
>   definierten Ruhezustand auf TXD kappt der Witty Pi den Strom versehentlich.
> - [ ] **Serielle Login-Shell deaktivieren** — sonst belegt die Konsole die
>   Leitung, über die der Radarsensor sendet.
> - [ ] **PL011-UART auf GPIO 14/15 legen** — sonst liegt dort der
>   taktabhängige Mini-UART, dessen Baudrate driftet.
> - [ ] **Neustart** und Gegenprüfung (Befehle siehe unten).
>
> Solange diese Punkte offen sind, darf der Witty Pi **nicht** aufgesteckt
> werden. Ein fehlkonfigurierter Pi fährt sonst nach jedem Boot sofort wieder
> herunter, ohne dass ein Login möglich ist.

---

## Vorbereitung des Pi

### Zu erledigende Befehle

```bash
sudo raspi-config nonint do_i2c 0          # I²C aktivieren
sudo raspi-config nonint do_serial_hw 0    # Hardware-UART aktivieren
sudo raspi-config nonint do_serial_cons 1  # serielle Login-Shell deaktivieren
```

Anschließend in `/boot/firmware/config.txt` ergänzen:

```
dtoverlay=disable-bt
enable_uart=1
```

`disable-bt` verlegt den stabilen PL011-UART von Bluetooth auf GPIO 14/15. Ohne
das liegt dort der Mini-UART, dessen Baudrate am Core-Takt hängt und bei
dynamischer Taktung driftet — mit sporadischem Datenmüll, der sich schwer von
einem Verkabelungsfehler unterscheiden lässt. Preis: kein Bluetooth mehr, für
den Spiegel unerheblich.

Danach neu starten.

### Gegenprüfung nach dem Neustart

```bash
ls -l /dev/serial*                 # serial0 -> ttyAMA0 erwartet
sudo raspi-config nonint get_i2c   # 0 = aktiv
i2cdetect -y 1                     # leer, solange kein Witty Pi steckt
grep -n "w1-gpio" /boot/firmware/config.txt   # muss leer bleiben
```

`i2cdetect` zeigt später `08`, sobald der Witty Pi aufgesteckt ist.

### 1-Wire muss deaktiviert bleiben

1-Wire belegt standardmäßig GPIO 4 — genau den Pin, über den der Witty Pi sein
Shutdown-Signal empfängt. Bei aktivem 1-Wire fährt der Pi nach jedem Boot sofort
wieder herunter.

**Status:** aktuell nicht aktiv, `grep` findet keinen Eintrag. Beim Hinzufügen
künftiger Sensoren darauf achten, dass 1-Wire nicht versehentlich eingeschaltet
wird. Falls es gebraucht wird, auf einen anderen Pin legen:

```
dtoverlay=w1-gpio,gpiopin=18
```

---

## Komponenten

| Komponente | Modell | Zweck | Status |
|---|---|---|---|
| Rechner | Raspberry Pi 4B Rev 1.4, 8 GB | MagicMirror, Sensorauswertung | vorhanden |
| Netzteil | Offizielles Raspberry Pi USB-C, 5,1 V / 3,0 A | Versorgung über den Witty Pi | bestellt |
| Power-Management | UUGear Witty Pi 4 Mini | RTC, geplantes Ein- und Ausschalten | bestellt |
| Stacking-Header | 2×20 GPIO, UUGear | führt die Pins über den Witty Pi hinaus | bestellt |
| Abstandshülsen | M2.5, 10 und 12 mm, Kunststoff | Montageabstand mit Stacking-Header | bestellt |
| Präsenzsensor | Waveshare HMMD mmWave (S3KM1110) | Anwesenheitserkennung | bestellt |
| Display | 27″ 16:9, hochkant | Anzeige | offen |
| Spionglas | 27″, 4 mm | Spiegelfläche | offen |
| Lüfter | 2-adrig, an Pin 1 und 6 | Kühlung | verbaut |
| USB-TTL-Adapter | Waveshare FT232, USB-C | Konfiguration des Radarsensors | vorhanden |
| Kamera | USB-Webcam 1080p | Gestenerkennung, Phase 5 | offen |

### Warum diese Auswahl

**Witty Pi 4 Mini statt Witty Pi 4:** Die volle Variante unterscheidet sich durch
einen DC/DC-Wandler für Eingangsspannungen bis 30 V und eine CR2032-Knopfzelle
statt eines Superkondensators. Beides wird bei fester 5-V-Versorgung nicht
gebraucht. Der Kondensator hält die Uhrzeit rund 17 Stunden ohne Strom — und
selbst wenn sie verloren geht, holt der Pi sie beim nächsten Boot per NTP.

**HMMD statt LD2410C:** Die Empfindlichkeit lässt sich pro Entfernungsbereich
einzeln konfigurieren. Der Nahbereich vor dem Spiegel kann empfindlich stehen,
während weiter entfernte Zonen gedämpft werden — sonst weckt jeder Durchgang im
Flur den Spiegel.

**mmWave statt PIR:** Ein PIR-Sensor reagiert nur auf Bewegung. Wer sich vor dem
Spiegel rasiert oder die Zähne putzt, bewegt sich dafür zu wenig — das Display
ginge mitten im Gebrauch aus. mmWave misst Reflexionen und erkennt selbst
Atembewegung.

---

## GPIO-Belegung

Stand: Lüfter angeschlossen, Witty Pi noch nicht montiert.

| Pi-Pin | Signal | Verwendet von | Zweck |
|---|---|---|---|
| 1 | 3V3 | **Lüfter** | Versorgung |
| 3 | GPIO 2 (SDA1) | Witty Pi *(geplant)* | I²C zum MCU |
| 5 | GPIO 3 (SCL1) | Witty Pi *(geplant)* | I²C zum MCU |
| 6 | GND | **Lüfter** | Masse |
| 7 | GPIO 4 | Witty Pi *(geplant)* | Taster / Shutdown-Signal |
| 8 | GPIO 14 (TXD) | Witty Pi *(geplant)* | nur Überwachung, erkennt System-Aus |
| 9 | GND | **Radar** | Masse |
| 11 | GPIO 17 | Witty Pi *(geplant)* | SYS_UP-Signal |
| 13 | GPIO 27 | **Radar** | Präsenz digital (OT2) |
| 17 | 3V3 | **Radar** | Versorgung |

Alle übrigen Pins sind frei.

### Warum Radar nicht auf Pin 1 und 6

Der Lüfter belegt bereits Pin 1 (3V3) und Pin 6 (GND). Beide Signale liegen
mehrfach am Header an, der Radarsensor weicht deshalb aus:

| Sensor | Pin | statt |
|---|---|---|
| 3V3 | **17** | 1 |
| GND | **9** | 6 |
| OT2 | 13 | unverändert |

Elektrisch identisch, nur physisch woanders. 3,3 V liegt an Pin 1 und 17 an,
Masse an den Pins 6, 9, 14, 20, 25, 30, 34 und 39.

> [!NOTE]
> Die 3,3-V-Schiene des Pi ist schwächer belastbar als die 5-V-Schiene —
> üblicherweise einige hundert Milliampere für alle Verbraucher zusammen.
> Lüfter und Radarsensor teilen sie sich. Sollte der Sensor später aussetzen
> oder sich merkwürdig verhalten, ist die Stromversorgung der erste Verdacht.
> Der Lüfter ließe sich dann auf Pin 4 (5 V) umlegen, was die 3,3-V-Schiene
> entlastet — er läuft dort allerdings schneller und lauter.

### GPIO 27 statt GPIO 17

GPIO 27 wurde für den Präsenzausgang bewusst statt des naheliegenderen GPIO 17
gewählt: Letzterer wird vom Witty Pi für das SYS_UP-Signal belegt.

> [!CAUTION]
> **Der offizielle Lüfter für das Raspberry-Pi-4-Gehäuse nutzt Pin 8
> (GPIO 14) für die PWM-Steuerung.** Dieser Pin wird vom Witty Pi überwacht,
> um das Herunterfahren zu erkennen. Ein PWM-Signal dort stört die Erkennung —
> im schlimmsten Fall kappt der Witty Pi den Strom im laufenden Betrieb.
>
> Der aktuell verbaute Lüfter hängt an Pin 1 und 6, hat also keine
> Steuerleitung und ist unkritisch. Bei einem Wechsel auf einen PWM-Lüfter
> muss die Steuerleitung auf einen freien GPIO gelegt werden, niemals auf
> GPIO 14.
>
> Der Pi 4B hat **keinen** vierpoligen JST-Lüfteranschluss — den gibt es erst
> ab dem Pi 5.

### Verkabelung Radarsensor

> [!WARNING]
> **3,3 V, nicht 5 V.** Der HMMD arbeitet vollständig mit 3,3 V. Versorgung über
> Pin 2 (5 V) zerstört das Modul.

| Sensor | Pi-Pin | GPIO | Funktion |
|---|---|---|---|
| 3V3 | **17** | — | 3,3 V (Pin 1 ist vom Lüfter belegt) |
| GND | **9** | — | Masse (Pin 6 ist vom Lüfter belegt) |
| OT2 | **13** | GPIO 27 | Präsenz high/low |
| TX | — | ~~GPIO 15 (RXD)~~ | nicht nötig, siehe unten |
| RX | — | ~~GPIO 14 (TXD)~~ | **nicht verbinden** |

Für den Betrieb genügen drei Leitungen. Die UART-Verbindung wird nur zum
Konfigurieren gebraucht und läuft über den FT232-Adapter am
Entwicklungsrechner.

Beide Seiten arbeiten mit 3,3-V-Logik — kein Pegelwandler nötig.

### Warum TXD unbeschaltet bleibt

Der Witty Pi nutzt GPIO 14 nicht selbst, überwacht aber dessen Spannung: TXD ist
HIGH, solange das System läuft, und geht nach dem Herunterfahren LOW. Daran
erkennt das Board, wann es den Strom kappen darf. Angeschlossene Geräte dürfen
dieses Verhalten laut Handbuch nicht verändern, sonst bleibt der Pi dauerhaft
unter Spannung.

Deshalb wird nur die Empfangsrichtung verdrahtet. Der Sensor lässt sich damit
nicht vom Pi aus konfigurieren — Empfindlichkeitszonen und Reichweite werden
einmalig über einen USB-TTL-Adapter am Entwicklungsrechner eingestellt.

> [!NOTE]
> **Ungeklärt:** Ob der HMMD tatsächlich einen digitalen Präsenzausgang
> herausführt oder nur UART. Die Produktbeschreibungen nennen beides. Falls kein
> Digitalausgang vorhanden ist, hängt die gesamte Erkennung an der
> UART-Empfangsleitung — was funktioniert, aber über die Distanz zum extern
> aufgestellten Pi weniger robust ist. Vor dem Löten im
> [Waveshare-Wiki](https://www.waveshare.com/wiki/HMMD_mmWave_Sensor) prüfen.

---

## Montage Witty Pi

Das Board wird **nicht** direkt auf den GPIO-Header gesteckt, sondern über einen
2×20-Stacking-Header. Nur so bleiben die Pins für den Radarsensor erreichbar.

Laut Handbuch die langen Pins des Stacking-Headers durch die Löcher auf der
Rückseite führen, dann ein Stahllineal zwischen die beiden Pinreihen legen und
das Board damit gleichmäßig herunterdrücken, bis es am Kunststoff anliegt.

**Beigelegt sind M2.5×10-Schrauben und 4-mm-Spacer** — mit Stacking-Header
reichen die nicht mehr. Der Plattenabstand ergibt sich aus der Höhe des
Header-Kunststoffs (8,5 mm) plus der Buchsenleiste auf der Unterseite des Witty
Pi. Nach Lieferung mit dem Messschieber nachmessen und die passende Hülsenlänge
verwenden.

### Stromversorgung

> [!IMPORTANT]
> Das Netzteil geht in den **USB-C-Anschluss des Witty Pi**, nicht in den Pi.
> Nur so kann das Board die Stromzufuhr kappen. Wird der Pi direkt versorgt, ist
> die harte Abschaltung wirkungslos.

Die Ausgangsleistung des Witty Pi liegt bei bis zu 2,5 A — das ist die Grenze,
nicht die 3,0 A des Netzteils. Für Pi 4B plus Webcam ausreichend.

### Einstellung, die nicht auf Standard bleiben darf

| Einstellung | Standard | Für den Spiegel |
|---|---|---|
| Default state when powered | OFF | **ON** |

Auf `OFF` startet der Pi nach Anlegen der Versorgung nicht von selbst, sondern
wartet auf einen Tastendruck. Nach einem Stromausfall bliebe der Spiegel dunkel,
bis jemand hinter das Gerät greift. Zu ändern in `wittyPi.sh` unter Punkt 11
(*View/change other settings*).

### Software

> [!WARNING]
> UUGear entwickelt und testet ausdrücklich gegen Raspberry Pi OS. Dieser Pi
> läuft auf Debian Trixie, das noch recht frisch ist. Die Installation deshalb
> **sofort nach Lieferung** testen, nicht erst zum geplanten Termin:
>
> ```bash
> wget https://www.uugear.com/repo/WittyPi4/install.sh
> sudo sh install.sh
> ```

Der Taster auf dem Board bleibt der Rückweg: Er fährt den Pi sauber herunter und
wieder hoch. Wenn ein Zeitplan zur falschen Zeit abschaltet, kommt man damit
ohne Ausbau wieder heran — ein Argument mehr für den zugänglichen externen
Aufbau.

---

## Displaysteuerung

MMM-Remote-Control schaltet den Bildschirm über die Endpunkte
`/api/monitor/on` und `/api/monitor/off`. Intern ruft es dafür
`wlopm --on '*'` bzw. `wlopm --off '*'` auf — ein Wayland-Werkzeug, nicht das
ältere `vcgencmd` oder `tvservice`.

Test bei laufendem Server:

```bash
KEY=$(grep -oP 'apiKey:\s*"\K[^"]+' ~/Projects/MagicMirror/config/config.js)
curl -s "http://localhost:8080/api/monitor/on?apiKey=$KEY"
```

> [!NOTE]
> **Ohne angeschlossenen Monitor schlägt der Aufruf erwartungsgemäß fehl:**
>
> ```json
> {"success":false,"info":{"cmd":"wlopm --on '*'",
>  "stderr":"ERROR: WAYLAND_DISPLAY is not set."}}
> ```
>
> Im Server-Modus existiert keine grafische Session, also auch kein Display
> zum Schalten. Das ist kein Fehler der Präsenzerkennung — der Sensor
> funktioniert, nur greift die Umschaltung erst mit einem Monitor am
> HDMI-Ausgang.
>
> `presence.py` erkennt diesen Fall und schreibt die Meldung nur einmal ins
> Log statt bei jedem Zustandswechsel.

### Zwei Wege, einer davon aussagekräftiger

| Endpunkt | Antwort ohne Display | Brauchbar? |
|---|---|---|
| `/api/monitor/on` | `success: false` mit `wlopm`-Fehler | ja, meldet den echten Zustand |
| `/api/notification/MONITORON` | `success: true` | nein, bestätigt nur den Versand |

Der Notification-Weg meldet Erfolg, sobald die Nachricht im Frontend verteilt
wurde — ob jemand darauf reagiert, sagt er nicht. Deshalb nutzt `presence.py`
die Monitor-Endpunkte.

### Beim ersten Monitoranschluss zu prüfen

- Läuft eine Wayland-Session, ist `WAYLAND_DISPLAY` gesetzt?
- Greift `wlopm --off '*'` von Hand auf der Konsole des Pi?
- Schaltet der Bildschirm nach der Nachlaufzeit tatsächlich ab?

Falls `wlopm` unter labwc nicht zuverlässig arbeitet, wäre `wlr-randr --output
HDMI-A-1 --off` die Alternative. Dann würde `presence.py` das Kommando direkt
aufrufen statt über MagicMirror zu gehen — die Stelle im Skript ist klar
abgegrenzt.

---

## Rahmenaufbau

Der Pi wird **extern unter dem Spiegel** montiert, nicht dahinter. Gründe:
Zugänglichkeit für SD-Karte, Taster und Nachrüstungen; keine addierte Abwärme im
geschlossenen Kasten; geringere Bautiefe des Spiegels.

### Schichtaufbau von vorn nach hinten

| Schicht | Hinweis |
|---|---|
| Spionglas | metallbedampft, sperrt Funk |
| Schwarze Blende | verdeckt den inaktiven Panelrand |
| LCD-Panel | Metallchassis, sperrt Funk vollständig |
| Luftspalt | Kabel, Belüftung |
| Rückwand | MDF, drückt das Paket gegen den Falz |

Zwischen Spionglas und Panel darf **kein Spalt** sein — schon ein Millimeter
erzeugt eine sichtbare Doppelspiegelung. Der Druck kommt von hinten über die
Rückwand, dazwischen ein Streifen Moosgummi.

### Maße 27″ 16:9

| Größe | Wert |
|---|---|
| Aktive Fläche quer | 59,8 × 33,6 cm |
| Aktive Fläche hochkant | 33,6 × 59,8 cm |
| Diagonale | 68,6 cm |
| Auflösung hochkant | 1080 × 1920 |

Das sind Panel-Maße ohne Rahmen. Am konkreten Gerät nachmessen.

### Einbauort des Radarsensors

Spionglas ist metallbedampft und dämpft Funkwellen, das LCD-Chassis sperrt
vollständig. Der Sensor muss deshalb **außerhalb der Panelfläche und außerhalb
der bedampften Glasfläche** sitzen.

Praktikabel: eine Tasche in der unteren Rahmenleiste mit ein bis zwei Millimeter
Restholz. Holz und MDF sind für mmWave weitgehend transparent.

Der Rahmen sollte deshalb nicht endgültig verschlossen werden, bevor die
Sensorposition feststeht.

---

## Offene Punkte

| Punkt | Status |
|---|---|
| I²C aktiviert | **erledigt** |
| Hardware-UART, `/dev/serial0` vorhanden | **erledigt** |
| Digitalausgang am HMMD vorhanden? | **erledigt** — OT2 an J2 Pin 5, high bei Anwesenheit |
| Sensoranbindung: GPIO oder ESP32 | **entschieden** — direkt am GPIO, Variante A |
| Sensor in Betrieb genommen | **erledigt** — 115200 8N1, Firmware v1.6.1 |
| Serielle Login-Shell deaktiviert | prüfen mit `raspi-config nonint get_serial_cons` |
| Hülsenlänge messen | beim Aufstecken des Stacking-Headers |
| Witty-Pi-Software unter Trixie | Installation lief, Board noch nicht montiert |
| Lüfter beim Umbau umstecken | vor der Montage notieren — nach dem Aufstecken unzugänglich |
| Displaysteuerung unter Wayland/labwc | Werkzeug bekannt (`wlopm`), Test braucht Monitor |
| Empfindlichkeitszonen justieren | erst am Einbauort sinnvoll |
| CPU-Reserve für Gestenerkennung | offen, vor Phase 5 durch Messung |