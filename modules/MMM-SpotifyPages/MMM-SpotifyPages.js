/* MMM-SpotifyPages
 *
 * Controls MMM-pages based on the Spotify playback status.
 *
 *   Playback running -> fixed Spotify page (player + lyrics)
 *   Playback paused   -> rotation through the idle pages
 *
 * Example layout in MMM-pages:
 *
 *   modules: [
 *     ["MMM-MVG",       "MMM-MyGCalendar"],   // 0  idle
 *     ["MMM-MVG",       "MMM-Globe"],         // 1  idle
 *     ["MMM-OnSpotify", "MMM-LiveLyrics"]     // 2  playing
 *   ]
 *
 * ---------------------------------------------------------------------
 * Why polling instead of notifications alone
 * ---------------------------------------------------------------------
 *
 * MMM-OnSpotify sends NOW_PLAYING only on two edges: a new track
 * starting (playerIsEmpty: false) and the player clearing
 * (playerIsEmpty: true). Pausing triggers neither -- Spotify only
 * clears the player after a long period of inactivity. The mirror
 * would stay on the Spotify page until then.
 *
 * The actual state is exposed on the frontend, though: MMM-OnSpotify
 * tracks it in "lastStatus" with the values isPlaying, isPlayingHidden,
 * isEmpty and isEmptyHidden. The "Hidden" suffix only says whether the
 * module is currently visible; what's evaluated is the prefix.
 *
 * This module reads that value on a regular interval. NOW_PLAYING is
 * kept as a fast secondary path so the switch happens without delay
 * when a track starts.
 *
 * ---------------------------------------------------------------------
 * Requirement in config.js
 * ---------------------------------------------------------------------
 *
 * MMM-pages: turn off its own rotation, otherwise its timer overrides
 * the selection made here.
 *
 *   timings: { default: 0 }
 *
 * MIT License
 */

