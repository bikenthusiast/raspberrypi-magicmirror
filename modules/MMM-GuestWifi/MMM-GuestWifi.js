/* MMM-GuestWifi
 *
 * Zeigt einen vorab erzeugten QR-Code für das Gast-WLAN an.
 *
 * Bewusst ohne JavaScript-Bibliothek: Der Code wird von
 * scripts/make-guest-qr.sh mit qrencode als PNG erzeugt, das Modul zeigt
 * nur das Bild. Damit kann kein Versionskonflikt einer QR-Bibliothek
 * auftreten -- es gibt keine.
 *
 * Nebeneffekt: Das Escaping der WIFI-Zeichenkette übernimmt die Shell
 * beim Erzeugen, nicht JavaScript zur Laufzeit. Sonderzeichen im
 * Passwort sind damit an genau einer Stelle zu behandeln.
 *
 * ---------------------------------------------------------------------
 * Einrichtung
 * ---------------------------------------------------------------------
 *
 *   ./scripts/make-guest-qr.sh
 *
 * Das Skript liest SSID und Passwort aus der .env und schreibt
 * guest-wifi.png in diesen Ordner. Die PNG-Datei enthält das Passwort
 * und gehört deshalb in .gitignore.
 *
 * Konfiguration:
 *
 *   {
 *     module: "MMM-GuestWifi",
 *     position: "top_left",
 *     header: "Gast-WLAN",
 *     config: {
 *       ssid: "MeinGastnetz",   // nur zur Anzeige, optional
 *       imageSize: 220
 *     }
 *   }
 *
 * MIT License
 */

Module.register("MMM-GuestWifi", {
	defaults: {
		// Dateiname des erzeugten QR-Codes, relativ zum Modulordner
		image: "guest-wifi.png",

		// Kantenlänge der Anzeige in Pixeln
		imageSize: 220,

		// Netzname unter dem Code anzeigen. Leer lassen, um ihn
		// wegzulassen -- der Name verrät bei einem Wandspiegel mehr,
		// als manchem lieb ist.
		ssid: "",

		// Hinweistext unter dem Code
		caption: "Zum Verbinden scannen"
	},

	getStyles () {
		return ["MMM-GuestWifi.css"];
	},

	start () {
		// Erzwingt einen frischen Abruf, wenn die PNG neu erzeugt wurde.
		// Ohne das liefert der Browser die alte Datei aus dem Cache.
		this.cacheBuster = Date.now();
		Log.info(`${this.name} gestartet`);
	},

	getDom () {
		const wrapper = document.createElement("div");
		wrapper.className = "guestwifi";

		const img = document.createElement("img");
		img.className = "guestwifi-code";
		img.src = `${this.file(this.config.image)}?t=${this.cacheBuster}`;
		img.width = this.config.imageSize;
		img.height = this.config.imageSize;
		img.alt = "QR-Code für das Gast-WLAN";

		// Fehlende Datei sichtbar machen, statt einen leeren Kasten zu
		// zeigen -- sonst sucht man den Fehler an der falschen Stelle.
		img.onerror = () => {
			wrapper.innerHTML = "";
			const err = document.createElement("div");
			err.className = "guestwifi-error";
			err.textContent = "QR-Code fehlt — scripts/make-guest-qr.sh ausführen";
			wrapper.appendChild(err);
		};

		wrapper.appendChild(img);

		if (this.config.ssid) {
			const ssid = document.createElement("div");
			ssid.className = "guestwifi-ssid";
			ssid.textContent = this.config.ssid;
			wrapper.appendChild(ssid);
		}

		if (this.config.caption) {
			const caption = document.createElement("div");
			caption.className = "guestwifi-caption";
			caption.textContent = this.config.caption;
			wrapper.appendChild(caption);
		}

		return wrapper;
	}
});