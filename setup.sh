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
# Priority: 1) Local tarballs (bundled in repo), 2) RPM packages (AAP repo), 3) Galaxy
echo "Installing required Ansible collections..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ls "${SCRIPT_DIR}"/collections/*.tar.gz &>/dev/null; then
  echo "Installing collections from local tarballs..."
  ansible-galaxy collection install "${SCRIPT_DIR}"/collections/*.tar.gz
elif subscription-manager repos --enable ansible-automation-platform-2.7-for-rhel-9-x86_64-rpms 2>/dev/null && \
     dnf install -y ansible-collection-community-general ansible-collection-ansible-posix ansible-collection-containers-podman 2>/dev/null; then
  echo "Collections installed via RPM."
else
  echo "Local tarballs and RPM packages not available. Falling back to ansible-galaxy..."
  ansible-galaxy collection install community.general ansible.posix containers.podman
fi

echo ""
echo "Starting playbook..."
echo ""

# Run the playbook
ansible-playbook -i inventory.ini deploy_sat.yml --ask-vault-pass "$@"