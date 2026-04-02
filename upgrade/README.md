# Red Hat Satellite Upgrade Guide

This guide covers upgrading Red Hat Satellite through minor versions (e.g., 6.16 → 6.17 → 6.18) and applying z-stream patch updates within a version. Always use `satellite-maintain` for both — never run raw `dnf update` against Satellite packages.

## Playbook Files

| File | Purpose |
|---|---|
| `satellite-upgrade.yml` | Main upgrade playbook — validates versions, backs up, loops through hops, enables Lightspeed Advisor |
| `satellite-upgrade-hop.yml` | Included task file — handles a single version hop (repo swap, pre-check, upgrade, reboot, health check) |

## Upgrade Paths

Satellite only supports upgrading one minor version at a time. If you need to jump multiple versions, you must step through each one sequentially:

| Current Version | Target | Path |
|---|---|---|
| 6.16 | 6.18 | 6.16 → 6.17 → 6.18 |
| 6.17 | 6.18 | 6.17 → 6.18 (direct) |

Capsule Servers are compatible one version behind. After upgrading Satellite to 6.18, Capsules on 6.17 or 6.16 continue to work. This lets you upgrade Capsules in separate maintenance windows.

> **Tip:** Use the [Red Hat Satellite Upgrade Helper](https://access.redhat.com/labs/satelliteupgradehelper/) to generate step-by-step instructions customized for your current version.

## Quick Start

```bash
# Multi-hop: 6.16 → 6.17 → 6.18
ansible-playbook satellite-upgrade.yml --ask-vault-pass \
  -e current_version=6.16 \
  -e target_version=6.18

# Single hop: 6.17 → 6.18
ansible-playbook satellite-upgrade.yml --ask-vault-pass \
  -e current_version=6.17 \
  -e target_version=6.18

# Skip Lightspeed Advisor
ansible-playbook satellite-upgrade.yml --ask-vault-pass \
  -e current_version=6.17 \
  -e target_version=6.18 \
  -e enable_lightspeed_advisor=false
```

The playbook uses Red Hat Registry credentials from `group_vars/satellite/vault.yml` (the same vault used by the deploy playbook) to pre-pull IOP container images. If you haven't set up the vault yet, see the deploy playbook's README.

## Before You Begin

### 1. Review release notes

Read the release notes for every version you'll pass through. Pay attention to deprecated features, removed API endpoints, and Hammer CLI changes that might affect your integrations.

- [Satellite 6.17 Release Notes](https://docs.redhat.com/en/documentation/red_hat_satellite/6.17/html-single/release_notes/index)
- [Satellite 6.18 Release Notes](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/html/release_notes/index)

### 2. Back up your Satellite

The playbook creates an online backup automatically. For a more consistent backup (services will be stopped), run manually before the playbook:

```bash
satellite-maintain backup offline /var/satellite-backup
```

### 3. Check current version and health

```bash
# Confirm your current version
rpm -q satellite --qf '%{VERSION}\n'

# Run a full health check
satellite-maintain health check

# Run upgrade-specific pre-checks (use the TARGET version)
satellite-maintain upgrade check --target-version 6.17
```

Address any errors or warnings before proceeding.

### 4. Test with --noop (optional but recommended)

Check which config files the installer would overwrite:

```bash
satellite-installer --noop
```

If you've made manual edits to files managed by `satellite-installer` (e.g., DNS or DHCP configs), back them up first. The installer will overwrite them.

### 5. Use tmux

Upgrades can take 30 minutes to 2 hours depending on your environment. Always run inside `tmux` so you can reattach if your SSH session drops:

```bash
tmux new -s satellite-upgrade
```

## What the Playbook Does

### Pre-Tasks

1. **Validates version inputs** — confirms `current_version` and `target_version` are valid and in the right order.
2. **Builds the upgrade path** — computes the sequential hops (e.g., 6.16 → 6.17 → 6.18).
3. **Verifies installed version** — checks `rpm -q satellite` matches the declared `current_version`.
4. **Creates a backup** — runs `satellite-maintain backup online` before touching anything.

### Per-Hop Tasks (satellite-upgrade-hop.yml)

For each version hop (e.g., 6.16 → 6.17), the included task file:

1. Enables the target version repositories via `satellite-maintain repository enable`.
2. Updates `rubygem-foreman_maintain` to the version that knows about the target.
3. Runs `satellite-maintain upgrade check` pre-flight validation.
4. Runs `satellite-maintain upgrade run` (handles stopping services, updating packages, running the installer, applying DB migrations, restarting services).
5. Reboots if the kernel was updated.
6. Verifies all services are healthy before proceeding to the next hop.

### Post-Upgrade Tasks

1. **Registry authentication** — persists `podman login` to `/root/.config/containers/auth.json` (required for IOP Quadlet units that run as root).
2. **Pre-pulls all 14 IOP container images** so the systemd Quadlet units start instantly.
3. **Resets failed IOP systemd units** from any prior attempts.
4. **Enables Lightspeed Advisor** with `satellite-installer --enable-iop`.
5. **Refreshes the subscription manifest**.

## Upgrading Capsule Servers

After the Satellite Server is upgraded, upgrade each Capsule:

```bash
# On each Capsule Server
dnf update -y rubygem-foreman_maintain
satellite-maintain upgrade run --target-version 6.18
```

Capsules can be upgraded in separate maintenance windows. Versions 6.17 and 6.16 remain compatible with a 6.18 Satellite Server.

## Applying Patch Updates (Z-Stream)

Z-stream updates (e.g., 6.18.1 → 6.18.2) are applied with `satellite-maintain update`, not `upgrade`:

```bash
# Back up first
satellite-maintain backup online /var/satellite-backup

# Check readiness
satellite-maintain update check

# Apply the update
satellite-maintain update run
```

> **Important:** Always use `satellite-maintain update run` for patching — never raw `dnf update`. The `satellite-maintain` wrapper ensures services are stopped and restarted correctly and that the installer runs any necessary migrations.

## Troubleshooting

### Log locations

```bash
# Installer / upgrade log (primary)
tail -f /var/log/foreman-installer/satellite.log

# Foreman application log
tail -f /var/log/foreman/production.log

# Candlepin (subscription management)
tail -f /var/log/candlepin/candlepin.log

# Pulp (content management)
journalctl -u pulpcore-api

# IOP container status
podman ps -a --filter 'name=iop-*'
systemctl list-units 'iop-*' --all
```

### Common issues

| Symptom | Fix |
|---|---|
| IOP units fail with `unable to retrieve auth token` | Root podman auth missing. Verify `/root/.config/containers/auth.json` exists. Re-run `podman login --authfile /root/.config/containers/auth.json registry.redhat.io`. |
| IOP units stuck in `failed` state | `systemctl reset-failed 'iop-*'` then re-run `satellite-installer --enable-iop`. |
| Upgrade fails on package dependencies (disconnected) | `satellite-maintain upgrade run --target-version 6.18 --whitelist="repositories-validate,repositories-setup"` then manually resolve missing packages. |
| Services won't start after upgrade | `satellite-maintain service restart && satellite-maintain health check` |
| Lost SSH during upgrade | `tmux attach -t satellite-upgrade` — check `/var/log/foreman-installer/satellite.log` for `Success!` |

## Best Practices

1. **Always back up before upgrading** — offline backups are more reliable than online.
2. **Test on a clone first** — Satellite supports cloning your server for upgrade testing.
3. **Step through versions sequentially** — never skip minor versions.
4. **Use tmux** — long-running upgrades will outlast your SSH session.
5. **Run `--noop` first** — catch config file conflicts before the real upgrade.
6. **Upgrade Satellite before Capsules** — Capsules are backward-compatible by one version.
7. **Review release notes** — breaking changes are documented; don't skip this.
8. **Schedule adequate downtime** — plan for 30 minutes to 2 hours per hop depending on data volume.

## References

- [Upgrading Connected Satellite to 6.18](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/html-single/upgrading_connected_red_hat_satellite_to_6.18/index)
- [Upgrading Disconnected Satellite to 6.18](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/html-single/upgrading_disconnected_red_hat_satellite_to_6.18/index)
- [Updating Red Hat Satellite (z-stream)](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/html-single/updating_red_hat_satellite/index)
- [Satellite Upgrade Helper (interactive)](https://access.redhat.com/labs/satelliteupgradehelper/)
- [Satellite Product Life Cycle](https://access.redhat.com/support/policy/updates/satellite)