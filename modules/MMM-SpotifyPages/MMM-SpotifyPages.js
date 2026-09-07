/* MMM-SpotifyPages
 *
 * Steuert MMM-pages abhaengig vom Spotify-Wiedergabestatus.
 *
 *   Wiedergabe laeuft   ->  feste Spotify-Seite (Player + Lyrics)
 *   Wiedergabe pausiert ->  Rotation ueber die Leerlaufseiten
 *
 * Beispielaufteilung in MMM-pages:
 *
 *   modules: [
 *     ["MMM-MVG",       "MMM-MyGCalendar"],   // 0  Leerlauf
 *     ["MMM-MVG",       "MMM-Globe"],         // 1  Leerlauf
 *     ["MMM-OnSpotify", "MMM-LiveLyrics"]     // 2  Wiedergabe
 *   ]
 *
 * ---------------------------------------------------------------------
 * Warum Polling statt nur Notifications
 * ---------------------------------------------------------------------
 *
 * MMM-OnSpotify sendet NOW_PLAYING nur an zwei Flanken: bei einem neuen
 * Titel (playerIsEmpty: false) und beim Leeren des Players
 * (playerIsEmpty: true). Pausieren loest keine der beiden aus -- Spotify
 * raeumt den Player erst nach langer Inaktivitaet ab. Der Spiegel bliebe
 * bis dahin auf der Spotify-Seite stehen.
 *
 * Der tatsaechliche Zustand liegt aber im Frontend offen: MMM-OnSpotify
 * fuehrt ihn in "lastStatus" mit den Werten isPlaying, isPlayingHidden,
 * isEmpty und isEmptyHidden. Das Suffix "Hidden" sagt nur, ob das Modul
 * gerade sichtbar ist; ausgewertet wird der Praefix.
 *
 * Dieses Modul liest den Wert regelmaessig aus. NOW_PLAYING bleibt als
 * schneller Zusatzweg erhalten, damit der Wechsel beim Start eines
 * Titels ohne Verzoegerung erfolgt.
 *
 * ---------------------------------------------------------------------
 * Voraussetzung in der config.js
 * ---------------------------------------------------------------------
 *
 * MMM-pages: eigene Rotation abschalten, sonst ueberschreibt dessen
 * Timer die hier getroffene Auswahl.
 *
 *   timings: { default: 0 }
 *
 * MIT License
 */

