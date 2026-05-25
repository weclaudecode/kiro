# Scheduling headless kiro jobs

The cron workflows need something to fire them on a schedule. All of these work
— pick by what you already run.

## crontab (Linux/macOS, simplest)

```cron
# nightly pipeline triage at 02:00
0 2 * * *  REPO_DIR=/repos/my-project KIRO_API_KEY=... /opt/kiro-automation/cron/kiro-pipeline-triage.sh
# nightly dependency scan at 02:30
30 2 * * * REPO_DIR=/repos/my-project KIRO_API_KEY=... /opt/kiro-automation/cron/kiro-dependency-scan.sh
# weekly steering refresh, Mondays 03:00
0 3 * * 1  REPO_DIR=/repos/my-project KIRO_API_KEY=... /opt/kiro-automation/cron/kiro-steering-refresh.sh
```

cron has a minimal environment — set `KIRO_API_KEY` and `PATH` explicitly in the
crontab or source a file at the top of each script. Don't hardcode the key in a
committed crontab; read it from a `chmod 600` file.

## systemd timer (Linux, preferred for servers)

More robust than cron: logs to the journal, survives missed runs with
`Persistent=true`, and keeps env in a unit file.

```ini
# /etc/systemd/system/kiro-triage.service
[Service]
Type=oneshot
EnvironmentFile=/etc/kiro-automation.env   # KIRO_API_KEY=..., REPO_DIR=...
ExecStart=/opt/kiro-automation/cron/kiro-pipeline-triage.sh
```

```ini
# /etc/systemd/system/kiro-triage.timer
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
```

`systemctl enable --now kiro-triage.timer`. Inspect with `journalctl -u kiro-triage`.

## launchd (macOS)

Drop a `~/Library/LaunchAgents/dev.kiro.triage.plist` with a
`StartCalendarInterval` dict and `EnvironmentVariables`. `launchctl load` it.
Survives sleep better than user crontab on macOS.

## EventBridge Scheduler + t4g.nano (zero local infra)

For solo ops who don't want a machine running overnight: a `t4g.nano` (or a
small Fargate task) triggered by EventBridge Scheduler is cleaner than babysitting
crontab on a laptop. The instance pulls the repo, runs the script, posts the
digest, and stops itself. Authenticate to AWS via OIDC/instance role, never a
static key, per the `aws-security` and `secrets-handling` steering.

## Picking

| Situation | Use |
| --- | --- |
| Already on a Linux server | systemd timer |
| macOS workstation | launchd |
| Quick-and-dirty on any box | crontab |
| No always-on machine, want it managed | EventBridge + t4g.nano |
