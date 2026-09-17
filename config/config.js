/* Config Sample
 *
 * For more information on how you can configure this file
 * see https://docs.magicmirror.builders/configuration/introduction.html
 * and https://docs.magicmirror.builders/modules/configuration.html
 *
 * You can use environment variables using a `config.js.template` file instead of `config.js`
 * which will be converted to `config.js` while starting. For more information
 * see https://docs.magicmirror.builders/configuration/introduction.html#enviromnent-variables
 */
const s = require(require("os").homedir() + "/Projects/raspberrypi-magicmirror/config/secrets.js");
let config = {
	address: "localhost",	// Address to listen on, can be:
							// - "localhost", "127.0.0.1", "::1" to listen on loopback interface
							// - another specific IPv4/6 to listen on a specific interface
							// - "0.0.0.0", "::" to listen on any interface
							// Default, when address config is left out or empty, is "localhost"
	port: 8080,
	basePath: "/",	// The URL path where MagicMirror² is hosted. If you are using a Reverse proxy
									// you must set the sub path here. basePath must end with a /
	ipWhitelist: ["127.0.0.1", "::ffff:127.0.0.1", "::1"],	// Set [] to allow all IP addresses
									// or add a specific IPv4 of 192.168.1.5 :
									// ["127.0.0.1", "::ffff:127.0.0.1", "::1", "::ffff:192.168.1.5"],
									// or IPv4 range of 192.168.3.0 --> 192.168.3.15 use CIDR format :
									// ["127.0.0.1", "::ffff:127.0.0.1", "::1", "::ffff:192.168.3.0/28"],

	useHttps: false,			// Support HTTPS or not, default "false" will use HTTP
	httpsPrivateKey: "",	// HTTPS private key path, only require when useHttps is true
	httpsCertificate: "",	// HTTPS Certificate path, only require when useHttps is true

	language: "de",
	locale: "de-DE",   // this variable is provided as a consistent location
			   // it is currently only used by 3rd party modules. no MagicMirror code uses this value
			   // as we have no usage, we  have no constraints on what this field holds
			   // see https://en.wikipedia.org/wiki/Locale_(computer_software) for the possibilities

	logLevel: ["INFO", "LOG", "WARN", "ERROR"], // Add "DEBUG" for even more logging
	timeFormat: 24,
	units: "metric",

	modules: [
		{
			module: "alert",
		},
    {
        module: 'MMM-page-indicator',
        disabled: true,
        position: 'top_bar',
        config: {
            		activeBright: true,
        		}
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
        station: s.mvgStation, // Station name
        maxEntries: 8,             // 10 items on screen
        updateInterval: 30000,      // 60 s
        showIcons: true,            // Show transport type icon
        transportTypesToShow: {
            "ubahn": true,            // show ubahn route
            "sbahn": true,            // show sbahn route
            "bus": true,              // show bus route
            "regional_bus": true,     // show regional bus route
            "tram": true              // show tram route
        },
        ignoreStations: [],         // lines with destination to which should not be shown
        lineFiltering: {
            "active": false, 			// set this to active if filtering should be used
            "filterType": "whitelist", 	// whitelist = only specified lines will be displayed, blacklist = all lines except specified lines will be displayed
            "lineNumbers": ["U1", "U3", "X50"] // lines that should be on the white-/blacklist
        },
        timeToWalk: 0,             // 10 min walking time to station. Default is 0
        showWalkingTime: false,     // if the walking time should be included and the starting time is displayed
        showTrainDepartureTime: true,             // show tran departure time
        trainDepartureTimeFormat: "relative",     // format of the train departure time
        walkingTimeFormat: "relative",            // format of the walking time
        showInterruptions: true,				    // show interruptions as gray-out rows
        showInterruptionsDetails: false,		    // show details of interruptions in next line
        countInterruptionsAsItemShown: false,	    // count interruptions details lines as a line shown
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
        updateInterval: 10,
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
        provider: "librewxr",
        // For a self-hosted LibreWXR instance, use:
        // provider: "librewxr",
        // providerUrl: "http://192.168.1.20:8080",
        mapHeight: "420px", // must be a pixel value (no percent)
        mapWidth: "420px", // must be a pixel value (no percent)
        maxHistoryFrames: 2,
        maxForecastFrames: 4,
        radarOpacity: 0.6,
        substituteModules: [],
        updateIntervalInSeconds: 600,
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
	backgroundColor: `#616161`,
    colorRules: [
      { keyword: "standup",        color: "#039BE5" }, // Peacock
      { keyword: "birthday",       color: "#E91E63" }, // Pink
      { keyword: "gym|workout",    color: "#F4511E" }, // Tangerine
      { keyword: "holiday",        color: "#0B8043" }, // Basil
      { keyword: "flight|travel",  color: "#F6BF26" }, // Banana
    ]
  }
},
{
    module: "MMM-GuestWifi",
    position: "middle_center",
    header: "Gast-WLAN",
    config: { imageSize: 440 }
},

//Remotesteuerung Anzeige
{
	module: "MMM-Remote-Control",

	config: {
				apiKey: s.remoteApiKey,
				showModuleApiMenu: true,
				secureEndpoints: true
			}
},
	{
		module: 'MMM-Globe',
		position: 'lower_third',	// This can be any of the regions. Best results in lower_third
		config: {
        style: "centralAmericaDiscNat",
        ownImagePath: "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/FD/GEOCOLOR/1808x1808.jpg",
        imageSize: 600,
        updateInterval: 10 * 60 * 1000
				}
	},
  {
	module: "MMM-SpotifyPages",
	config: {
		spotifyPage: 2,
		idlePages: [0, 1],
		idleRotationMs: 300000,
		hiddenPageTimeoutMs: 60000,
		debug: true
	}
},
	  {
	module: "MMM-pages",
	config: {
		timings: { default: 0},
		modules: [
	["MMM-MVG","MMM-MyGCalendar", "MMM-OpenWeatherMapForecast","MMM-RAIN-MAP", "newsfeed"],   // 0
	["MMM-MVG",       "MMM-Globe","MMM-OpenWeatherMapForecast","MMM-RAIN-MAP", "newsfeed"],         // 1
	["MMM-MVG", "MMM-LiveLyrics","MMM-OpenWeatherMapForecast"]     // 2
		],
		fixed: [
			"clock","alert", "updatenotification",
		],
		hiddenPages: { gast: ["MMM-GuestWifi"] }
	}
},
{
    /* Don't share your credentials! */
    module: "MMM-OnSpotify",
    position: 'top_left', /* bottom_left, bottom_center */
    config: {
       clientID: s.spotifyClientId,
        clientSecret: s.spotifyClientSecret,
        accessToken: s.spotifyAccessToken,
        refreshToken:s.spotifyRefreshToken,
        
        /* Add here other configuration options */
        isPlaying: 5,
        isEmpty: 10,
        isPlayingHidden: 10,
        isEmptyHidden: 30,
        onReconnecting: 4,
        onError: 8
    },
},
{  
  // This is the base config. See more config options below
	module: "MMM-LiveLyrics",
	position: "fullscreen_below", // Do not change position
	config: {
		accessToken: s.geniusAccessToken, // Paste here your token
    lyricsFillType: "fullCalcTopModules",
    lyricsStyleTheme: "dynamicblobsFull",
    updateTopModulesCalcOnData: true,
    showConnectionQrOnLoad: false,
    
	}
}
]
};

/*************** DO NOT EDIT THE LINE BELOW ***************/
if (typeof module !== "undefined") { module.exports = config; }
