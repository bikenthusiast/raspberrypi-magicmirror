# 006 · Credentials in a git-ignored `secrets.js`, guarded by a pre-commit hook

- **Status:** Accepted
- **Date:** 2026-09-15

## Context

The configuration needs a private Google Calendar iCal URL (a token granting full read access without a
login), Spotify client secret and tokens, a Genius token, an OpenWeatherMap key, the Remote-Control API
key, the guest Wi-Fi password and the home location. The repository is public.

The first approach kept a sanitized `config.js.example` in Git and generated it from the real
`config.js` with a `sed` script (`sync-config.sh`). That meant two versions of every configuration
change, and a forgotten pattern in the script would have published a secret.

## Decision

- `config/config.js` is tracked in Git and contains **no** credentials. It reads them from
  `config/secrets.js`, which is git-ignored; [`config/secrets.example.js`](../../config/secrets.example.js)
  lists every key without a value.
- Derived artifacts that encode secrets are ignored too — notably `guest-wifi.png`, whose QR code
  contains the Wi-Fi password.
- A versioned pre-commit hook in [`.githooks/pre-commit`](../../.githooks/pre-commit) blocks forbidden
  file names (`secrets.js`, `.env`, keys) and common secret patterns in added lines. It is enabled once
  per clone with `git config core.hooksPath .githooks`.

## Alternatives considered

| Option | Why not |
|---|---|
| `config.js.example` + `sync-config.sh` | Two files to keep in sync; sanitizing by regex fails open |
| `config.js.template` with `${ENV}` substitution (built into MagicMirror) | Works, but every value has to be exported into the service environment, which moves the secrets into the systemd unit |
| Encrypted secrets in Git (git-crypt, sops) | More tooling than a single-device hobby project warrants |

## Consequences

- One configuration file, reviewed in full in every diff.
- MagicMirror evaluates `config.js` without a file context, so `require("./secrets.js")` fails; the
  path is derived from the home directory instead.
- The hook is a safety net, not a guarantee: it only runs where `core.hooksPath` is set, and
  `--no-verify` bypasses it. The full Git history was scanned for secrets on 2026-09-18, with no findings.
- Logs contain tokens in request URLs (the Genius token in full), so log excerpts need checking before
  they are shared.
