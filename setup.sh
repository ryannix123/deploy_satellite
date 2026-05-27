#!/bin/bash
# setup.sh — Install prerequisites and run the Satellite deployment playbook
# Usage:
#   sudo ./setup.sh
#   sudo ./setup.sh -e satellite_fqdn='satellite.prod.example.com'
#
# Any arguments are passed directly to ansible-playbook.

set -euo pipefail

echo "=== Satellite Deployment Bootstrap ==="

# Install Ansible and required collections (RPM packages)
echo "Installing Ansible and required collections..."
dnf install -y \
  ansible-core \
  ansible-collection-community-general \
  ansible-collection-ansible-posix \
  ansible-collection-containers-podman

echo "Collections installed. Starting playbook..."
echo ""

# Run the playbook locally
ansible-playbook -i inventory.ini deploy_sat.yml --ask-vault-pass "$@"