Module.register("MMM-SpotifyPages", {
	defaults: {
		// Page shown while playback is running
		spotifyPage: 2,

		// Pages that rotate while idle
		idlePages: [0, 1],

		// Rotation duration while idle, in ms. 0 stops on the first
		// idle page.
		idleRotationMs: 10000,

		// Delay before switching back after playback is paused.
		// Prevents jumping on short gaps between two tracks.
		graceMs: 30000,

		// Interval of the status check in ms. 0 turns off polling --
		// then it runs purely on notifications, and pausing is not
		// detected.
		pollMs: 5000,

		// Module whose lastStatus is evaluated
		spotifyModule: "MMM-OnSpotify",

		// While a hidden page from MMM-pages is active, this module
		// stays completely out of the way -- neither rotation nor a
		// Spotify switch may hide the QR code.
		respectHiddenPages: true,

		// Minimum gap between two page switches, in ms.
		//
		// MMM-pages fades out and back in on a switch using setTimeout.
		// If a second switch arrives during that animation, the release
		// for the old page can get lost -- the modules are then left
		// locked by an MMM-pages lockString and stay permanently
		// invisible even though the page is set correctly.
		//
		// This shows up when leaving the Spotify page: the switch back
		// and the first rotation step follow closely one after another.
		minSwitchGapMs: 700,

		// Automatically switch back once a hidden page has been open
		// this long. 0 turns off the automatism, so it then stays
		// until a LEAVE_HIDDEN_PAGE.
		hiddenPageTimeoutMs: 120000,

		// Name of the MMM-pages instance. Its animationTime decides how
		// long a page transition keeps timers pending (see settle()).
		pagesModule: "MMM-pages",

		// Extra safety margin on top of MMM-pages' animationTime, in ms.
		settleMarginMs: 200,

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
		this.hiddenName = null;
		this.reassertTimer = null;

		// Until this time, MMM-pages may still fire a pending show() from
		// an earlier transition -- see settle().
		this.settledAt = 0;

		if (this.config.pollMs > 0) {
			this.pollTimer = setInterval(
				() => this.poll(),
				this.config.pollMs
			);
		}

		this.startRotation(true);
		Log.info(`${this.name} started`);
	},

	// Invisible module -- it only controls.
	getDom () {
		return document.createElement("div");
	},

	log (msg) {
		if (this.config.debug) Log.info(`${this.name}: ${msg}`);
	},

	// --- Read the neighboring module's state ---------------------------

	/**
	 * @returns {boolean|null} true when playing, false when silent,
	 *                         null when the state is unclear
	 *                         (module missing, onReconnecting, onError).
	 */
	readPlayingState () {
		const mods = (typeof MM !== "undefined" && MM.getModules)
			? MM.getModules()
			: [];
		const spotify = mods.find((m) => m.name === this.config.spotifyModule);

		if (!spotify) {
			this.log(`${this.config.spotifyModule} not found`);
			return null;
		}
		if (typeof spotify.lastStatus !== "string") return null;

		// isPlaying / isPlayingHidden -> playing
		// isEmpty   / isEmptyHidden   -> silent
		// onReconnecting / onError    -> unclear, keep current state
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
				this.log("playback resumed -- grace period discarded");
				this.clearGrace();
			}
			this.showSpotify();
			return;
		}

		// No playback
		if (!this.playing) return;
		if (this.graceTimer) return;

		this.log(`paused -- switching back in ${this.config.graceMs} ms`);
		this.graceTimer = setTimeout(() => {
			this.graceTimer = null;
			this.showIdle();
		}, this.config.graceMs);
	},

	// --- Idle rotation ---------------------------------------------

	stopRotation () {
		if (this.rotationTimer) {
			clearInterval(this.rotationTimer);
			this.rotationTimer = null;
		}
	},

	/**
	 * @param {boolean} jumpNow Switch to the current idle page
	 *                          immediately, instead of only after an
	 *                          interval.
	 */
	startRotation (jumpNow) {
		this.stopRotation();

		const pages = this.config.idlePages;
		if (!Array.isArray(pages) || pages.length === 0) {
			Log.warn(`${this.name}: idlePages is empty -- no rotation.`);
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

	// --- Transition bookkeeping -----------------------------------------

	/**
	 * Duration of one MMM-pages transition in ms.
	 *
	 * MMM-pages hides the old modules over animationTime/2 and shows the
	 * new ones with a setTimeout after animationTime/2. That timeout is
	 * never cancelled: a second transition during this window does not
	 * stop the first one from showing its modules afterwards. Whatever
	 * was meant to be hidden by the second transition comes back.
	 */
	transitionMs () {
		const mods = (typeof MM !== "undefined" && MM.getModules) ? MM.getModules() : [];
		const pages = mods.find((m) => m.name === this.config.pagesModule);
		const time = pages && pages.config && Number(pages.config.animationTime);
		return Number.isFinite(time) && time >= 0 ? time : 1000;
	},

	/**
	 * Call on every transition this module triggers or witnesses.
	 * Afterwards, settledAt is the earliest time at which no MMM-pages
	 * timer from that transition can fire any more.
	 */
	settle () {
		const until = Date.now() + this.transitionMs() + (this.config.settleMarginMs || 0);
		this.settledAt = Math.max(this.settledAt, until);
	},

	clearReassertTimer () {
		if (this.reassertTimer) {
			clearTimeout(this.reassertTimer);
			this.reassertTimer = null;
		}
	},

	// --- Page switching ------------------------------------------------

	/**
	 * Sends PAGE_SELECT, but never two switches closer together than
	 * minSwitchGapMs. A second switch that's too early leaves modules
	 * locked in MMM-pages.
	 */
	goToPage (index) {
		// Final safeguard: nothing is sent while a hidden page is
		// active. Also catches timers that were started before the
		// hidden page was shown and only fire afterward.
		if (this.hiddenActive) {
			this.log(`page ${index} suppressed -- hidden page active`);
			return;
		}

		const now = Date.now();
		const gap = this.config.minSwitchGapMs || 0;
		const wait = Math.max(gap - (now - this.lastSwitch), this.settledAt - now, 0);

		if (wait > 0) {
			// A switch that's already waiting is discarded -- the most
			// recently requested state always wins.
			if (this.switchTimer) clearTimeout(this.switchTimer);
			this.log(`page ${index} in ${wait} ms (animation still running)`);
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
		this.settle();
		// PAGE_SELECT replaces the deprecated PAGE_CHANGED.
		// MMM-pages requires an actual integer, not a string.
		this.sendNotification("PAGE_SELECT", index);
		this.log(`page ${index}`);
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
		// Resume rotation where it was interrupted.
		this.startRotation(true);
	},

	// --- Fast secondary path via the notification --------------------

	// --- Hidden pages ---------------------------------------------

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
		this.clearReassertTimer();
		this.stopRotation();
		this.hiddenActive = true;
		this.hiddenName = pageName;
		this.log(`hidden page "${pageName}" active -- control paused`);

		// The page was opened while an earlier transition (typically the
		// LEAVE of the same page a moment ago) still has a show() pending
		// in MMM-pages. That show() would put the regular page back on
		// top of the guest page. Ask MMM-pages again once it has settled;
		// its transition then hides everything that is not on this page.
		const now = Date.now();
		if (now < this.settledAt) {
			const wait = this.settledAt - now;
			this.log(`re-asserting "${pageName}" in ${wait} ms`);
			this.reassertTimer = setTimeout(() => {
				this.reassertTimer = null;
				if (!this.hiddenActive || this.hiddenName !== pageName) return;
				this.settle();
				this.sendNotification("SHOW_HIDDEN_PAGE", pageName);
			}, wait);
		}
		this.settle();

		if (this.config.hiddenPageTimeoutMs > 0) {
			this.hiddenTimer = setTimeout(() => {
				this.hiddenTimer = null;
				this.log("time elapsed -- leaving hidden page");
				this.sendNotification("LEAVE_HIDDEN_PAGE");
				// MagicMirror never delivers a notification to its own
				// sender, so this module would not see its LEAVE and
				// would stay paused forever. Leave explicitly.
				this.leaveHidden();
			}, this.config.hiddenPageTimeoutMs);
		}
	},

	leaveHidden () {
		if (!this.hiddenActive) {
			// MMM-pages animates on every LEAVE_HIDDEN_PAGE, even a
			// redundant one -- its pending show() counts all the same.
			this.settle();
			return;
		}
		this.clearHiddenTimer();
		this.clearReassertTimer();
		this.hiddenActive = false;
		this.hiddenName = null;
		this.log("hidden page left -- control active again");

		// The page switch below is held back until MMM-pages has settled
		// (goToPage waits for settledAt). If the hidden page was opened only
		// a moment ago, its pending show() fires in between -- the delayed
		// PAGE_SELECT then hides the guest page again.
		this.settle();

		// Re-determine the state instead of blindly resuming: playback
		// may have started or ended while paused.
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

		// Only reacts to a track starting, so the switch happens
		// without waiting for the next poll. The end of playback is
		// handled exclusively by polling -- the playerIsEmpty edge
		// doesn't fire on pause.
		if (payload.playerIsEmpty === false) {
			if (this.hiddenActive) {
				this.log("track start ignored -- hidden page active");
				return;
			}
			this.log(`playing: ${payload.artist} - ${payload.name}`);
			this.showSpotify();
		}
	},

	// Deliberately no suspend()/resume(): MagicMirror calls suspend()
	// as soon as a module is hidden -- and MMM-pages hides everything
	// that isn't assigned to a page. This module has no position and
	// is therefore permanently hidden. If it cleared its timers on
	// suspend(), rotation and polling would stop.

	stop () {
		this.clearGrace();
		this.clearHiddenTimer();
		this.clearSwitchTimer();
		this.clearReassertTimer();
		this.stopRotation();
		if (this.pollTimer) clearInterval(this.pollTimer);
	}
});