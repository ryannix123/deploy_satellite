# Red Hat Satellite 6.18 Deployment Playbook

<p align="center">
  <img src="https://adfinis-assets.ams3.digitaloceanspaces.com/Logo_Red_Hat_Satellite_A_Standard_RGB_Medium_logo_transparent_3201c6c345.png" alt="Red Hat Satellite" width="400">
</p>

> **Disclaimer:** This is a community playbook and is **not officially supported by Red Hat**. It is maintained as a personal project and provided as-is. For production deployments, refer to the [official Satellite 6.18 installation guide](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/html-single/installing_satellite_server_on_red_hat_enterprise_linux/index).

Automates deployment of Red Hat Satellite 6.18 on RHEL 9 with on-premises Red Hat Lightspeed Advisor (formerly Insights) for air-gapped environments.

## Repository Layout

```
deploy_satellite/
├── deploy_sat.yml                      # Main playbook
├── inventory.ini                       # Your host inventory
├── group_vars/
│   └── satellite/
│       ├── vars.yml                    # Non-sensitive defaults
│       └── vault.yml                   # Encrypted credentials (ansible-vault)
└── README.md
```

## Prerequisites

### System Requirements

- Red Hat Enterprise Linux 9.x (x86_64 or aarch64)
- Minimum 20 GB RAM (32 GB recommended for production)
- Minimum 4 CPU cores
- Minimum 100 GB free on `/var` (override with `-e required_disk_gb=50` for home labs or demos)
- Valid Red Hat subscription with Satellite entitlements
- Network connectivity to Red Hat CDN (or disconnected ISO workflow)
- FQDN must resolve to the server's IP (DNS or `/etc/hosts`)

### Ansible Control Node

- Ansible Core 2.14+
- Required collections:

```bash
ansible-galaxy collection install community.general ansible.posix containers.podman redhat.satellite_operations
```

If you don't have access to Automation Hub for the productised collection, use the community equivalent:

```bash
ansible-galaxy collection install theforeman.operations
```

Then update the `include_role` references in the playbook from `redhat.satellite_operations.installer` to `theforeman.operations.installer`.

### Passwordless Sudo

The Ansible user on the Satellite host must have passwordless `sudo` access. Create a sudoers drop-in on the target before running the playbook:

```bash
# On the Satellite host (as root):
echo 'ansible ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ansible
chmod 0440 /etc/sudoers.d/ansible
```

Replace `ansible` with whatever user your inventory connects as. The playbook runs entirely with `become: true` because Satellite installation, `podman login`, and `satellite-installer` all require root.

## Credential Setup

Sensitive values live in `group_vars/satellite/vault.yml`. Non-sensitive defaults live in `group_vars/satellite/vars.yml` and reference the vault variables automatically.

### 1. Create an encrypted vault file

Use `ansible-vault create` to open an editor that encrypts on save — credentials never touch disk in plaintext:

```bash
ansible-vault create group_vars/satellite/vault.yml
```

Paste the following, substituting your real values:

```yaml
vault_satellite_admin_password: "YourSecurePassword"
vault_rh_registry_user: "your-portal-username"
vault_rh_registry_password: "your-portal-password"
```

Save and quit. The file is encrypted immediately.

### 2. Run the playbook

```bash
ansible-playbook deploy_sat.yml --ask-vault-pass
```

The playbook validates that credentials are not still set to `CHANGEME` before proceeding.

### Alternative: Pass credentials at runtime

If you prefer not to use a vault file, override directly:

```bash
ansible-playbook deploy_sat.yml \
  -e vault_satellite_admin_password='S3cureP@ss' \
  -e vault_rh_registry_user='rhn-user' \
  -e vault_rh_registry_password='rhn-pass'
```

## Quick Start

1. Update your inventory:

```ini
# inventory.ini
[satellite]
satellite.example.com ansible_user=ansible
```

2. Set your credentials in the vault (see above).

3. Customize `group_vars/satellite/vars.yml` for your environment — at minimum, set `satellite_fqdn`.

4. Run:

```bash
ansible-playbook -i inventory.ini deploy_sat.yml --ask-vault-pass
```

## What the Playbook Does

### Pre-Tasks

1. **Credential validation** — asserts that admin password and registry credentials are present and not placeholders.
2. **System checks** — validates RAM, CPU, and `/var` disk space against Satellite 6.18 minimums.
3. **DNS check** — verifies the FQDN resolves to the server's IP.
4. **Registry authentication** — runs `podman login` as root and persists the auth token to `/root/.config/containers/auth.json`. This is critical because the IOP containers are managed by systemd Quadlet units that run as root. Without persistent auth at this path, the Quadlet units fail to pull images and hit their restart limit.

### Main Tasks

1. Disables all RHSM repos and enables only the Satellite 6.18 and RHEL 9 repos (architecture-aware).
2. Installs `satellite` and `chrony` packages.
3. Configures hostname, `/etc/hosts`, firewall, and NTP.
4. Runs `satellite-installer` with admin credentials, tuning profile, and Ansible/Discovery/rh-cloud plugins. Idempotent — skips if Satellite is already installed.
5. **Pre-pulls all 13 IOP container images** from `registry.redhat.io` so the systemd Quadlet units start instantly.
6. **Resets any failed IOP systemd units** from prior runs (they hit a 5-attempt restart limit and get stuck in `failed` state).
7. Runs `satellite-installer --enable-iop` to enable the on-prem Lightspeed Advisor.
8. Waits for all Satellite services to report healthy.

