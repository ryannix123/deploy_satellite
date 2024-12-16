# Red Hat Satellite Upgrade Guide

## Upgrade Process Overview

Before upgrading Satellite, ensure you follow these steps:

1. **Backup your Satellite**
   ```bash
   satellite-maintain backup online
   ```

2. **Check current version**
   ```bash
   satellite-maintain packages list
   ```

3. **Check system health**
   ```bash
   satellite-maintain health check
   ```

4. **Upgrade Options**

   a. Using the playbook:
   ```bash
   ansible-playbook -i inventory.ini satellite-upgrade.yml
   ```

   b. Manual upgrade steps:
   ```bash
   satellite-maintain service stop
   dnf update satellite
   satellite-maintain upgrade
   satellite-maintain service start
   satellite-maintain health check
   ```

## Post-Upgrade Tasks

1. Clear browser cache
2. Verify all services are running
3. Test key functionality:
   - Repository synchronization
   - Host registration
   - Content view publishing

## Troubleshooting

If issues occur during upgrade:

1. Check logs:
   ```bash
   tail -f /var/log/satellite-installer/satellite-installer.log
   tail -f /var/log/foreman/production.log
   ```

2. Verify services:
   ```bash
   satellite-maintain service status
   ```

3. Run health check:
   ```bash
   satellite-maintain health check
   ```

## Regular Patching

For regular system patching:

1. Schedule maintenance window
2. Create backup
3. Update packages:
   ```bash
   dnf update
   ```
4. Restart services if required:
   ```bash
   satellite-maintain service restart
   ```

## Best Practices

1. Always backup before upgrading
2. Test upgrade procedure in non-production first
3. Maintain current backups
4. Monitor system resources during upgrade
5. Review release notes for breaking changes
6. Plan for adequate downtime
7. Verify client functionality post-upgrade

## Support

For additional assistance:
- Red Hat Satellite documentation
- Red Hat Customer Portal
- Open support case if needed