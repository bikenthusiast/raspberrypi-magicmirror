#!/usr/bin/env bash
#
# bootstrap.sh -- installs every module listed in modules.txt
#
# Idempotent: modules already present are updated, not re-cloned.
#
# Usage:  ./scripts/bootstrap.sh [/path/to/MagicMirror]
#
# Exits non-zero when a clone, checkout or npm install fails, or when a
# patched file does not parse. Moving a module to a new pin discards local
# changes to its tracked files (package-lock.json rewritten by npm, the
# node-fetch patch, which is applied again). deploy.sh runs it after modules.txt changes.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MM_ROOT="${1:-$HOME/Projects/MagicMirror}"
MODULES_DIR="$MM_ROOT/modules"
MANIFEST="$REPO_ROOT/modules.txt"

RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

[[ -d "$MM_ROOT" ]] || {
	echo "${RED}ERROR${NC} MagicMirror not found at $MM_ROOT" >&2
	echo "      Pass the path as an argument, or install MagicMirror first." >&2
	exit 1
}

[[ -f "$MANIFEST" ]] || {
	echo "${RED}ERROR${NC} $MANIFEST not found" >&2
	exit 1
}

mkdir -p "$MODULES_DIR"

# Log directory for scripts/run-server.sh (manual runs in server mode).
# The systemd service itself logs to the journal.
mkdir -p "$MM_ROOT/logs"

# --- 1. Clone or update the third-party modules ----------------------
#
# Columns: name, url, optional pin, optional policy (follow|hold, read by
# module-updates.sh, not here), optional "# comment".
#
# A module is only fetched when its pin is not already there, and npm runs
# only when the checked-out commit changed or node_modules is missing. That
# keeps a re-run cheap enough for deploy.sh, which runs this script whenever
# modules.txt changes, and again on a rollback.

