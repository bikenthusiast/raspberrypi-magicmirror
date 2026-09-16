module.exports = {
	// MMM-Remote-Control. Generate with: openssl rand -hex 16
	remoteApiKey: "",

	// FRITZ!Box -> WLAN -> guest access.
	// SSID must match what is broadcast, character for character.
	guestWifiSsid: "",
	guestWifiPass: "",
	guestWifiType: "WPA",        // "nopass" for an open network

	// Google Calendar -> settings -> private address in iCal format.
	// Contains a token granting full read access without a login.
	calendarUrl: "",

	// developer.spotify.com/dashboard
	// Redirect URI must be http://127.0.0.1:8888/callback --
	// Spotify has rejected localhost since 2025.
	spotifyClientId: "",
	spotifyClientSecret: "",
	spotifyAccessToken: "",
	spotifyRefreshToken: "",

	// genius.com/api-clients
	// Use the value from "Generate Access Token", NOT the client secret.
	geniusAccessToken: "",

	// MVG stop name, exactly as the MVG spells it.
	
	mvgStation: "",
	// openweathermap.org -> API keys (One Call 3.0)
	openWeatherApiKey: "",

	// City-level coordinates for weather, rain map and globe.
	cityLatitude: 0.0,
	cityLongitude: 0.0,
};
