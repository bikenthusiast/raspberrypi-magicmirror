#!/usr/bin/env python3
"""
presence.py -- schaltet den Spiegel abhaengig vom Radarsensor

Liest den digitalen Praesenzausgang (OT2) des Waveshare HMMD mmWave
Sensors an GPIO 27 und ruft bei Zustandswechsel die Monitor-Endpunkte
von MMM-Remote-Control auf.

Verkabelung:
    Sensor 3V3  ->  Pi Pin 1   (3,3 V)
    Sensor GND  ->  Pi Pin 6   (Masse)
    Sensor OT2  ->  Pi Pin 13  (GPIO 27)

Warum ueber die API und nicht direkt wlr-randr: MagicMirror weiss
selbst, wie es seinen Bildschirm abschaltet, und im Server-Modus gibt
es gar kein Display. Der Aufruf bleibt derselbe, egal ob spaeter
Electron am HDMI-Ausgang laeuft oder nicht.

Displaysteuerung: MMM-Remote-Control ruft intern `wlopm --on '*'` bzw.
`wlopm --off '*'` auf. Ohne laufende Wayland-Session -- also im
Server-Modus ohne angeschlossenen Monitor -- schlaegt das mit
"WAYLAND_DISPLAY is not set" fehl. Das ist erwartet und kein Fehler des
Sensors; die Umschaltung greift, sobald ein Display am HDMI-Ausgang
haengt.

Abhaengigkeiten:
    sudo apt install python3-gpiozero python3-lgpio
"""

import logging
import os
import signal
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from gpiozero import Button

# --- Konfiguration ---------------------------------------------------

GPIO_PIN = int(os.environ.get("PRESENCE_GPIO", "27"))

# Wartezeit in Sekunden, bevor nach dem letzten Erkennen abgeschaltet
# wird. Verhindert Flackern, wenn der Sensor kurz aussetzt -- etwa
# weil jemand sich abwendet.
GRACE_SECONDS = int(os.environ.get("PRESENCE_GRACE", "120"))

# Entprellung des Eingangs in Sekunden. Kurze Stoerimpulse loesen
# damit keinen Zustandswechsel aus.
BOUNCE_SECONDS = float(os.environ.get("PRESENCE_BOUNCE", "0.5"))

MM_HOST = os.environ.get("MM_HOST", "http://localhost:8080")
ENV_FILE = Path(os.environ.get("MM_ENV", Path.home() / "Projects/MagicMirror/.env"))
CONFIG_JS = Path.home() / "Projects/MagicMirror/config/config.js"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("presence")


