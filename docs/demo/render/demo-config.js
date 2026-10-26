/* Builds a demo config.js for render.sh from the repo's config/config.js.
 *
 * Same modules, positions and pages; secrets.js is replaced by values that
 * point at mock-backend.js. Dropped: MMM-OnSpotify and MMM-Remote-Control,
 * which need real credentials -- capture.mjs plays their part.
 *
 * Usage:  node demo-config.js <repo config.js> <out config.js> <mock url> <port>
 */

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const [repoConfig, outFile, mock, port] = process.argv.slice(2);

const secrets = {
	mvgStation: "Hauptbahnhof",  // public stop, live departures
	openWeatherApiKey: "demo",
	cityLatitude: 48.1402,
	cityLongitude: 11.5601,
	calendarUrlpersonal: `${mock}/personal.ics`,
	calenderUrlclaude: `${mock}/claude.ics`,
	calendarUrlSport: `${mock}/sport.ics`,
	calendarUrlCulture: `${mock}/kultur.ics`,
	remoteApiKey: "demo",
	spotifyClientId: "demo", spotifyClientSecret: "demo",
	spotifyAccessToken: "demo", spotifyRefreshToken: "demo",
	geniusAccessToken: "demo"
};

const source = fs.readFileSync(repoConfig, "utf8");
if (!/^const s = require\(.*$/m.test(source)) {
	throw new Error("config.js: the secrets require line has changed -- update demo-config.js");
}
const tmp = path.join(path.dirname(outFile), ".demo-config.tmp.js");
fs.writeFileSync(tmp, source.replace(/^const s = require\(.*$/m, `const s = ${JSON.stringify(secrets)};`));
const config = require(tmp);
fs.unlinkSync(tmp);

config.port = Number(port);
// Inter from Google Fonts in front of the real stylesheet: a dev machine
// rarely has fonts-inter-variable installed.
config.customCss = "config/demo.css";
config.modules = config.modules.filter((m) => !["MMM-OnSpotify", "MMM-Remote-Control"].includes(m.module));
for (const m of config.modules) {
	if (m.module === "MMM-OpenWeatherMapForecast") m.config.endpoint = `${mock}/owm`;
	if (m.module === "newsfeed") m.config.feeds = [{ title: "Nachrichten", url: `${mock}/news.rss` }];
}

fs.writeFileSync(outFile, `let config = ${JSON.stringify(config, null, "\t")};\nif (typeof module !== "undefined") { module.exports = config; }\n`);
console.log(`demo config: ${config.modules.length} modules on port ${config.port}`);
