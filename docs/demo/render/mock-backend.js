/* Demo backend for render.sh: stands in for everything that needs a secret.
 *
 *   /owm          OpenWeatherMap One Call 3.0 (MOCK_RAIN=1: raining now, so
 *                 MMM-RAIN-MAP shows up)
 *   /<name>.ics   the four calendars of config.js, relative to today
 *   /news.rss     a neutral news feed
 *   /cover.svg    cover art for the now-playing card
 *
 * Usage:  node mock-backend.js [port]      (default 8099)
 */

"use strict";

const http = require("node:http");

const PORT = Number(process.argv[2] || 8099);
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

function at (dayOffset, hour, minute = 0) {
	const d = new Date();
	d.setDate(d.getDate() + dayOffset);
	d.setHours(hour, minute, 0, 0);
	return d;
}

// [summary, days from today, hour (null = all day), minute, minutes long]
// Today's events sit a few hours ahead, so the today panel is never empty.
function calendars () {
	const h = new Date().getHours();
	const later = (n) => Math.min(h + n, 23);
	return {
		personal: [
			["Kaffee mit Lena", 0, later(1), 30, 60],
			["Abendessen bei Mama", 0, later(3), 0, 90],
			["Zahnarzt", 2, 9, 0, 60],
			["Wohnungsübergabe", 5, 11, 0, 60],
			["Kino", 9, 20, 0, 150],
			["Geburtstag Lena", 13, null]
		],
		claude: [
			["README aktualisieren", 0, later(1), 0, 30],
			["Standup", 1, 9, 30, 15], ["Standup", 2, 9, 30, 15], ["Standup", 3, 9, 30, 15],
			["Standup", 8, 9, 30, 15], ["Standup", 9, 9, 30, 15], ["Sprint Planning", 8, 13, 0, 90]
		],
		sport: [
			["Lauf – lang", 0, later(2), 0, 60],
			["Gym – Kraft", 1, 18, 0, 75], ["Gym – Kraft", 4, 18, 0, 75],
			["Rennrad Starnberger See", 6, 10, 0, 180], ["Gym – Kraft", 11, 18, 0, 75]
		],
		kultur: [
			["Staatsoper", 3, 19, 30, 180],
			["Pinakothek", 7, null], ["Lesung Literaturhaus", 12, 20, 0, 90]
		]
	};
}

function ics (name, events) {
	const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//raspberrypi-magicmirror//demo//DE", `X-WR-CALNAME:${name}`];
	events.forEach(([summary, off, h, m, dur], i) => {
		lines.push("BEGIN:VEVENT", `UID:${name}-${i}@demo`, `DTSTAMP:${stamp(new Date())}`, `SUMMARY:${summary}`);
		if (h === null) {
			lines.push(`DTSTART;VALUE=DATE:${day(at(off, 0))}`, `DTEND;VALUE=DATE:${day(at(off + 1, 0))}`);
		} else {
			const s = at(off, h, m);
			lines.push(`DTSTART:${stamp(s)}`, `DTEND:${stamp(new Date(s.getTime() + dur * 60000))}`);
		}
		lines.push("END:VEVENT");
	});
	lines.push("END:VCALENDAR");
	return lines.join("\r\n");
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
	const all = calendars();
	if (cal && all[cal[1]]) return send("text/calendar; charset=utf-8", ics(cal[1], all[cal[1]]));
	res.writeHead(404).end();
}).listen(PORT, () => console.log(`demo backend on http://localhost:${PORT}`));
