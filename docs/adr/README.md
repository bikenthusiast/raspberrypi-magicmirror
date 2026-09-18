# Architecture decision records

Short records of decisions that shaped the mirror: the context at the time, what was decided, and what
it costs. Format after Michael Nygard. Records are not edited after the fact; a changed decision gets a
new record that supersedes the old one.

| ADR | Decision | Status |
|---|---|---|
| [001](001-hidden-page-trigger.md) | Hidden pages are triggered by notification through MMM-Remote-Control | Accepted |
| [002](002-display-power-cec.md) | Display power via HDMI-CEC, not the Wayland compositor | Accepted |
| [003](003-presence-sensor.md) | 24 GHz mmWave radar (Waveshare HMMD) for presence detection | Accepted |
| [004](004-sensor-connection.md) | Radar on a GPIO input, UART not connected in operation | Accepted |
| [005](005-power-management.md) | Witty Pi 4 Mini for the night, CEC standby during the day | Accepted |
| [006](006-secrets-handling.md) | Credentials in a git-ignored `secrets.js`, guarded by a pre-commit hook | Accepted |

Template for new records: [`000-template.md`](000-template.md).
