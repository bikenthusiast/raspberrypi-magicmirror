/* MagicMirror² configuration
 *
 * Credentials are not in this file. They are read from config/secrets.js,
 * which is git-ignored; config/secrets.example.js lists the keys.
 *
 * Reference: https://docs.magicmirror.builders/configuration/introduction.html
 */

// MagicMirror evaluates this file rather than require()-ing it, so a relative
// require("./secrets.js") has no file context to resolve against. The path is
// therefore derived from the home directory — see docs/setup.md, section 12.
const s = require(require("os").homedir() + "/Projects/raspberrypi-magicmirror/config/secrets.js");

let config = {
	address: "localhost",
	port: 8080,
	basePath: "/",
	// Loopback only: the Remote-Control API is called from scripts on the Pi itself.
	ipWhitelist: ["127.0.0.1", "::ffff:127.0.0.1", "::1"],

	useHttps: false,
	httpsPrivateKey: "",
	httpsCertificate: "",

	language: "de",
	locale: "de-DE",
	logLevel: ["INFO", "LOG", "WARN", "ERROR"], // add "DEBUG" for more output
	timeFormat: 24,
	units: "metric",

	modules: [
		// Order is kept as in the running installation: within a region, modules
		// render in list order. Page assignment happens in the MMM-pages entry.
		{
			module: "alert"
		},
		{
			module: "updatenotification",
			position: "top_bar"
		},
		{
			module: "clock",
			position: "top_left"
		},
		{
			module: "newsfeed",
			position: "bottom_bar",
			config: {
				feeds: [
					{ title: "Süddeutsche", url: "https://rss.sueddeutsche.de/rss/Alles" },
					{ title: "Tagesschau", url: "https://www.tagesschau.de/xml/rss2/" }
				],
				showSourceTitle: true,
				showPublishDate: false,
				broadcastNewsFeeds: true,
				broadcastNewsUpdates: true
			}
		},
		{
			module: "MMM-MVG",
			position: "top_left",
			header: "MVG",
			config: {
				station: s.mvgStation,
				maxEntries: 8,
				updateInterval: 30000, // 30 s
				showIcons: true,
				transportTypesToShow: {
					ubahn: true,
					sbahn: true,
					bus: true,
					regional_bus: true,
					tram: true
				},
				ignoreStations: [],
				lineFiltering: {
					active: false,
					filterType: "whitelist",
					lineNumbers: ["U1", "U3", "X50"]
				},
				timeToWalk: 0,
				showWalkingTime: false,
				showTrainDepartureTime: true,
				trainDepartureTimeFormat: "relative",
				walkingTimeFormat: "relative",
				showInterruptions: true, // interrupted rows are greyed out
				showInterruptionsDetails: false,
				countInterruptionsAsItemShown: false
			}
		},
		{
			module: "MMM-OpenWeatherMapForecast",
			position: "top_right",
			header: "Wetter",
			config: {
				apikey: s.openWeatherApiKey,
				endpoint: "https://api.openweathermap.org/data/3.0/onecall",
				latitude: s.cityLatitude,
				longitude: s.cityLongitude,
				units: "metric",
				language: "de",
				iconset: "4c",
				useAnimatedIcons: true,
				forecastLayout: "table",
				updateInterval: 10, // minutes
				label_timeFormat: "HH:MM",
				// German labels
				label_days: ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"],
				label_high: "H",
				label_low: "T",
				label_maximum: "max",
				label_ordinals: ["N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO",
					"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
			}
		},
		{
			module: "MMM-RAIN-MAP",
			position: "top_right",
			config: {
				animationSpeedMs: 800,
				colorizeTime: true,
				defaultZoomLevel: 6,
				displayTime: true,
				displayTimeline: true,
				displayClockSymbol: true,
				displayHoursBeforeRain: 0,
				extraDelayLastFrameMs: 2000,
				extraDelayCurrentFrameMs: 5000,
				invertColors: false,
				markers: [
					{ lat: s.cityLatitude, lng: s.cityLongitude, color: "red" }
				],
				mapPositions: [
					{ lat: s.cityLatitude, lng: s.cityLongitude, zoom: 10, loops: 2 }
				],
				mapUrl: "https://a.tile.openstreetmap.de/{z}/{x}/{y}.png",
				// RainViewer's free API is gone; LibreWXR is the public replacement.
				// A self-hosted instance would add: providerUrl: "http://<host>:8080"
				provider: "librewxr",
				mapHeight: "420px", // pixel values only, no percent
				mapWidth: "420px",
				maxHistoryFrames: 2,
				maxForecastFrames: 4,
				radarOpacity: 0.6,
				substituteModules: [],
				updateIntervalInSeconds: 600
			}
		},
		{
			module: "MMM-MyGCalendar",
			position: "lower_third",
			config: {
				calendars: [
					{
						name: "Personal",
						url: s.calendarUrl,
						color: "#4285F4"
					}
				],
				weekStartsOnMonday: true,
				backgroundColor: "#616161",
				// Keyword (regex) → Google Calendar colour
				colorRules: [
					{ keyword: "standup", color: "#039BE5" }, // Peacock
					{ keyword: "birthday", color: "#E91E63" }, // Pink
					{ keyword: "gym|workout", color: "#F4511E" }, // Tangerine
					{ keyword: "holiday", color: "#0B8043" }, // Basil
					{ keyword: "flight|travel", color: "#F6BF26" } // Banana
				]
			}
		},
		{
			module: "MMM-GuestWifi",
			position: "middle_center",
			header: "Gast-WLAN",
			config: { imageSize: 440 }
		},
		{
			// HTTP API used by scripts/guest-page.sh
			module: "MMM-Remote-Control",
			config: {
				apiKey: s.remoteApiKey,
				showModuleApiMenu: true,
				secureEndpoints: true
			}
		},
		{
			module: "MMM-Globe",
			position: "lower_third",
			config: {
				style: "centralAmericaDiscNat",
				// The module's built-in EUMETSAT URLs are dead; NOAA GOES-16 full disk instead.
				ownImagePath: "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/FD/GEOCOLOR/1808x1808.jpg",
				imageSize: 600,
				updateInterval: 10 * 60 * 1000 // 10 min
			}
		},
		{
			// Drives MMM-pages from the Spotify playback state — see docs/mmm-spotifypages.md
			module: "MMM-SpotifyPages",
			config: {
				spotifyPage: 2,
				idlePages: [0, 1],
				idleRotationMs: 300000, // 5 min
				hiddenPageTimeoutMs: 60000, // guest page closes itself after 1 min
				debug: false
			}
		},
		{
			module: "MMM-pages",
			config: {
				timings: { default: 0 }, // own rotation off; MMM-SpotifyPages switches
				modules: [
					["MMM-MVG", "MMM-MyGCalendar", "MMM-OpenWeatherMapForecast", "MMM-RAIN-MAP", "newsfeed"], // 0 idle
					["MMM-MVG", "MMM-Globe", "MMM-OpenWeatherMapForecast", "MMM-RAIN-MAP", "newsfeed"], // 1 idle
					["MMM-MVG", "MMM-LiveLyrics", "MMM-OpenWeatherMapForecast"] // 2 now playing
				],
				fixed: ["clock", "alert", "updatenotification"],
				hiddenPages: { gast: ["MMM-GuestWifi"] }
			}
		},
		{
			module: "MMM-OnSpotify",
			position: "top_left",
			config: {
				clientID: s.spotifyClientId,
				clientSecret: s.spotifyClientSecret,
				accessToken: s.spotifyAccessToken,
				refreshToken: s.spotifyRefreshToken,
				// Poll intervals in seconds, raised to stay clear of Spotify rate limits
				isPlaying: 5,
				isEmpty: 10,
				isPlayingHidden: 10,
				isEmptyHidden: 30,
				onReconnecting: 4,
				onError: 8
			}
		},
		{
			module: "MMM-LiveLyrics",
			position: "fullscreen_below", // required by the module
			config: {
				accessToken: s.geniusAccessToken,
				lyricsFillType: "fullCalcTopModules",
				lyricsStyleTheme: "dynamicblobsFull",
				updateTopModulesCalcOnData: true,
				showConnectionQrOnLoad: false
			}
		}
	]
};

/*************** DO NOT EDIT THE LINE BELOW ***************/
if (typeof module !== "undefined") { module.exports = config; }