### Post-Tasks

- Prints the Satellite URL and Lightspeed Advisor status.

## Configuration Variables

All variables are in `group_vars/satellite/vars.yml`. Override any value with `-e` at runtime.

| Variable | Default | Description |
|---|---|---|
| `satellite_version` | `6.18` | Satellite version (drives repo and image tag names) |
| `satellite_admin_username` | `admin` | Initial admin user |
| `satellite_admin_password` | *(from vault)* | Admin password |
| `rh_registry_user` | *(from vault)* | Red Hat Customer Portal username for `registry.redhat.io` |
| `rh_registry_password` | *(from vault)* | Red Hat Customer Portal password |
| `satellite_organization` | `Default Organization` | Initial organization |
| `satellite_location` | `Default Location` | Initial location |
| `satellite_fqdn` | `satellite.example.com` | FQDN set on the host |
| `satellite_tuning` | `development` | Installer tuning profile (`development`, `default`, `medium`, `large`, `extra-large`) |
| `enable_lightspeed_advisor` | `true` | Enable on-prem Insights (IOP) |
| `satellite_manifest_path` | `/root/manifest.zip` | Subscription manifest to upload |
| `required_memory_gb` | `20` | Minimum RAM in GB |
| `required_cpu_cores` | `4` | Minimum vCPUs |
| `required_disk_gb` | `100` | Minimum free space on `/var` in GB |
| `satellite_firewall_services` | `[http, https, RH-Satellite-6]` | Firewall services to open |

## Usage Examples

### Standard deployment

```bash
ansible-playbook deploy_sat.yml --ask-vault-pass \
  -e satellite_fqdn='satellite.prod.example.com' \
  -e satellite_tuning='default'
```

### Home lab (reduced resources)

Red Hat recommends 100 GB free on `/var` for production. If you're running a demo or home lab with less disk, lower the threshold — Satellite will still install and function, but you may run low on space once you start syncing content repositories.

```bash
ansible-playbook deploy_sat.yml --ask-vault-pass \
  -e satellite_fqdn='satellite.home.lab' \
  -e satellite_tuning='development' \
  -e required_disk_gb=50
```

### Disconnected / air-gapped install

For disconnected installs, use the Satellite 6.18 ISO which bundles all required container images. Install Satellite from the ISO, then the playbook's `satellite-installer --enable-iop` step uses the locally imported containers.

### Skip Lightspeed Advisor

```bash
ansible-playbook deploy_sat.yml --ask-vault-pass \
  -e enable_lightspeed_advisor=false
```

## Why Root Auth Matters for IOP

The Lightspeed Advisor service runs as 13+ Podman Quadlet containers managed by systemd. These units run as root and need credentials to pull images from `registry.redhat.io`. The auth chain works as follows:

1. `podman login` writes a token to an auth file.
2. By default, root's token lands in `/run/containers/0/auth.json` — **volatile, lost on reboot**.
3. The playbook explicitly writes auth to `/root/.config/containers/auth.json` — **persistent across reboots**.
4. If a prior `satellite-installer --enable-iop` run failed, the IOP systemd units may be stuck at their 5-attempt restart limit. The playbook runs `systemctl reset-failed 'iop-*'` before re-enabling.

## Post-Installation Steps

1. Access the web UI at `https://<satellite_fqdn>`
2. Log in with the configured admin credentials
3. Navigate to **Red Hat Lightspeed > Recommendations** to verify the advisor is populating
4. Register RHEL hosts using the global registration template (**Hosts > Register Host**) with **Setup Red Hat Lightspeed** set to **Yes (override)**
5. Configure content views, sync plans, and activation keys

## Troubleshooting

```bash
# Overall health
satellite-maintain health check

# Service status
satellite-maintain service status

# Installer logs
tail -f /var/log/foreman-installer/satellite.log

# IOP container status
podman ps -a --filter 'name=iop-*'
systemctl list-units 'iop-*' --all

# Registry auth (verify root has a valid token)
podman login --get-login registry.redhat.io
cat /root/.config/containers/auth.json

# Reset stuck IOP units after fixing auth
systemctl reset-failed 'iop-*'
satellite-installer --enable-iop
```

| Symptom | Fix |
|---|---|
| `/var has only XX GB free (need 100 GB)` | Override with `-e required_disk_gb=50` for demos/home labs. Not recommended for production with many synced repos. |
| Installer fails at step ~1000 with `unable to retrieve auth token` | Root podman auth missing. Re-run `podman login` and verify `/root/.config/containers/auth.json` exists. |
| IOP units stuck in `failed` state | `systemctl reset-failed 'iop-*'` then re-run the installer. |
| Installer hangs or OOM-killed | Need 20+ GB RAM. Use `--tuning development` for constrained hosts. |
| Lightspeed menu missing in UI | Verify `--enable-iop` was passed. Re-run the playbook — the task is idempotent. |
| Recommendations not appearing | Register at least one RHEL host and wait a few minutes for initial analysis. |

## References

- [Red Hat Satellite 6.18 Documentation](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18)
- [Lightspeed Advisor in Satellite](https://www.redhat.com/en/blog/red-hat-insights-advisor-red-hat-satellite)
- [Disconnected Install Guide](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/html-single/installing_satellite_server_in_a_disconnected_network_environment/index)
- [Red Hat Satellite Product Life Cycle](https://access.redhat.com/support/policy/updates/satellite)