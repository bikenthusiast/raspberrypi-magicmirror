#!/usr/bin/env bash
#
# module-updates.sh -- which pinned modules have newer upstream commits
#
# Reads modules.txt, asks each upstream for the head of its default branch
# (git ls-remote, no clone) and compares it with the pin.
#
#   follow  the pin may move: with --write it is set to upstream's head
#   hold    reported as "held back" only, never changed (own fork, patched
#           by bootstrap.sh, upstream known to break this setup)
#
# For GitHub repositories the report also lists the new commits and whether
# package.json changed (= npm install on the Pi pulls different dependencies).
# GH_TOKEN, if set, raises the GitHub API limit; without it 60 requests/hour.
#
# Usage:
#   scripts/module-updates.sh                  report only, change nothing
#   scripts/module-updates.sh --write          move the follow pins in modules.txt
#   scripts/module-updates.sh --report FILE    also write a Markdown summary (PR body)
#
# Run weekly by .github/workflows/module-updates.yml, which opens a pull
# request with the result. Background: docs/updates.md, ADR-011.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${MODULES_MANIFEST:-$REPO_ROOT/modules.txt}"
MAX_COMMITS=10

write=0
report=""
while (( $# )); do
	case "$1" in
		--write)  write=1 ;;
		--report) report="${2:?--report needs a file}"; shift ;;
		*)        echo "Usage: $0 [--write] [--report FILE]" >&2; exit 2 ;;
	esac
	shift
done

# --- GitHub compare: commits and changed files between two commits ------------
#
# Prints Markdown lines; empty when the repository is not on GitHub or the API
# is not reachable (the report then only has the compare link).
compare_md () {
	local url="$1" base="$2" head="$3" slug json
	[[ "$url" =~ ^https://github\.com/([^/]+/[^/.]+)(\.git)?/?$ ]] || return 0
	slug="${BASH_REMATCH[1]}"
	local auth=()
	[[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GH_TOKEN")
	json="$(curl -fsS --max-time 20 "${auth[@]}" -H "Accept: application/vnd.github+json" \
		"https://api.github.com/repos/$slug/compare/$base...$head" 2>/dev/null)" || return 0
	MAX="$MAX_COMMITS" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
mx = int(os.environ["MAX"])
status, n = d.get("status"), d.get("total_commits", 0)
if status != "ahead":
    print(f"  - **{status}**: the pin is not an ancestor of upstream (history rewritten?) -- check before merging")
commits = d.get("commits", [])
for c in commits[-mx:]:
    msg = c["commit"]["message"].splitlines()[0][:100]
    sha = c["sha"][:7]
    print(f"  - `{sha}` {msg}")
if n > mx:
    print(f"  - ... {n - mx} older")
files = [f["filename"] for f in d.get("files", [])]
if any(f.endswith("package.json") or f.endswith("package-lock.json") for f in files):
    print("  - :package: **dependencies changed** (package.json) -- npm install pulls new code")
' <<<"$json" || true
}

# --- main ---------------------------------------------------------------------

moved=()      # "name old new url"
held=()       # "name pin head url reason"
current=0
failed=()

while read -r name url pin policy rest; do
	[[ -z "${name:-}" || "$name" == \#* ]] && continue
	[[ "${pin:-}" == \#* ]] && pin=""
	[[ "${policy:-}" == \#* ]] && policy=""
	policy="${policy:-hold}"

	if [[ -z "$pin" ]]; then
		echo "  ?  $name: no pin in modules.txt -- pin it first"
		continue
	fi

	head="$(git ls-remote --symref "$url" HEAD 2>/dev/null | awk '$2 == "HEAD" && $1 !~ /^ref:/ {print $1; exit}')" || head=""
	if [[ -z "$head" ]]; then
		echo "  !  $name: upstream not reachable ($url)"
		failed+=("$name")
		continue
	fi

	if [[ "$head" == "$pin"* ]]; then
		current=$(( current + 1 ))
		continue
	fi

	short="${head:0:${#pin}}"
	if [[ "$policy" == "follow" ]]; then
		echo "  +  $name: $pin -> $short"
		moved+=("$name $pin $short $url")
		if (( write )); then
			sed -i -E "s|^(${name}[[:space:]]+[^[:space:]]+[[:space:]]+)${pin}([[:space:]]\|$)|\\1${short}\\2|" "$MANIFEST"
			grep -qE "^${name}[[:space:]].*[[:space:]]${short}([[:space:]]|$)" "$MANIFEST" \
				|| { echo "  !  $name: could not rewrite the pin in $MANIFEST" >&2; exit 1; }
		fi
	else
		reason="$(sed -n 's/^#[[:space:]]*//p' <<<"${rest:-}")"
		echo "  =  $name: held at $pin, upstream at $short${reason:+ ($reason)}"
		held+=("$name $pin $short $url ${reason:-}")
	fi
done < "$MANIFEST"

echo "${#moved[@]} to update, ${#held[@]} held back, $current current${failed[*]:+, unreachable: ${failed[*]}}"

if [[ -n "$report" ]]; then
	{
		echo "Weekly check of the third-party modules in \`modules.txt\` (\`scripts/module-updates.sh\`)."
		echo
		if (( ${#moved[@]} )); then
			echo "### Updated pins (\`follow\`)"
			echo
			for m in "${moved[@]}"; do
				read -r n old new u <<<"$m"
				echo "- **$n** \`$old\` → \`$new\` · [compare]($u/compare/$old...$new)"
				compare_md "$u" "$old" "$new"
			done
			echo
		fi
		if (( ${#held[@]} )); then
			echo "### Held back (\`hold\`, not changed)"
			echo
			for m in "${held[@]}"; do
				read -r n old new u why <<<"$m"
				echo "- **$n** pinned \`$old\`, upstream \`$new\`${why:+ — $why} · [compare]($u/compare/$old...$new)"
			done
			echo
		fi
		if (( ${#failed[@]} )); then
			echo "### Not reachable"
			echo
			for n in "${failed[@]}"; do echo "- $n"; done
			echo
		fi
		cat <<'EOF'
### Before merging

- Read the commits above, especially anything marked *dependencies changed* or *diverged*.
- After the merge, `deploy.sh` on the Pi runs `bootstrap.sh`, restarts MagicMirror and smoke-tests it;
  on failure it rolls back to the old pins. Check the next morning: `journalctl --user -u deploy -n 50`.
- To keep a module from moving, set it to `hold` in `modules.txt` (with a reason) and close this PR.
EOF
	} >"$report"
fi
