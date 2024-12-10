# Red Hat Satellite Deployment Playbook

This Ansible playbook automates the deployment of Red Hat Satellite 6.16 on RHEL 9. It handles the complete installation process including system preparation, package installation, and post-installation configuration.

## Requirements

### System Requirements
- Red Hat Enterprise Linux 9.x
- Minimum 20GB RAM
- Minimum 4 CPU cores
- A valid Red Hat subscription, including the free tier, with Satellite entitlements
- Network connectivity to Red Hat's CDN

### Ansible Requirements
- Ansible 2.9 or later
- Python 3.x
- `firewalld` module
- Access to target system with sudo privileges

## Pre-Installation Steps

Before running the playbook, ensure:
1. The target system is registered with Red Hat Subscription Manager
2. Required repositories are available
3. The system meets minimum hardware requirements
4. Network connectivity is properly configured

## What the Playbook Does

### Pre-Tasks
1. Verifies system requirements (RAM, CPU)
2. Disables all repositories
3. Enables required RHEL and Satellite repositories based on system architecture. i.e., ARM or x86
4. Updates all system packages
5. Installs Satellite and chronyd packages
6. Configures firewall ports (80, 443, 5647, 8140, 9090)
7. Enables and starts chronyd service

### Main Tasks
1. Runs Satellite installer with configuration for:
   - Admin username and password
   - Initial organization and location
   - Ansible plugin
   - Discovery plugin
2. Waits for services to start
3. Performs post-installation health checks

### Post-Installation Verification
1. Verifies Satellite services are operational
2. Runs comprehensive health checks
3. Verifies web interface accessibility
4. Collects diagnostic information if any checks fail

## Configuration Variables

Key variables that can be customized:
```yaml
satellite_admin_username: "admin"
satellite_admin_password: "changeme123"
satellite_organization: "Default Organization"
satellite_location: "Default Location"
required_memory_gb: 20
required_cpu_cores: 4
```

## Usage

1. Update your inventory file with the target host:
```ini
[satellite]
satellite.example.com ansible_host=192.168.1.6
```

2. Run the playbook:
```bash
ansible-playbook -i inventory.ini satellite-deploy.yml
```

## Post-Installation Steps

After successful deployment:
1. Access the web UI at `https://your-satellite-hostname`
2. Log in with the configured admin credentials
3. Configure repositories and sync plans
4. Add content views and activation keys

## Troubleshooting

If installation fails, the playbook collects diagnostic information including:
- Satellite installer logs
- Foreman logs
- PostgreSQL status
- Service status

Common issues can be diagnosed using:
```bash
satellite-maintain health check
satellite-maintain service status
```

## Firewall Configuration

The playbook configures the following ports:
- 80/tcp (HTTP)
- 443/tcp (HTTPS)
- 5647/tcp (Puppet)
- 8140/tcp (Puppet CA)
- 9090/tcp (Smart Proxy)

## Support

For additional support:
- Consult the [Red Hat Satellite Documentation](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.16)
- Contact Red Hat Support