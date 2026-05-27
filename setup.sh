#!/bin/bash
# setup.sh — Install prerequisites and run the Satellite deployment playbook
# Usage:
#   sudo ./setup.sh
#   sudo ./setup.sh -e satellite_fqdn='satellite.prod.example.com'
#
# Any arguments are passed directly to ansible-playbook.

set -euo pipefail

echo "=== Satellite Deployment Bootstrap ==="

# Install Ansible if not present
if ! command -v ansible-playbook &>/dev/null; then
  echo "Installing ansible-core..."
  dnf install -y ansible-core
fi

# Install required Ansible collections.
# Try RPM packages first (available if AAP repo is enabled),
# then fall back to ansible-galaxy (requires internet to galaxy.ansible.com).
echo "Installing required Ansible collections..."
if dnf install -y \
  ansible-collection-community-general \
  ansible-collection-ansible-posix \
  ansible-collection-containers-podman 2>/dev/null; then
  echo "Collections installed via RPM."
else
  echo "RPM packages not available. Falling back to ansible-galaxy..."
  ansible-galaxy collection install community.general ansible.posix containers.podman
fi

echo ""
echo "Starting playbook..."
echo ""

# Run the playbook
ansible-playbook -i inventory.ini deploy_sat.yml --ask-vault-pass "$@"