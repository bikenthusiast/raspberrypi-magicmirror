/* Demo backend for render.sh: stands in for everything that needs a secret.
 *
 *   /owm          OpenWeatherMap One Call 3.0 (MOCK_RAIN=1: raining now, so
 *                 MMM-RAIN-MAP shows up)
 *   /<name>.ics   the four calendars of config.js, from demo-calendar.ics
 *                 (CATEGORIES picks the feed; times relative to now, see there)
 *   /news.rss     a neutral news feed
 *   /cover.svg    cover art for the now-playing card
 *
 * Usage:  node mock-backend.js [port]      (default 8099)
 */

"use strict";

const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const PORT = Number(process.argv[2] || 8099);
const CALENDAR = path.join(__dirname, "demo-calendar.ics");
const H = 3600, D = 86400;

function owm () {
	const now = Math.floor(Date.now() / 1000);
	const w = (id, icon, description) => [{ id, main: "", description, icon }];
	const hourly = Array.from({ length: 48 }, (_, i) => ({
		dt: now + i * H,
		temp: 12 - Math.abs(6 - (i % 24) / 2) + (i % 3),
		feels_like: 10,
		pop: i < 3 ? 0.8 : 0.1,
		wind_speed: 2 + (i % 4),
		wind_deg: 220,
		weather: i < 3 ? w(501, "10d", "mäßiger Regen") : w(803, "04d", "Überwiegend bewölkt")
	}));
	const daily = Array.from({ length: 8 }, (_, i) => ({
		dt: now + i * D,
		temp: { min: 6 + (i % 3), max: 13 + (i % 4) },
		pop: i === 0 ? 0.8 : 0.1,
		rain: i === 0 ? 4.1 : undefined,
		wind_speed: 3 + (i % 3),
		wind_deg: 240,
		weather: i === 0 ? w(501, "10d", "mäßiger Regen") : i === 3 ? w(800, "01d", "klarer Himmel") : w(802, "03d", "Mäßig bewölkt")
	}));
	const current = process.env.MOCK_RAIN
		? w(501, "10d", "mäßiger Regen")
		: w(803, "04d", "Überwiegend bewölkt");
	return {
		lat: 48.14, lon: 11.56, timezone: "Europe/Berlin",
		current: { dt: now, temp: 12.4, feels_like: 10.8, wind_speed: 3.1, wind_gust: 6.2, wind_deg: 230, weather: current },
		hourly, daily
	};
}

const pad = (n) => String(n).padStart(2, "0");
const stamp = (d) => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}T${pad(d.getHours())}${pad(d.getMinutes())}00`;
const day = (d) => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;

// Resolves the relative times of demo-calendar.ics:
//   {now+90m}      now + 90 minutes, rounded up to the quarter hour; kept
//                  within today so the today panel always has it
//   {day+2 09:00}  local date and time
//   {day+13}       date only, for DTSTART;VALUE=DATE
function resolve (token, property) {
	let m = token.match(/^now\+(\d+)m$/);
	if (m) {
		const d = new Date(Date.now() + Number(m[1]) * 60000);
		d.setMinutes(Math.ceil(d.getMinutes() / 15) * 15, 0, 0);
		const limit = new Date();
		limit.setHours(23, property === "DTEND" ? 59 : 30, 0, 0);
		return stamp(d < limit ? d : limit);
	}
	m = token.match(/^day\+(\d+)(?: (\d\d):(\d\d))?$/);
	if (m) {
		const d = new Date();
		d.setDate(d.getDate() + Number(m[1]));
		if (m[2] === undefined) return day(d);
		d.setHours(Number(m[2]), Number(m[3]), 0, 0);
		return stamp(d);
	}
	throw new Error(`demo-calendar.ics: unknown time {${token}}`);
}

// One feed per CATEGORIES value, read fresh on every request
function ics (feed) {
	const events = fs.readFileSync(CALENDAR, "utf8").split(/BEGIN:VEVENT\r?\n/).slice(1)
		.map((block) => block.split(/\r?\nEND:VEVENT/)[0].split(/\r?\n/))
		.filter((lines) => lines.includes(`CATEGORIES:${feed}`));
	if (events.length === 0) return null;
	const out = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//raspberrypi-magicmirror//demo//DE", `X-WR-CALNAME:${feed}`];
	events.forEach((lines, i) => {
		out.push("BEGIN:VEVENT", `UID:${feed}-${i}@demo`, `DTSTAMP:${stamp(new Date())}`);
		for (const line of lines) {
			const property = line.split(/[;:]/)[0];
			out.push(line.replace(/\{([^}]+)\}/g, (_, token) => resolve(token, property)));
		}
		out.push("END:VEVENT");
	});
	out.push("END:VCALENDAR");
	return out.join("\r\n");
}

function rss () {
	const items = [
		"Hier erscheinen die Schlagzeilen der eingestellten Feeds",
		"Der Newsfeed wechselt alle paar Sekunden zur nächsten Meldung",
		"Quelle und Titel stehen in config.js"
	];
	const date = new Date().toUTCString();
	return `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Nachrichten</title>${items
		.map((t, i) => `<item><title>${t}</title><guid>demo-${i}</guid><pubDate>${date}</pubDate></item>`)
		.join("")}</channel></rss>`;
}

const COVER = `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#a9cf8a"/><stop offset="1" stop-color="#24401c"/></linearGradient></defs>
<rect width="600" height="600" fill="url(#g)"/><circle cx="300" cy="320" r="150" fill="#1d2a14"/>
<circle cx="300" cy="320" r="40" fill="#a9cf8a"/></svg>`;

http.createServer((req, res) => {
	const { pathname } = new URL(req.url, `http://localhost:${PORT}`);
	const send = (type, body) => {
		res.writeHead(200, { "content-type": type, "access-control-allow-origin": "*" });
		res.end(body);
	};
	if (pathname === "/owm") return send("application/json", JSON.stringify(owm()));
	if (pathname === "/news.rss") return send("application/rss+xml; charset=utf-8", rss());
	if (pathname === "/cover.svg") return send("image/svg+xml", COVER);
	const cal = pathname.match(/^\/(\w+)\.ics$/);
	const feed = cal && ics(cal[1]);
	if (feed) return send("text/calendar; charset=utf-8", feed);
	res.writeHead(404).end();
}).listen(PORT, () => console.log(`demo backend on http://localhost:${PORT}`));