def read_api_key():
    """API-Key aus .env lesen, ersatzweise aus der config.js."""
    if ENV_FILE.is_file():
        for line in ENV_FILE.read_text().splitlines():
            if line.startswith("MM_REMOTE_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
                if key:
                    return key

    if CONFIG_JS.is_file():
        import re
        m = re.search(r'apiKey:\s*"([^"]+)"', CONFIG_JS.read_text())
        if m:
            return m.group(1)

    log.error("Kein API-Key gefunden. Erwartet in %s oder %s", ENV_FILE, CONFIG_JS)
    sys.exit(1)


API_KEY = read_api_key()


# Merker, damit die Hinweise zu fehlendem Display und nicht laufendem
# MagicMirror nur einmal statt bei jedem Wechsel im Log stehen.
_warned = set()


def warn_once(key, message, *args):
    if key not in _warned:
        _warned.add(key)
        log.warning(message, *args)


def call(path):
    """Endpunkt aufrufen. Fehler werden geloggt, nicht geworfen --
    ein nicht laufender MagicMirror darf den Dienst nicht beenden.

    Rueckgabe True nur, wenn die Umschaltung tatsaechlich stattfand.
    MMM-Remote-Control antwortet auch mit HTTP 200, wenn der interne
    Aufruf von wlopm fehlgeschlagen ist -- deshalb wird der Body
    ausgewertet, nicht nur der Statuscode."""
    url = f"{MM_HOST}{path}?apiKey={API_KEY}"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            body = r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        if e.code == 401 or "Wrong API Key" in body:
            log.error("API-Key wird abgelehnt. Stimmt MM_REMOTE_API_KEY?")
            return False
        body_lower = body.lower()
        if "wayland_display" in body_lower:
            warn_once(
                "nodisplay",
                "Kein Display angeschlossen -- MagicMirror kann den Bildschirm "
                "nicht schalten (WAYLAND_DISPLAY nicht gesetzt). Die "
                "Praesenzerkennung selbst funktioniert; die Umschaltung greift, "
                "sobald ein Monitor am HDMI-Ausgang haengt. Weitere Meldungen "
                "dieser Art werden unterdrueckt.",
            )
            return False
        log.warning("Aufruf abgelehnt (%s, HTTP %d): %s", path, e.code, body.strip())
        return False
    except urllib.error.URLError as e:
        reason = getattr(e, "reason", e)
        if isinstance(reason, ConnectionRefusedError) or "refused" in str(reason).lower():
            warn_once(
                "notrunning",
                "MagicMirror ist nicht erreichbar unter %s. Laeuft der Server? "
                "Weitere Meldungen dieser Art werden unterdrueckt.",
                MM_HOST,
            )
        else:
            log.warning("Aufruf fehlgeschlagen (%s): %s", path, reason)
        return False

    # Erfolgreich zugestellt, aber intern gescheitert
    low = body.lower()
    if "wayland_display" in low:
        warn_once(
            "nodisplay",
            "Kein Display angeschlossen -- MagicMirror kann den Bildschirm nicht "
            "schalten (WAYLAND_DISPLAY nicht gesetzt). Die Praesenzerkennung "
            "selbst funktioniert; die Umschaltung greift, sobald ein Monitor am "
            "HDMI-Ausgang haengt. Weitere Meldungen dieser Art werden "
            "unterdrueckt.",
        )
        return False
    if '"success":false' in low.replace(" ", ""):
        log.warning("Umschaltung abgelehnt (%s): %s", path, body.strip())
        return False

    _warned.discard("nodisplay")
    _warned.discard("notrunning")
    return True


# --- Zustandslogik ---------------------------------------------------

class Mirror:
    def __init__(self):
        # Beim Start unbekannt -- der erste Wechsel setzt den Zustand.
        self.on = None
        self.off_at = None

    def turn_on(self):
        self.off_at = None
        if self.on is True:
            return
        log.info("Anwesenheit erkannt -- Display ein")
        if call("/api/monitor/on"):
            self.on = True

    def schedule_off(self):
        if self.on is False:
            return
        if self.off_at is None:
            self.off_at = time.monotonic() + GRACE_SECONDS
            log.info("Niemand da -- Abschaltung in %d s", GRACE_SECONDS)

    def tick(self):
        if self.off_at and time.monotonic() >= self.off_at:
            self.off_at = None
            log.info("Nachlaufzeit abgelaufen -- Display aus")
            if call("/api/monitor/off"):
                self.on = False


def main():
    mirror = Mirror()

    # pull_up=False: der Sensor treibt den Pin aktiv auf 3,3 V bei
    # Anwesenheit. Ein interner Pulldown haelt ihn sonst auf low.
    sensor = Button(GPIO_PIN, pull_up=False, bounce_time=BOUNCE_SECONDS)

    sensor.when_pressed = mirror.turn_on
    sensor.when_released = mirror.schedule_off

    log.info("Gestartet. GPIO %d, Nachlaufzeit %d s", GPIO_PIN, GRACE_SECONDS)

    # Ausgangszustand einmalig auswerten, damit der Spiegel nach einem
    # Neustart nicht im falschen Zustand haengt.
    if sensor.is_pressed:
        mirror.turn_on()
    else:
        mirror.schedule_off()

    def shutdown(signum, frame):
        log.info("Beende.")
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    while True:
        mirror.tick()
        time.sleep(1)


if __name__ == "__main__":
    main()