# MMM-GuestWifi

Eigenentwicklung. Zeigt einen QR-Code für das Gast-WLAN an — Besucher scannen
ihn mit der Kamera-App und sind verbunden, ohne dass jemand ein Passwort
vorlesen muss.

## Voraussetzungen

> [!IMPORTANT]
> **`qrencode` muss installiert sein.** Ohne das Paket bricht
> `make-guest-qr.sh` ab mit:
>
> ```
> FEHLER: qrencode fehlt. Installation: sudo apt install qrencode
> ```

| Voraussetzung | Installation | Zweck |
|---|---|---|
| `qrencode` | `sudo apt install qrencode` | erzeugt die PNG-Datei |
| `.env` mit Zugangsdaten | siehe unten | Quelle für SSID und Passwort |

Auf macOS lautet der Befehl `brew install qrencode` — relevant, falls der Code
auf dem Entwicklungsrechner erzeugt und übertragen wird.

Sonst keine. Das Modul bringt bewusst **keine JavaScript-Abhängigkeit** mit.

## Warum ohne QR-Bibliothek

Das zuvor eingesetzte `uxigene/MMM-QRCode` erzeugte den Code zur Laufzeit im
Browser und scheiterte an einem Versionskonflikt:

```
Uncaught TypeError: QRCode.toCanvas is not a function
```

Das Modul erwartete die API des npm-Pakets `qrcode`, im globalen Namensraum
landete aber eine andere Bibliothek. Solche Konflikte entstehen bei wenig
gepflegten Modulen mit offener Versionsangabe immer wieder — `npm install` holt
dann eine neuere Hauptversion mit geänderter API.

Dieses Modul umgeht das Problem, statt es zu lösen: Der Code wird einmalig per
`qrencode` als PNG erzeugt, das Modul zeigt nur das Bild. Es gibt keine
Bibliothek, die brechen könnte.

Zwei weitere Vorteile:

**Das Escaping passiert an einer Stelle.** Im WIFI-URI-Schema müssen `\ ; , : "`
mit einem Backslash versehen werden. Das übernimmt die Shell beim Erzeugen, statt
dass es in JavaScript zur Laufzeit passieren muss — wo ein literaler Backslash
doppelt geschrieben werden will und der Fehler erst beim Scannen auffällt.

**Das Passwort verlässt das Gerät nicht.** `qrencode` arbeitet lokal, anders als
die zahllosen Online-Generatoren.

## Einrichtung

```bash
# Modul verlinken
ln -sfn ~/Projects/raspberrypi-magicmirror/modules/MMM-GuestWifi \
        ~/Projects/MagicMirror/modules/MMM-GuestWifi

# QR-Code erzeugen
cd ~/Projects/raspberrypi-magicmirror
./scripts/make-guest-qr.sh
```

Das Skript liest aus der `.env`:

| Variable | Pflicht | Bedeutung |
|---|---|---|
| `GUEST_WIFI_SSID` | ja | Netzname, exakt wie ausgesendet |
| `GUEST_WIFI_PASS` | ja | Passwort des Gastnetzes |
| `GUEST_WIFI_TYPE` | nein | `WPA` (Standard) oder `nopass` für offene Netze |

Zur Kontrolle gibt es den Code zusätzlich im Terminal aus. Der lässt sich direkt
mit dem Handy scannen — funktioniert er dort, liegt ein späteres Problem am
Spiegel und nicht an der Zeichenkette.

Nach jeder Änderung von SSID oder Passwort das Skript erneut ausführen.

## Konfiguration

```js
{
    module: "MMM-GuestWifi",
    position: "top_left",
    header: "Gast-WLAN",
    config: {
        imageSize: 220
    }
}
```

| Option | Standard | Bedeutung |
|---|---|---|
| `image` | `"guest-wifi.png"` | Dateiname im Modulordner |
| `imageSize` | `220` | Kantenlänge in Pixeln |
| `ssid` | `""` | Netzname unter dem Code anzeigen. Leer lassen, um ihn wegzulassen |
| `caption` | `"Zum Verbinden scannen"` | Hinweistext |

`ssid` ist bewusst standardmäßig leer: Auf einem Wandspiegel verrät der Netzname
mehr, als manchem lieb ist — für einen Gast reicht der Code.

## Versteckte Seite

Im Zusammenspiel mit MMM-pages liegt das Modul auf einer versteckten Seite und
ist nicht Teil der Rotation:

```js
hiddenPages: {
    gast: ["MMM-GuestWifi"]
}
```

### Aufruf aus der Browserkonsole

```js
MM.getModules()[0].sendNotification("SHOW_HIDDEN_PAGE", "gast")
MM.getModules()[0].sendNotification("LEAVE_HIDDEN_PAGE")
```