while read -r name url pin _rest; do
	[[ -z "${name:-}" || "$name" == \#* ]] && continue
	[[ "${pin:-}" == \#* ]] && pin=""

	target="$MODULES_DIR/$name"
	before=""

	if [[ -d "$target/.git" ]]; then
		before="$(git -C "$target" rev-parse HEAD)"
		if [[ -n "${pin:-}" ]] && git -C "$target" cat-file -e "$pin^{commit}" 2>/dev/null; then
			echo "==> $name"
		else
			echo "==> $name: fetching"
			git -C "$target" fetch --quiet origin
		fi
	else
		echo "==> $name: cloning"
		git clone --quiet "$url" "$target"
	fi

	if [[ -n "${pin:-}" ]]; then
		# Moving to another commit discards local changes to tracked files:
		# npm install rewrites package-lock.json in some modules, and the
		# node-fetch patch below is re-applied anyway. Without --force such a
		# change blocks the checkout ("would be overwritten").
		want="$(git -C "$target" rev-parse --verify --quiet "$pin^{commit}")" \
			|| { echo "    ${RED}ERROR${NC} $name: commit $pin not found upstream" >&2; exit 1; }
		if [[ "$(git -C "$target" rev-parse HEAD)" != "$want" ]]; then
			if [[ -n "$(git -C "$target" status --porcelain --untracked-files=no)" ]]; then
				echo "    discarding local changes: $(git -C "$target" status --porcelain --untracked-files=no | awk '{print $2}' | paste -sd ' ')"
			fi
			git -C "$target" checkout --quiet --force "$want"
		fi
		echo "    pinned to $pin"
	else
		branch="$(git -C "$target" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || echo master)"
		git -C "$target" checkout --quiet "$branch"
		git -C "$target" pull --quiet --ff-only origin "$branch" || true
		echo "    ${YELLOW}no pin${NC}, tracking $branch"
	fi

	# npm install only where dependencies are declared, and only when needed
	if [[ -f "$target/package.json" ]] && grep -q '"dependencies"' "$target/package.json"; then
		if [[ "$(git -C "$target" rev-parse HEAD)" != "$before" || ! -d "$target/node_modules" ]]; then
			echo "    npm install"
			(cd "$target" && npm install --omit=dev --silent)
		fi
	fi
done < "$MANIFEST"

# --- 2. Patch the two Fabrizz modules --------------------------------
#
# Both bundle node-fetch 2.7.0, which fails to decompress gzip response
# bodies on Node 18+. The symptom is ERR_STREAM_PREMATURE_CLOSE thrown
# at Gunzip, retried at the poll interval with no backoff -- only a
# restart clears it.
#
# Native fetch has been available since Node 18, so the polyfill is
# only needed on older installs. The ?? keeps that fallback intact.
#
# Reported upstream: github.com/Fabrizz/MMM-OnSpotify/issues/116
# Once fixed there, this section can go.

patch_fetch () {
	local file="$1" label="$2"

	[[ -f "$file" ]] || {
		echo "    ${YELLOW}skipped${NC} $label: $file not found"
		return
	}

	if grep -q 'globalThis.fetch ?? require' "$file"; then
		echo "    $label: already patched"
		return
	fi

	if ! grep -q '^const fetch = require("node-fetch");' "$file"; then
		echo "    ${YELLOW}skipped${NC} $label: import line not found, check manually"
		return
	fi

	cp "$file" "$file.orig"
	sed -i 's|^const fetch = require("node-fetch");|const fetch = globalThis.fetch ?? require("node-fetch");|' "$file"
	sed -i 's|^const Headers = fetch.Headers;|const Headers = globalThis.Headers ?? fetch.Headers;|' "$file"
	echo "    ${GREEN}patched${NC} $label (backup at $(basename "$file").orig)"
}

echo
echo "==> node-fetch patches"
patch_fetch "$MODULES_DIR/MMM-OnSpotify/utils/SpotifyFetcher.js" "MMM-OnSpotify"
patch_fetch "$MODULES_DIR/MMM-LiveLyrics/utils/LyricsFetcher.js" "MMM-LiveLyrics"

# A half-applied patch leaves `const Headers;` without an initializer,
# which surfaces as "Missing initializer in const declaration" in the
# MagicMirror log -- naming neither file nor line.
echo
echo "==> verifying patched files"
errors=0
for f in \
	"$MODULES_DIR/MMM-OnSpotify/utils/SpotifyFetcher.js" \
	"$MODULES_DIR/MMM-LiveLyrics/utils/LyricsFetcher.js"
do
	[[ -f "$f" ]] || continue
	if node --check "$f" 2>/dev/null; then
		echo "    ${GREEN}ok${NC} $(basename "$f")"
	else
		echo "    ${RED}SYNTAX ERROR${NC} $f"
		node --check "$f" 2>&1 | head -3 | sed 's/^/      /'
		errors=1
	fi
done

# --- 3. Symlink the modules kept in this repo ------------------------
#
# ln -sfn, not ln -s: if the target exists as a directory, ln -s places
# the link inside it and everything ends up one level too deep.

echo
echo "==> own modules"
for own in MMM-SpotifyPages MMM-GuestWifi; do
	src="$REPO_ROOT/modules/$own"
	if [[ -d "$src" ]]; then
		ln -sfn "$src" "$MODULES_DIR/$own"
		echo "    linked $own"
	else
		echo "    ${YELLOW}missing${NC} $own at $src"
	fi
done

# The global stylesheet: MagicMirror loads config/custom.css after all
# module styles. A custom.css that is a real file was made on the Pi by
# hand -- keep it next to the link instead of overwriting it.
echo
echo "==> stylesheet"
css_dst="$MM_ROOT/config/custom.css"
if [[ -f "$css_dst" && ! -L "$css_dst" ]]; then
	mv "$css_dst" "$css_dst.local-$(date +%F)"
	echo "    ${YELLOW}kept${NC} the previous custom.css as custom.css.local-$(date +%F)"
fi
mkdir -p "$MM_ROOT/config"
ln -sfn "$REPO_ROOT/config/custom.css" "$css_dst"
echo "    linked config/custom.css"

# The stylesheet asks for Inter; without it Chromium falls back to Roboto.
# fc-list filters itself: piping into grep -q would let an early grep exit
# kill fc-list with SIGPIPE, and pipefail would report an installed font missing.
if command -v fc-list >/dev/null && [[ -z "$(fc-list 'Inter Variable' family)" ]]; then
	echo "    ${YELLOW}font missing${NC}: sudo apt install fonts-inter-variable (docs/setup.md, section 5)"
fi

# --- 4. Summary ------------------------------------------------------

# A non-zero exit lets deploy.sh roll back instead of starting a broken module.
(( errors == 0 )) || { echo "${RED}FAILED${NC}: a patched file does not parse" >&2; exit 1; }

# deploy.sh sets this: the first-install hints below are noise in its log.
[[ "${BOOTSTRAP_NO_HINTS:-0}" == "1" ]] && { echo "${GREEN}Done.${NC}"; exit 0; }

echo
echo "${GREEN}Done.${NC} Next:"
echo "  1. Credentials:"
echo "     cp $REPO_ROOT/config/secrets.example.js $REPO_ROOT/config/secrets.js"
echo "     chmod 600 $REPO_ROOT/config/secrets.js"
echo "     nano $REPO_ROOT/config/secrets.js"
echo
echo "  2. Link the config:"
echo "     ln -sfn $REPO_ROOT/config/config.js $MM_ROOT/config/config.js"
echo
echo "  3. Generate the guest WiFi code:"
echo "     $REPO_ROOT/scripts/make-guest-qr.sh"
echo
echo "  4. Check it loads:"
echo "     node -e \"require('$MM_ROOT/config/config.js')\""