Module.register("MMM-SpotifyPages", {
	defaults: {
		// Seite, die bei laufender Wiedergabe gezeigt wird
		spotifyPage: 2,

		// Seiten, die im Leerlauf rotieren
		idlePages: [0, 1],

		// Rotationsdauer im Leerlauf in ms. 0 haelt auf der ersten
		// Leerlaufseite an.
		idleRotationMs: 10000,

		// Wartezeit, bevor nach dem Pausieren zurueckgeschaltet wird.
		// Verhindert Springen bei kurzen Luecken zwischen zwei Titeln.
		graceMs: 30000,

		// Abstand der Statusabfrage in ms. 0 schaltet das Polling ab --
		// dann laeuft es rein flankengesteuert und Pausieren wird nicht
		// erkannt.
		pollMs: 5000,

		// Modul, dessen lastStatus ausgewertet wird
		spotifyModule: "MMM-OnSpotify",

		// Solange eine versteckte Seite von MMM-pages aktiv ist, haelt
		// sich dieses Modul komplett zurueck -- weder Rotation noch
		// Spotify-Wechsel duerfen den QR-Code wegblenden.
		respectHiddenPages: true,

		// Mindestabstand zwischen zwei Seitenwechseln in ms.
		//
		// MMM-pages blendet beim Wechsel mit setTimeout aus und wieder
		// ein. Kommt waehrend dieser Animation ein zweiter Wechsel,
		// kann die Freigabe fuer die alte Seite verlorengehen -- die
		// Module bleiben dann mit einem lockString von MMM-pages
		// gesperrt zurueck und sind dauerhaft unsichtbar, obwohl die
		// Seite korrekt gesetzt ist.
		//
		// Auffaellig wird das beim Verlassen der Spotify-Seite: dort
		// folgen der Wechsel zurueck und der erste Rotationsschritt
		// dicht aufeinander.
		minSwitchGapMs: 700,

		// Automatisch zurueckschalten, wenn eine versteckte Seite so
		// lange offen war. 0 schaltet die Automatik ab, dann bleibt sie
		// bis zu einem LEAVE_HIDDEN_PAGE stehen.
		hiddenPageTimeoutMs: 120000,

		debug: false
	},

	start () {
		this.playing = false;
		this.idleIndex = 0;
		this.hiddenActive = false;

		this.graceTimer = null;
		this.rotationTimer = null;
		this.pollTimer = null;
		this.hiddenTimer = null;
		this.switchTimer = null;
		this.lastSwitch = 0;

		if (this.config.pollMs > 0) {
			this.pollTimer = setInterval(
				() => this.poll(),
				this.config.pollMs
			);
		}

		this.startRotation(true);
		Log.info(`${this.name} gestartet`);
	},

	// Unsichtbares Modul -- es steuert nur.
	getDom () {
		return document.createElement("div");
	},

	log (msg) {
		if (this.config.debug) Log.info(`${this.name}: ${msg}`);
	},

	// --- Zustand des Nachbarmoduls auslesen ---------------------------

	/**
	 * @returns {boolean|null} true bei Wiedergabe, false bei Stille,
	 *                         null wenn der Zustand unklar ist
	 *                         (Modul fehlt, onReconnecting, onError).
	 */
	readPlayingState () {
		const mods = (typeof MM !== "undefined" && MM.getModules)
			? MM.getModules()
			: [];
		const spotify = mods.find((m) => m.name === this.config.spotifyModule);

		if (!spotify) {
			this.log(`${this.config.spotifyModule} nicht gefunden`);
			return null;
		}
		if (typeof spotify.lastStatus !== "string") return null;

		// isPlaying / isPlayingHidden -> laeuft
		// isEmpty   / isEmptyHidden   -> still
		// onReconnecting / onError    -> unklar, Zustand halten
		if (spotify.lastStatus.startsWith("isPlaying")) return true;
		if (spotify.lastStatus.startsWith("isEmpty")) return false;
		return null;
	},

	poll () {
		if (this.hiddenActive) return;

		const state = this.readPlayingState();
		if (state === null) return;

		if (state) {
			if (this.graceTimer) {
				this.log("Wiedergabe zurueck -- Karenzzeit verworfen");
				this.clearGrace();
			}
			this.showSpotify();
			return;
		}

		// Keine Wiedergabe
		if (!this.playing) return;
		if (this.graceTimer) return;

		this.log(`pausiert -- zurueck in ${this.config.graceMs} ms`);
		this.graceTimer = setTimeout(() => {
			this.graceTimer = null;
			this.showIdle();
		}, this.config.graceMs);
	},

	// --- Leerlaufrotation ---------------------------------------------

	stopRotation () {
		if (this.rotationTimer) {
			clearInterval(this.rotationTimer);
			this.rotationTimer = null;
		}
	},

	/**
	 * @param {boolean} jumpNow Sofort auf die aktuelle Leerlaufseite
	 *                          schalten, statt erst nach einem Intervall.
	 */
	startRotation (jumpNow) {
		this.stopRotation();

		const pages = this.config.idlePages;
		if (!Array.isArray(pages) || pages.length === 0) {
			Log.warn(`${this.name}: idlePages ist leer -- keine Rotation.`);
			return;
		}

		if (this.idleIndex >= pages.length) this.idleIndex = 0;
		if (jumpNow) this.goToPage(pages[this.idleIndex]);

		if (pages.length < 2 || this.config.idleRotationMs <= 0) return;

		this.rotationTimer = setInterval(() => {
			this.idleIndex = (this.idleIndex + 1) % pages.length;
			this.goToPage(pages[this.idleIndex]);
		}, this.config.idleRotationMs);
	},

	// --- Seitenwechsel ------------------------------------------------

	/**
	 * Sendet PAGE_SELECT, aber nie zwei Wechsel dichter als
	 * minSwitchGapMs hintereinander. Ein zu frueher zweiter Wechsel
	 * laesst Module bei MMM-pages gesperrt zurueck.
	 */
	goToPage (index) {
		// Letzte Sicherung: Solange eine versteckte Seite laeuft, wird
		// nichts gesendet. Faengt auch Timer ab, die vor dem Einblenden
		// gestartet wurden und erst danach feuern.
		if (this.hiddenActive) {
			this.log(`Seite ${index} unterdrueckt -- versteckte Seite aktiv`);
			return;
		}

		const gap = this.config.minSwitchGapMs || 0;
		const since = Date.now() - this.lastSwitch;

		if (gap > 0 && since < gap) {
			// Ein bereits wartender Wechsel wird verworfen -- es zaehlt
			// immer der zuletzt gewuenschte Zustand.
			if (this.switchTimer) clearTimeout(this.switchTimer);
			const wait = gap - since;
			this.log(`Seite ${index} in ${wait} ms (Animation laeuft noch)`);
			this.switchTimer = setTimeout(() => {
				this.switchTimer = null;
				this.emitPage(index);
			}, wait);
			return;
		}

		this.emitPage(index);
	},

	emitPage (index) {
		if (this.hiddenActive) return;
		this.lastSwitch = Date.now();
		// PAGE_SELECT loest das veraltete PAGE_CHANGED ab.
		// MMM-pages verlangt einen echten Integer, kein String.
		this.sendNotification("PAGE_SELECT", index);
		this.log(`Seite ${index}`);
	},

	clearSwitchTimer () {
		if (this.switchTimer) {
			clearTimeout(this.switchTimer);
			this.switchTimer = null;
		}
	},

	clearGrace () {
		if (this.graceTimer) {
			clearTimeout(this.graceTimer);
			this.graceTimer = null;
		}
	},

	showSpotify () {
		this.clearGrace();
		if (this.playing) return;

		this.playing = true;
		this.stopRotation();
		this.goToPage(this.config.spotifyPage);
	},

	showIdle () {
		this.clearGrace();
		if (!this.playing) return;

		this.playing = false;
		// Rotation dort fortsetzen, wo sie unterbrochen wurde.
		this.startRotation(true);
	},

	// --- Schneller Zusatzweg ueber die Notification --------------------

	// --- Versteckte Seiten ---------------------------------------------

	clearHiddenTimer () {
		if (this.hiddenTimer) {
			clearTimeout(this.hiddenTimer);
			this.hiddenTimer = null;
		}
	},

	enterHidden (pageName) {
		this.clearHiddenTimer();
		this.clearGrace();
		this.clearSwitchTimer();
		this.stopRotation();
		this.hiddenActive = true;
		this.log(`versteckte Seite "${pageName}" aktiv -- Steuerung pausiert`);

		if (this.config.hiddenPageTimeoutMs > 0) {
			this.hiddenTimer = setTimeout(() => {
				this.hiddenTimer = null;
				this.log("Zeit abgelaufen -- verstecktes Seite wird verlassen");
				this.sendNotification("LEAVE_HIDDEN_PAGE");
			}, this.config.hiddenPageTimeoutMs);
		}
	},

	leaveHidden () {
		if (!this.hiddenActive) return;
		this.clearHiddenTimer();
		this.hiddenActive = false;
		this.log("versteckte Seite verlassen -- Steuerung wieder aktiv");

		// Zustand neu bestimmen, statt blind fortzusetzen: Waehrend der
		// Pause kann die Wiedergabe gestartet oder geendet haben.
		const state = this.readPlayingState();
		if (state === true) {
			this.playing = false;
			this.showSpotify();
		} else {
			this.playing = false;
			this.startRotation(true);
		}
	},

	notificationReceived (notification, payload) {
		if (this.config.respectHiddenPages) {
			if (notification === "SHOW_HIDDEN_PAGE") {
				this.enterHidden(typeof payload === "string" ? payload : "?");
				return;
			}
			if (notification === "LEAVE_HIDDEN_PAGE") {
				this.leaveHidden();
				return;
			}
		}

		if (notification !== "NOW_PLAYING") return;
		if (!payload || typeof payload !== "object") return;

		// Reagiert nur auf den Start eines Titels, damit der Wechsel
		// ohne Wartezeit auf das naechste Polling erfolgt. Das Ende der
		// Wiedergabe uebernimmt ausschliesslich das Polling -- die
		// Flanke playerIsEmpty kommt beim Pausieren nicht.
		if (payload.playerIsEmpty === false) {
			if (this.hiddenActive) {
				this.log("Titelstart ignoriert -- versteckte Seite aktiv");
				return;
			}
			this.log(`spielt: ${payload.artist} - ${payload.name}`);
			this.showSpotify();
		}
	},

	// Bewusst kein suspend()/resume(): MagicMirror ruft suspend() auf,
	// sobald ein Modul versteckt wird -- und MMM-pages versteckt alles,
	// was keiner Seite zugeordnet ist. Dieses Modul hat keine position
	// und ist damit dauerhaft versteckt. Wuerde es bei suspend() seine
	// Timer abraeumen, blieben Rotation und Polling stehen.

	stop () {
		this.clearGrace();
		this.clearHiddenTimer();
		this.clearSwitchTimer();
		this.stopRotation();
		if (this.pollTimer) clearInterval(this.pollTimer);
	}
});