Beide geben `undefined` zurück — `sendNotification` hat keinen Rückgabewert.
Das ist kein Fehler.

### Aufruf per HTTP

Über MMM-Remote-Control, damit die Seite auch von Skripten, Tastern oder
später der Gestenerkennung aufgerufen werden kann:

```bash
KEY=$(grep -oP 'apiKey:\s*"\K[^"]+' ~/Projects/MagicMirror/config/config.js)

curl -H "Authorization: apiKey $KEY" \
     "http://localhost:8080/api/notification/SHOW_HIDDEN_PAGE/gast"

curl -H "Authorization: apiKey $KEY" \
     "http://localhost:8080/api/notification/LEAVE_HIDDEN_PAGE"
```

> [!IMPORTANT]
> **Der API-Key muss in den Header, nicht in die URL.** Und der Seitenname
> `gast` ist ein Pfadsegment, kein Query-Parameter.
>
> Der Grund steht in `MMM-Remote-Control/API/api.js`:
>
> ```js
> 537   payload = request.params.p;
> 539   payload = {param: request.params.p, ...request.query};
> ```
>
> Zeile 537 reicht den Wert unverpackt durch — aber nur, wenn die Anfrage
> **keinen** Query-String hat. Sobald einer vorhanden ist, und `?apiKey=…` ist
> einer, greift Zeile 539 und baut ein Objekt daraus. MMM-pages sucht dann
> nach einer Seite namens `[object Object]`:
>
> ```
> [MMM-pages] Hidden page "[object Object]" does not exist!
> ```
>
> Dieselbe Meldung erscheint bei Übergabe im Body. Ein nackter String wird vom
> Body-Parser zusätzlich abgelehnt (`"gast" is not valid JSON`).
>
> Nebeneffekt der Header-Variante: Der Schlüssel landet nicht in Server-Logs
> oder im Shell-Verlauf.

Für Notifications ohne Payload — etwa `LEAVE_HIDDEN_PAGE` — funktioniert auch
`?apiKey=…` in der URL. Der Header ist trotzdem die bessere Gewohnheit.

> [!NOTE]
> `MMM-SpotifyPages` steuert dieselbe Seitenauswahl und weiß nichts von der
> versteckten Seite. Ein Rotationsschritt oder ein Spotify-Ereignis blendet den
> QR-Code deshalb wieder aus. Für einen Test die Rotation vorher anhalten:
>
> ```js
> m = MM.getModules().find(x => x.name === "MMM-SpotifyPages")
> m.stopRotation()
> ```

## Sicherheit

> [!CAUTION]
> **`guest-wifi.png` enthält das WLAN-Passwort** und gehört in die `.gitignore`:
>
> ```gitignore
> modules/MMM-GuestWifi/guest-wifi.png
> ```
>
> Der Pre-Commit-Hook prüft Textinhalte und erkennt Binärdateien nicht. Diese
> Zeile ist deshalb nicht optional.

Der Code wird aus der `.env` erzeugt, die ebenfalls nicht im Repo liegt. Im
Repository steht damit weder das Passwort noch etwas, woraus es sich ableiten
ließe.

Ein permanent sichtbarer WLAN-Code ist beim Gastnetz vertretbar, weil es vom
Hauptnetz isoliert ist. Für das Hauptnetz wäre davon abzuraten.

## Gestaltung

Der weiße Rahmen um den Code kommt aus dem CSS und ist funktional: QR-Codes
brauchen eine helle Ruhezone, sonst scannen viele Kameras auf schwarzem Grund
nicht zuverlässig.

Die Fehlerkorrektur steht auf Stufe M. Das ist gutmütiger gegenüber
Spiegelungen im Glas als die sparsamere Stufe L, ohne den Code unnötig dicht zu
machen.

## Fehlersuche

| Symptom | Ursache |
|---|---|
| „QR-Code fehlt" im Modul | `make-guest-qr.sh` wurde nicht ausgeführt oder der Symlink zeigt ins Leere |
| Alter Code trotz Neuerzeugung | sollte der Cache-Buster verhindern; sonst hart neu laden |
| Code scannt, verbindet aber nicht | SSID stimmt nicht zeichengenau, oder der Verschlüsselungstyp passt nicht |
| Code wird gar nicht erkannt | zu klein — `imageSize` erhöhen |

Gegenprobe unabhängig vom Spiegel:

```bash
qrencode -t ANSIUTF8 'WIFI:T:WPA;S:MeineSSID;P:meinPasswort;;'
```

Scannt dieser Code und der im Spiegel nicht, liegt es an der Anzeige. Scannt
keiner von beiden, stimmt die Zeichenkette nicht.