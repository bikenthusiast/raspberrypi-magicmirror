/* Minimal MagicMirror front-end for tests -- no browser, no Electron.
 *
 * Loads the real module files (MMM-SpotifyPages from this repo, MMM-pages
 * from the MagicMirror installation) and reproduces exactly the parts of
 * MagicMirror's core they depend on:
 *
 *   - Module.register / instantiation with defaults + config
 *   - sendNotification: delivered to every other module in config order,
 *     never to the sender (MagicMirror core behaviour). Notifications sent
 *     from start() are lost, because the core only knows its module list
 *     after all modules have started (MM.modulesStarted)
 *   - hide()/show() with lock strings, as in js/main.js:
 *       hide adds the lock string and sets hidden
 *       show removes the lock string and only shows if no lock is left
 *   - MM.getModules() with withClass / exceptWithClass / enumerate
 *
 * Timers are whatever the global setTimeout/setInterval/Date are, so a test
 * can drive them with node:test's mock.timers.
 */

"use strict";

const fs = require("node:fs");

const silentLog = { log () {}, info () {}, warn () {}, error () {}, debug () {} };

function selection (list) {
	const names = (classes) => (Array.isArray(classes) ? classes : String(classes).split(" "));
	list.withClass = (classes) => selection(list.filter((m) => names(classes).includes(m.name)));
	list.exceptWithClass = (classes) => selection(list.filter((m) => !names(classes).includes(m.name)));
	list.enumerate = (fn) => { list.forEach(fn); return list; };
	return list;
}

function createMirror ({ log = silentLog } = {}) {
	const definitions = {};
	const modules = [];
	const trace = [];
	let started = false;

	const MM = {
		getModules: () => selection([...modules])
	};
	const Module = { register (name, def) { definitions[name] = def; } };

	function load (file) {
		// The module files are browser scripts that call the global
		// Module.register; run them with our stand-ins in scope.
		new Function("Module", "Log", "MM", fs.readFileSync(file, "utf8"))(Module, log, MM);
	}

	function broadcast (notification, payload, sender) {
		trace.push({ t: Date.now(), from: sender ? sender.name : "remote", notification, payload, lost: !started });
		if (!started) return;
		for (const m of modules) {
			if (m !== sender && typeof m.notificationReceived === "function") {
				m.notificationReceived(notification, payload, sender);
			}
		}
	}

	function add (name, { config = {}, position = "top_left", definition } = {}) {
		const def = definition || definitions[name] || {};
		const m = Object.create(def);
		Object.assign(m, {
			name,
			identifier: `module_${modules.length}_${name}`,
			config: { ...(def.defaults || {}), ...config },
			data: { position },
			hidden: false,
			lockStrings: [],
			sendNotification (n, p) { broadcast(n, p, m); },
			hide (speed, callback, options = {}) {
				m.hidden = true;
				if (options && options.lockString && !m.lockStrings.includes(options.lockString)) {
					m.lockStrings.push(options.lockString);
				}
				if (typeof callback === "function") callback();
			},
			show (speed, callback, options = {}) {
				if (options && options.lockString) {
					const i = m.lockStrings.indexOf(options.lockString);
					if (i !== -1) m.lockStrings.splice(i, 1);
				}
				if (m.lockStrings.length !== 0) return;
				m.hidden = false;
				if (typeof callback === "function") callback();
			}
		});
		modules.push(m);
		return m;
	}

	function start () {
		for (const m of modules) if (typeof m.start === "function") m.start();
		started = true;
		broadcast("ALL_MODULES_STARTED", undefined, null);
		broadcast("DOM_OBJECTS_CREATED", undefined, null);
	}

	const visible = () => modules.filter((m) => m.data.position && !m.hidden).map((m) => m.name);

	return { load, add, start, broadcast, visible, trace, get: (n) => modules.find((m) => m.name === n) };
}

module.exports = { createMirror };
