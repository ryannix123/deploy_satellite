# Red Hat Satellite Upgrade Guide

This guide covers upgrading Red Hat Satellite through minor versions (y-stream, e.g. 6.18 → 6.19) and applying z-stream patch updates within a version. Always use `satellite-maintain` for both — never run raw `dnf update` against Satellite packages.

> **Verified on a live 6.18.5 → 6.19.1 upgrade.** The command syntax below reflects what the current `satellite-maintain` build actually accepts, which differs from some published examples (see the notes on `--target-version` and `container-podman-login` below).

## Understanding the Version Number (X.Y.Z)

For `6.18.5`:

| Field | Example | Meaning |
|---|---|---|
| **X** | 6 | Major version |
| **Y** | 18 | Minor / **y-stream** — where new features land. 6.18 → 6.19 is a y-stream **upgrade**. |
| **Z** | 5 | **z-stream** — the maintenance counter. Bug fixes and security errata only, not features. |

The Z is an aggregation of errata: qualified Critical/Important security advisories (RHSAs) and Urgent/selected High-priority bug-fix advisories (RHBAs). So `6.18.5` means "Satellite 6.18 with five rounds of accumulated maintenance and security fixes." New functionality waits for the next y-stream. Note that Lightspeed/Insights *rule* updates flow as content the on-premises IOP consumes; they are not tied to the z-stream number.

- **z-stream update** (6.18.4 → 6.18.5): `satellite-maintain update`
- **y-stream upgrade** (6.18 → 6.19): `satellite-maintain upgrade`

## Playbook Files

| File | Purpose |
|---|---|
| `upgrade_satellite_6.19.yml` | Upgrade playbook — verifies version (N-1), pre-seeds Hammer credentials, backs up, enables the maintenance repo, self-upgrades the tooling, verifies registry login, runs the pre-check and upgrade with the correct whitelist, verifies health |

## Upgrade Path and Compatibility

- **Direct path:** 6.18 → 6.19 is a single y-stream hop. No intermediate version required.
- **N-1 policy:** the Server can only be upgraded from the immediately preceding minor version.
- **Capsule compatibility:** after the Server is on 6.19, Capsules at **6.18 and 6.17** keep working, so they can be upgraded later in their own maintenance windows.

| Current | Target | Path |
|---|---|---|
| 6.18 | 6.19 | 6.18 → 6.19 (direct) |
| 6.17 | 6.19 | 6.17 → 6.18 → 6.19 |
| 6.16 | 6.19 | 6.16 → 6.17 → 6.18 → 6.19 |

