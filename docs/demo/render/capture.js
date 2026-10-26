/* Drives the demo mirror in headless Chrome for render.sh.
 *
 * Pass 1 takes one screenshot per page at the panel's 1440 × 2560.
 * Pass 2 reloads and records the tour for the GIF:
 *   page 0 -> page 1 -> a track starts (MMM-SpotifyPages switches to
 *   page 2 by itself) -> guest Wi-Fi page.
 *
 * MMM-OnSpotify and the lyrics service need credentials, so this script
 * plays them: it sends NOW_PLAYING the way MMM-OnSpotify does and hands
 * MMM-LiveLyrics placeholder lyrics.
 *
 * Usage:  node capture.js <mirror url> <screenshot dir> <video.webm> <mock url>
 * Env:    DEMO_TOOLS  folder with node_modules/puppeteer-core
 *         CHROME      Chrome or Chromium binary (default: the usual install path)
 */

"use strict";

const path = require("node:path");
const puppeteer = require(require.resolve("puppeteer-core", { paths: [process.env.DEMO_TOOLS || __dirname] }));

const [url, screensDir, videoPath, mock] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const CHROME = process.env.CHROME || {
	darwin: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
	linux: "/usr/bin/chromium"
}[process.platform];

// Colours MMM-OnSpotify would extract from the cover art
const COVER_COLOURS = {
	"--ONSP-VIBRANT-VIBRANT": "#4f7a3a", "--ONSP-VIBRANT-DARKVIBRANT": "#24401c",
	"--ONSP-VIBRANT-LIGHTVIBRANT": "#a9cf8a", "--ONSP-VIBRANT-MUTED": "#5d6b4f",
	"--ONSP-VIBRANT-DARKMUTED": "#2c3326", "--ONSP-VIBRANT-LIGHTMUTED": "#c9d6b8",
	"--ONSP-VIBRANT-DOMINANTBRIGHT": "#dfe8d2", "--ONSP-VIBRANT-DOMINANTDARK": "#1d2a14"
};

// The track from the README credits: Josh Woodward, CC BY 4.0
// (https://www.joshwoodward.com/). Its lyrics are not reproduced here --
// the mirror fetches them live; the demo shows placeholder lines.
const TRACK = {
	name: "I'll Be Right Behind You, Josephine",
	artist: "Josh Woodward"
};

const LYRICS = [
	"Hier laufen die Lyrics zum Song,",
	"Zeile für Zeile, groß und fett,",
	"damit man sie auch vom Flur aus liest.",
	"",
	"Diese Zeilen sind nur Demotext.",
	"Der echte Spiegel holt sie live",
	"für den Song, der gerade läuft."
].join("\n");

async function send (page, notification, payload) {
	await page.evaluate((n, p) => MM.getModules().find((m) => m.name === "clock").sendNotification(n, p), notification, payload);
}

async function warmUp (page) {
	await page.goto(url, { waitUntil: "domcontentloaded" });
	await page.waitForFunction(() => typeof MM !== "undefined" && MM.getModules().length > 0, { timeout: 60000 });
	// Before MMM-LiveLyrics decides there is no MMM-OnSpotify
	await send(page, "ONSPOTIFY_NOTICE", { version: "4.0.0", directColorData: true });
	await page.waitForFunction(() => document.querySelector(".MMM-MVG table")
		&& document.querySelector(".gcal-mirror-today")
		&& document.querySelector(".MMM-OpenWeatherMapForecast .current.temperature")
		&& document.querySelector(".newsfeed .newsfeed-title"), { timeout: 90000 });
	await page.evaluate(() => document.fonts.ready);
	// A visit to page 1 settles modules that were mid-fade at start-up
	await send(page, "PAGE_CHANGED", 1);
	await sleep(1500);
	await send(page, "PAGE_CHANGED", 0);
	await sleep(2000);
	await page.waitForFunction(() => document.querySelectorAll(".MMM-RAIN-MAP .leaflet-tile-loaded").length > 6, { timeout: 30000 })
		.catch(() => console.log("rain map tiles not loaded -- continuing"));
	await sleep(1500);
}

async function startPlayback (page) {
	await page.evaluate(async (cover, colours, lyrics, song) => {
		for (const [k, v] of Object.entries(colours)) document.documentElement.style.setProperty(k, v);
		const lily = MM.getModules().find((m) => m.name === "MMM-LiveLyrics");
		// Its helper would answer "no lyrics" for the demo token; keep only ours
		const original = lily.socketNotificationReceived.bind(lily);
		lily.socketNotificationReceived = (n, p) => (n === "LYRICS" && !(p && p.demo) ? undefined : original(n, p));
		const track = { playerIsEmpty: false, isPlaying: true, uri: "spotify:track:demo", name: song.name, artist: song.artist, artists: song.artist, image: cover };
		MM.getModules().find((m) => m.name === "clock").sendNotification("NOW_PLAYING", track);
		await new Promise((r) => setTimeout(r, 400));
		lily.upstreamNotFound = false;
		lily.onSpotifyVersionMismatch = null;
		lily.socketNotificationReceived("LYRICS", { demo: true, uri: track.uri, lyrics });
	}, `${mock}/cover.svg`, COVER_COLOURS, LYRICS, TRACK);
}

async function main () {
	const browser = await puppeteer.launch({
		executablePath: CHROME,
		headless: true,
		defaultViewport: { width: 1440, height: 2560, deviceScaleFactor: 1 },
		args: ["--hide-scrollbars", "--force-color-profile=srgb"]
	});
	try {
		const page = await browser.newPage();
		page.on("pageerror", (e) => console.log(`page error: ${e.message}`));
		const shot = (name) => page.screenshot({ path: path.join(screensDir, name) }).then(() => console.log(`  ${name}`));

		console.log("pass 1: screenshots");
		await warmUp(page);
		await shot("page0-calendar.png");
		await send(page, "PAGE_CHANGED", 1);
		await page.waitForFunction(() => [...document.querySelectorAll(".MMM-Globe img")].some((i) => i.complete && i.naturalWidth > 0), { timeout: 30000 })
			.catch(() => console.log("globe image not loaded -- continuing"));
		await sleep(2000);
		await shot("page1-globe.png");
		await startPlayback(page);
		await sleep(3500);
		await shot("page2-spotify.png");
		await send(page, "SHOW_HIDDEN_PAGE", "gast");
		await sleep(2500);
		await shot("page-guest.png");

		console.log("pass 2: tour");
		await warmUp(page);
		const recorder = await page.screencast({ path: videoPath, scale: 0.3125 });
		await sleep(5500);  // the calendar page is the one with the most to read
		await send(page, "PAGE_CHANGED", 1);
		await sleep(3500);
		await startPlayback(page);
		await sleep(5000);
		await send(page, "SHOW_HIDDEN_PAGE", "gast");
		await sleep(3500);
		await recorder.stop();
		console.log(`  ${path.basename(videoPath)}`);
	} finally {
		await browser.close();
	}
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
