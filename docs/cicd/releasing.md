# Releasing

How versions are numbered and how a release is cut. The pipeline that carries every commit to the Pi
is in [README.md](README.md); a release is a deliberate marker on top of it.

## Version policy

Semantic Versioning, `vMAJOR.MINOR.PATCH`, applied to what a person operating the mirror has to do:

| Bump | When | Example |
|---|---|---|
| **Major** | installation, wiring or operation changes; an upgrade needs steps | new sensor on a new UART, deploy model changes (2.0.0) |
| **Minor** | a new feature that works after `git pull` and the automatic restart | trained gesture model replaces the rule |
| **Patch** | a fix, no new behaviour | a race in the page controller |

The first tag was `v1.0`; from 2.0.0 on, tags carry all three parts.

Every major version comes with an upgrade guide (`docs/upgrading-to-N.0.md`). Every version comes with
a `CHANGELOG.md` entry. Documentation-only changes need neither a tag nor a changelog line.

## Release checklist

Copy into the release PR and tick off.

### Before the release candidate

- [ ] `CHANGELOG.md`: entries under the new version, *Known limitations* honest, date still `YYYY-MM-DD`
- [ ] Major only: upgrade guide written and followed once on a real 1.x installation (or a fresh SD card)
- [ ] ADRs for the decisions in this version exist and their status is current
- [ ] `docs/roadmap.md`, `docs/hardware.md`, `README.md` match what is released
- [ ] Release PR merged into `main`, all CI checks green

### Release candidate

```bash
git switch main && git pull --ff-only
git tag -a vX.Y.Z-rc.1 -m "X.Y.Z release candidate 1"
git push origin vX.Y.Z-rc.1
```

- [ ] The Pi runs the candidate (deploy timer or `git pull`) for at least **3 days** of normal use
- [ ] At least one deployment went through the timer, and one rollback was exercised (major only)
- [ ] Journal clean: `journalctl --user -u deploy`, `journalctl -u presence -u gesture -u edge-bridge`,
      `journalctl -t magicmirror -p err`
- [ ] Problems found → fix on a branch, merge, tag `rc.2`, start the clock again

### Release

The release tag goes on **the same commit** as the last candidate — nothing is changed in between.

```bash
# CHANGELOG.md: replace YYYY-MM-DD with today's date in a last PR, then:
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "MagicMirror X.Y.Z"
git push origin vX.Y.Z
```

The date commit is the only exception to "same commit": it changes no code.

- [ ] GitHub → *Releases → Draft a new release* from the tag. Body: the changelog section, link to the
      upgrade guide, known limitations
- [ ] `[Unreleased]` link in `CHANGELOG.md` points to `compare/vX.Y.Z...HEAD`

### After the release

- [ ] Watch the journal for a few days
- [ ] Roadmap: next version and its scope