> **Tip:** Use the [Red Hat Satellite Upgrade Helper](https://access.redhat.com/labs/satelliteupgradehelper/) for instructions matched to your exact version.

## Quick Start (Ansible)

```bash
# Connected (default)
ansible-playbook -i inventory.ini upgrade_satellite_6.19.yml --ask-vault-pass

# Disconnected / air-gapped (6.19 content already staged from ISO locally)
ansible-playbook -i inventory.ini upgrade_satellite_6.19.yml --ask-vault-pass \
  -e satellite_connected=false

# Skip the backup (NOT recommended; only with a fresh VM snapshot)
ansible-playbook -i inventory.ini upgrade_satellite_6.19.yml --ask-vault-pass \
  -e take_backup=false
```

The playbook reads the Satellite admin password and Red Hat Registry credentials from `group_vars/satellite/vault.yml` (the same vault used by the deploy playbook).

## Manual Upgrade Steps

> **Run as root** (or prefix each command with `sudo`). Run inside `tmux` so a dropped SSH session does not interrupt the upgrade.

```bash
# 1. Enable the 6.19 maintenance repository (system must be registered)
subscription-manager repos --enable satellite-maintenance-6.19-for-rhel-9-x86_64-rpms

# 2. Self-upgrade the maintenance tooling (run twice if only the tooling updated)
satellite-maintain self-upgrade

# 3. Pre-upgrade check — NO version argument; target is derived from the enabled repo
satellite-maintain upgrade check -y

# 4. Run the upgrade
satellite-maintain upgrade run -y

# 5. Reboot if the kernel was updated
dnf needs-restarting -r || systemctl reboot
```

> **Important syntax note:** this build of `satellite-maintain` does **not** accept `--target-version`. It derives the target from the enabled `satellite-maintenance-6.19` repository. Passing `--target-version 6.19` returns `Unrecognised option`. Use the bare `-y` form. On first run, the tooling prompts once for the **Satellite admin password** (Hammer setup) and saves it to `/etc/foreman-maintain/foreman-maintain-hammer.yml`.

## What the Playbook Does

### Pre-Tasks

1. **Pre-seeds Hammer credentials** to `/etc/foreman-maintain/foreman-maintain-hammer.yml` so the upgrade never blocks on the interactive password prompt.
2. **Verifies the source version** satisfies the N-1 rule (on 6.18.z, below 6.19).
3. **Confirms registration** (connected mode) — repos cannot be enabled on an unregistered system.
4. **Establishes registry auth** to `/etc/foreman/registry-auth.json` and **verifies the login** with `podman login --get-login`.
5. **Ensures `tmux` is installed.**

### Upgrade Tasks

1. **Backup** — offline backup before any changes (toggle with `-e take_backup=false`).
2. **z-stream current** — `satellite-maintain update run` so the box is on the latest 6.18.z first (connected).
3. **Enable the maintenance repo** — `satellite-maintenance-6.19-...` via the `rhsm_repository` module (connected).
4. **Self-upgrade** the `satellite-maintain` tooling.
5. **Assemble the whitelist** — adds `container-podman-login` only when the registry login was verified, and the disconnected repo checks only in disconnected mode.
6. **Pre-flight check** — `satellite-maintain upgrade check -y` (plus whitelist if needed).
7. **Upgrade** — `satellite-maintain upgrade run -y` (plus whitelist if needed).

### Post-Tasks

1. **Waits for services** to report healthy.
2. **Confirms the new version** via `rpm -q satellite`.
3. **Checks whether a reboot** is required and reports it.
4. Prints a summary with next steps (manifest refresh, content sync, `insights-client --register --force` on hosts, Capsule upgrades later).

## Disconnected (Air-Gapped) Upgrades

The flow is the same, but content comes from local media and the CDN-dependent checks are skipped:

1. Stage the 6.19 binary DVD/ISO content locally and point repositories at it; ensure RHEL 9 BaseOS/AppStream is available locally too.
2. Make the Lightspeed/IOP container images available locally (bundled on the ISO or pre-pulled), since the connected path would otherwise pull them from `registry.redhat.io`.
3. Run with the disconnected whitelist:

```bash
satellite-maintain upgrade check -y --whitelist="repositories-validate,repositories-setup"
satellite-maintain upgrade run   -y --whitelist="repositories-validate,repositories-setup"
```

Run from a directory without a `config/` subdirectory (e.g. `/root`) to avoid a scenario-not-found error.

## Upgrading Capsule Servers

After the Server is on 6.19, upgrade each Capsule in its own window (6.17/6.18 Capsules remain compatible):

```bash
subscription-manager repos --enable satellite-maintenance-6.19-for-rhel-9-x86_64-rpms
satellite-maintain self-upgrade
satellite-maintain upgrade check -y
satellite-maintain upgrade run   -y
```

Restore any manual DNS/DHCP edits from backup afterward.

## Applying Patch Updates (Z-Stream)

Z-stream updates (e.g. 6.19.1 → 6.19.2) use `update`, not `upgrade`:

```bash
satellite-maintain backup offline /var/backup/satellite
satellite-maintain update check
satellite-maintain update run
```

> Always use `satellite-maintain update run` for patching — never raw `dnf update`. The wrapper stops and restarts services correctly and runs any necessary migrations.

## Troubleshooting

### `container-podman-login` check fails (often a false positive)

The pre-upgrade check verifies Satellite can authenticate to `registry.redhat.io` to pull the 6.19 Lightspeed/IOP images. In proxied or firewall-filtered networks this can fail **even when authentication is valid**:

```
The following steps ended up in failing state:
  [container-podman-login]
```

First confirm the login genuinely works:

```bash
podman login registry.redhat.io
podman login --get-login registry.redhat.io   # returns your username if valid
```

If `--get-login` returns your username, it is a false positive — whitelist that one step:

```bash
satellite-maintain upgrade check -y --whitelist="container-podman-login"
satellite-maintain upgrade run   -y --whitelist="container-podman-login"
```

During the run, watch for **`Update IoP containers: [OK]`** — that is the real image pull succeeding, confirming the whitelist was safe. **Only whitelist after verifying the login**; if `--get-login` does not return a username, fix the auth first rather than skipping the check.

### `--target-version` is not recognized

This build derives the target from the enabled maintenance repository. Run `satellite-maintain self-upgrade` (twice if it only updated the tooling), then use the bare `satellite-maintain upgrade check -y`.

### Log locations

```bash
tail -f /var/log/foreman-installer/satellite.log   # primary upgrade log
tail -f /var/log/foreman/production.log            # Foreman application
journalctl -u pulpcore-api                         # content
podman ps -a --filter 'name=iop-*'                 # IOP container status
```

### Other common issues

| Symptom | Fix |
|---|---|
| IOP units fail with `unable to retrieve auth token` | Re-establish auth: `podman login --authfile /etc/foreman/registry-auth.json registry.redhat.io` and `podman login registry.redhat.io`. |
| IOP units stuck in `failed` state | `systemctl reset-failed 'iop-*'` then `satellite-installer --enable-iop`. |
| Upgrade prompts for a password | The Satellite admin password for Hammer setup; saved after first entry. The playbook pre-seeds it. |
| Disconnected dependency failures | Add `--whitelist="repositories-validate,repositories-setup"`, then resolve missing packages from the ISO. |
| Lost SSH during upgrade | `tmux attach` — check `/var/log/foreman-installer/satellite.log` for completion. |

## Best Practices

1. **Be current on the source z-stream first** (`satellite-maintain update run` on 6.18) before the y-stream upgrade.
2. **Always back up** — offline backups are more reliable than online.
3. **Test on a clone or snapshot first.**
4. **Step through minor versions sequentially** — never skip a y-stream.
5. **Use tmux** — upgrades outlast SSH sessions.
6. **Upgrade the Server before Capsules** — Capsules are backward-compatible by one version.
7. **Verify the registry login before whitelisting** the podman-login check.
8. **Review release notes** and run the Upgrade Helper for your exact version.

## References

- [Upgrading Connected Satellite to 6.19](https://docs.redhat.com/en/documentation/red_hat_satellite/6.19/html-single/upgrading_connected_red_hat_satellite_to_6.19/index)
- [Upgrading Disconnected Satellite to 6.19](https://docs.redhat.com/en/documentation/red_hat_satellite/6.19/html-single/upgrading_disconnected_red_hat_satellite_to_6.19/index)
- [Updating Red Hat Satellite (z-stream)](https://docs.redhat.com/en/documentation/red_hat_satellite/6.19/html-single/updating_red_hat_satellite/index)
- [Satellite Upgrade Helper (interactive)](https://access.redhat.com/labs/satelliteupgradehelper/)
- [Satellite Product Life Cycle](https://access.redhat.com/support/policy/updates/satellite)
