/* Hidden page race tests: real MMM-SpotifyPages + real MMM-pages.
 *
 *   node --test tests/js/*.test.js
 *
 * MMM-pages is third-party and not in this repo. The test looks for it in
 * the MagicMirror installation next to this repo, or wherever MMM_PAGES
 * points:
 *
 *   MMM_PAGES=~/Projects/MagicMirror/modules/MMM-pages/MMM-pages.js node --test tests/js/*.test.js
 *
 * Without it the tests are skipped, not failed.
 */

"use strict";

const { test, mock } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

const { createMirror } = require("./harness");

const REPO = path.resolve(__dirname, "..", "..");
const SPOTIFY_PAGES = path.join(REPO, "modules", "MMM-SpotifyPages", "MMM-SpotifyPages.js");
const MMM_PAGES = process.env.MMM_PAGES
	|| path.join(os.homedir(), "Projects", "MagicMirror", "modules", "MMM-pages", "MMM-pages.js");
const skip = fs.existsSync(MMM_PAGES) ? false : `MMM-pages not found at ${MMM_PAGES}`;

// Same structure as config/config.js, reduced to what matters here.
const PAGES = {
	timings: { default: 0 },
	modules: [
		["MMM-MyGCalendar"],   // 0 idle
		["MMM-Globe"],         // 1 idle
		["MMM-LiveLyrics"]     // 2 now playing
	],
	fixed: ["clock"],
	hiddenPages: { gast: ["MMM-GuestWifi"] }
};
const SPOTIFY = { spotifyPage: 2, idlePages: [0, 1], idleRotationMs: 300000, hiddenPageTimeoutMs: 60000 };

// Advance the clock in small steps. mock.timers.tick() runs every due timer
// with Date.now() already at the end of the tick, so one big tick would
// squash the very timing this test is about.
function advance (ms) {
	for (let left = ms; left > 0; left -= 50) mock.timers.tick(Math.min(50, left));
}

function setup ({ playing = false } = {}) {
	// Start far from 0: the controller compares Date.now() with its last
	// switch (initially 0), and the mirror has been running for a while.
	mock.timers.enable({ apis: ["setTimeout", "setInterval", "Date"], now: 1e9 });
	const mirror = createMirror();
	mirror.load(SPOTIFY_PAGES);
	mirror.load(MMM_PAGES);
	// Config order as in config/config.js: the controller comes before MMM-pages.
	for (const name of ["clock", "MMM-MyGCalendar", "MMM-Globe", "MMM-LiveLyrics", "MMM-GuestWifi"]) {
		mirror.add(name, { definition: {} });
	}
	// Stand-in for MMM-OnSpotify: the controller only reads lastStatus.
	mirror.add("MMM-OnSpotify", { definition: {}, position: undefined })
		.lastStatus = playing ? "isPlaying" : "isEmpty";
	mirror.add("MMM-SpotifyPages", { config: SPOTIFY, position: undefined });
	mirror.add("MMM-pages", { config: PAGES, position: undefined });
	mirror.start();
	advance(5000);          // let the start-up page switch settle
	return mirror;
}

// What guest-page.sh does: a notification from outside (MMM-Remote-Control).
const show = (m) => m.broadcast("SHOW_HIDDEN_PAGE", "gast", null);
const hide = (m) => m.broadcast("LEAVE_HIDDEN_PAGE", undefined, null);

for (const gap of [0, 100, 300, 600, 1500]) {
	test(`show, then hide after ${gap} ms: guest page ends up hidden`, { skip }, (t) => {
		t.after(() => mock.timers.reset());
		const mirror = setup();
		assert.deepEqual(mirror.visible(), ["clock", "MMM-MyGCalendar"]);

		show(mirror);
		advance(gap);
		hide(mirror);
		advance(5000);

		assert.deepEqual(mirror.visible(), ["clock", "MMM-MyGCalendar"]);
	});
}

for (const gap of [0, 100, 300, 600]) {
	test(`hide, then show again after ${gap} ms: only the guest page is visible`, { skip }, (t) => {
		t.after(() => mock.timers.reset());
		const mirror = setup();
		show(mirror);
		advance(3000);
		hide(mirror);
		advance(gap);
		show(mirror);
		advance(5000);

		assert.deepEqual(mirror.visible(), ["MMM-GuestWifi"]);
	});
}

test("after the automatic timeout, rotation and Spotify switching work again", { skip }, (t) => {
	t.after(() => mock.timers.reset());
	const mirror = setup();
	show(mirror);
	advance(SPOTIFY.hiddenPageTimeoutMs + 5000);

	assert.deepEqual(mirror.visible(), ["clock", "MMM-MyGCalendar"], "timeout closes the page");
	assert.equal(mirror.get("MMM-SpotifyPages").hiddenActive, false, "controller must be active again");

	// Idle rotation must continue: after one interval the second idle page is shown.
	advance(SPOTIFY.idleRotationMs + 5000);
	assert.deepEqual(mirror.visible(), ["clock", "MMM-Globe"]);
});

test("while music plays, a quick show/hide returns to the player page", { skip }, (t) => {
	t.after(() => mock.timers.reset());
	const mirror = setup({ playing: true });
	advance(6000);                                   // first poll switches to the player
	assert.deepEqual(mirror.visible(), ["clock", "MMM-LiveLyrics"]);

	show(mirror);
	advance(100);
	hide(mirror);
	advance(5000);

	assert.deepEqual(mirror.visible(), ["clock", "MMM-LiveLyrics"]);
});

test("random show/hide bursts always end in the state of the last command", { skip }, (t) => {
	t.after(() => mock.timers.reset());
	// Small deterministic PRNG, so a failure can be replayed.
	let seed = 42;
	const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);

	for (let run = 0; run < 50; run++) {
		const mirror = setup();
		let last = "hide";
		for (let i = 0; i < 6; i++) {
			last = rnd() < 0.5 ? "show" : "hide";
			(last === "show" ? show : hide)(mirror);
			advance(Math.round(rnd() * 12) * 50);    // 0..600 ms between commands
		}
		advance(5000);
		const expected = last === "show" ? ["MMM-GuestWifi"] : ["clock", "MMM-MyGCalendar"];
		assert.deepEqual(mirror.visible(), expected, `run ${run} (seed sequence), last command: ${last}`);
		mock.timers.reset();
	}
});
