# 009 · CI on GitHub Actions, deployment pulled by the Pi and gated on green CI

- **Status:** Proposed
- **Date:** 2026-10-12

## Context

Changes reach the mirror by hand so far: commit on the Mac, `git pull` on the Pi, restart whatever
seems affected. Nothing checks a commit before it runs on the device, and the secret check (ADR-006)
only runs where the pre-commit hook is enabled — `--no-verify` and a fresh clone skip it.

The repository is public, so GitHub Actions minutes cost nothing. The Pi sits behind the home router
without a public address. It runs MagicMirror as a systemd **user** service and the sensor and bridge
services (`presence`, `edge-bridge`) as system services. The Witty Pi keeps it powered from 07:30 to
22:15 (ADR-005). Credentials exist only on the Pi (`config/secrets.js`, `/etc/magicmirror/*.env`).

The existing checks are worth running automatically: pytest for the edge bridge, the node:test suite for
the hidden-page race, shell scripts that have broken on quoting before.

## Decision

**CI** runs on GitHub Actions for every push and pull request (`.github/workflows/ci.yml`): gitleaks,
shellcheck, ruff and pytest, and JavaScript syntax, config loading and module tests. `main` is
protected and only accepts merges with green checks.

**CD** is pulled, not pushed: a systemd user timer on the Pi runs `scripts/deploy.sh` every 30 minutes
during operating hours. It fast-forwards to `origin/main` only if every GitHub check run for that exact
commit succeeded. It restarts only the services whose files changed and smoke-tests them. On failure it
resets to the previous commit and remembers the failed one, so it does not retry the same commit.

## Alternatives considered

| Option | Why not |
|---|---|
| Self-hosted GitHub runner on the Pi | Runs code from workflows triggered by others; GitHub advises against self-hosted runners for public repositories. It would also keep a long-lived process with GitHub credentials on the device |
| Push from Actions over SSH (port forward or Tailscale) | Needs an SSH key for the Pi as a GitHub secret and an inbound path to the home network. More attack surface than the problem warrants |
| `ansible-pull` / container images with Watchtower | Mature tools, but they bring a second configuration system or a container runtime to a single device whose services are plain systemd units |
| Keep deploying by hand | Works, but nothing stops an untested commit, and restarts depend on remembering which service a file belongs to |
| Deploy without the CI gate (`git pull` on a timer) | Any commit on main would reach the wall within 30 minutes, including one that failed CI |

## Consequences

- No inbound connection, no GitHub credentials on the Pi, no Pi credentials on GitHub. The Pi reads the
  public check-runs API anonymously (60 requests per hour; the timer needs at most 2).
- The Pi becomes a deploy target. Local edits to tracked files make `deploy.sh` skip the run
  instead of overwriting them. Development happens on the Mac or a branch.
- The mapping from changed paths to restarts lives in one function (`actions_for`) and can be checked
  with `deploy.sh --plan OLD NEW`. A new service means a new line there.
- Restarting system services needs a narrow sudoers rule for exactly those `systemctl restart` commands.
- Changes to systemd units, `modules.txt` and config templates are reported, not applied. Installing a
  unit needs root and a decision, so it stays manual.
- The smoke test checks liveness (HTTP 200, unit active), not behaviour. A module that renders wrong but
  starts cleanly still deploys; that is what the CI tests are for.
- `deploy.sh` copies itself to a temporary file before running, because a deployment can change the
  script while bash is still reading it.
