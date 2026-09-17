# Logging and Log Troubleshooting

How MagicMirror logging is set up on this Pi, how to read it, and how to diagnose it
when the logs themselves mislead you.

Host: `raspberrypi-magicmirror` · Service: systemd **user** unit `magicmirror`

---

## TL;DR — reading the logs

```bash
journalctl -t magicmirror -b            # this boot only  ← use this by default
journalctl -t magicmirror -f -n 50      # follow live, with context
journalctl -t magicmirror -p err -b     # errors only
journalctl -t magicmirror --since "10 min ago"
```

`journalctl --user -u magicmirror` returns **"No journal files were found"** even though the
entries exist. Use the `-t magicmirror` identifier instead — that is what the drop-in below
sets it up for.

Remote, from a workstation:

```bash
ssh -t raspberrypi-magicmirror "journalctl -t magicmirror -f -n 50"
```

---

## Current configuration

### 1. Service unit

`~/.config/systemd/user/magicmirror.service` (unchanged, package/own original):

```ini
[Unit]
Description=MagicMirror (Electron)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
WorkingDirectory=/home/tobiask/Projects/MagicMirror
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=15
StandardOutput=append:/home/tobiask/Projects/MagicMirror/logs/magicmirror.log
StandardError=append:/home/tobiask/Projects/MagicMirror/logs/magicmirror.log

[Install]
WantedBy=default.target
```

### 2. Service drop-in — send output to the journal

`~/.config/systemd/user/magicmirror.service.d/override.conf`:

```ini
[Service]
StandardOutput=journal
StandardError=journal
SyslogIdentifier=magicmirror
```

Created with:

```bash
mkdir -p ~/.config/systemd/user/magicmirror.service.d

cat > ~/.config/systemd/user/magicmirror.service.d/override.conf << 'EOF'
[Service]
StandardOutput=journal
StandardError=journal
SyslogIdentifier=magicmirror
EOF

systemctl --user daemon-reload
systemctl --user restart magicmirror
```

### 3. journald drop-in — persistent storage

`/etc/systemd/journald.conf.d/99-persistent.conf`:

```ini
[Journal]
Storage=persistent
SystemMaxUse=100M
SystemMaxFileSize=20M
```

Created with:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d

printf '[Journal]\nStorage=persistent\nSystemMaxUse=100M\nSystemMaxFileSize=20M\n' \
  | sudo tee /etc/systemd/journald.conf.d/99-persistent.conf

sudo systemctl restart systemd-journald
sudo journalctl --flush
```

---

## Why this setup

Two independent problems had to be solved.

**1. The unit redirected all output into a single file.**
`StandardOutput=append:` sends stdout and stderr to `logs/magicmirror.log`. Two consequences:
the journal stays empty, and the file accumulates **every run since the beginning**, with no
marker between restarts. Scrolling into the middle of that file shows output from an arbitrary
past run that looks current. This caused a real misdiagnosis: two module errors were chased
that had already been fixed hours earlier, because the log predated the fix.

**2. Raspberry Pi OS forces volatile journal storage.**
The image ships `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` with
`Storage=volatile` to reduce SD-card wear. Journals then live in `/run/log/journal`, i.e. RAM,
and are lost on reboot.

Crucially, **drop-ins override the main `journald.conf`**, not the other way round. Setting
`Storage=persistent` in `journald.conf` therefore has no effect. Drop-ins are read in
lexicographic filename order and the last value wins, so the override must sort after `40-`
— hence `99-persistent.conf`. It lives in `/etc`, never in `/usr/lib`, which is package-owned
and overwritten on updates.

**Trade-off accepted:** persistent journals mean more SD-card writes. `SystemMaxUse=100M`
bounds it.

---

## Verification

```bash
# Is the service drop-in in effect?
systemctl --user show magicmirror -p StandardOutput -p StandardError
# expected: StandardOutput=journal / StandardError=journal

# Which files make up the effective journald config, and what do they set?
sudo systemd-analyze cat-config systemd/journald.conf | grep -E "^#? ?/|Storage"

# Where does the journal actually live?
sudo du -sh /var/log/journal /run/log/journal 2>/dev/null
# expected: size under /var/log/journal, 0 under /run/log/journal

# Definitive proof of persistence — only after a reboot
journalctl --list-boots        # two or more entries
```

---

## Troubleshooting playbook

| Symptom | Check | Likely cause |
|---|---|---|
| Log shows an error that is already fixed | Compare the log timestamp with the file's mtime; `ps -eo etime,cmd \| grep -i magicmirror` | Service was never restarted; the log describes a dead run |
| `No journal files were found` | `systemctl --user show magicmirror -p StandardOutput` | Output redirected to a file, or `--user` used instead of `-t magicmirror` |
| Journal empty after reboot | `sudo du -sh /var/log/journal /run/log/journal` | Volatile storage — see drop-in above |
| Config change has no effect | `sudo systemd-analyze cat-config systemd/journald.conf` | A drop-in overrides the main file |
| `No <module>.js found for module` | `find ~ -name "<Module>.js"`; check symlink with `ls -lL` | Wrong path, case mismatch, or service not restarted since the fix |
| `zsh: no matches found: /var/log/journal/*/` | — | zsh aborts on globs with no match; the directory is empty. Quote the glob or use `ls -lR` |

**Rule of thumb:** before interpreting any log line, confirm the log covers the run you care
about. `-b` restricts output to the current boot and makes this class of mistake structurally
impossible.

---

## Reverting

```bash
# Back to file logging
rm ~/.config/systemd/user/magicmirror.service.d/override.conf
systemctl --user daemon-reload && systemctl --user restart magicmirror

# Back to the Raspberry Pi OS default (volatile journal)
sudo rm /etc/systemd/journald.conf.d/99-persistent.conf
sudo systemctl restart systemd-journald
```

---

## Note on the legacy log file

`logs/magicmirror.log` is no longer written to. Before archiving or publishing anything from
that tree, check it for credentials — MagicMirror logs can contain Spotify tokens, API keys
and calendar URLs:

```bash
grep -iE "token|secret|api[_-]?key|client[_-]?secret|password|ical|webcal" logs/magicmirror.log | head
git check-ignore -v logs/ || echo "WARNING: logs/ is not ignored"
```