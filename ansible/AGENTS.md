# Ansible - Proxmox Host Management

## Common Commands

```bash
# Enter devshell to get ansible
nix develop

# Test connectivity to all Proxmox hosts
ansible -i ansible/inventory/hosts.yml proxmox -m ping

# Dry run (show what would change)
cd ansible && ansible-playbook playbooks/site.yml --check --diff

# Apply to all hosts
cd ansible && ansible-playbook playbooks/site.yml

# Apply only to specific host
cd ansible && ansible-playbook playbooks/site.yml --limit rohan

# Run only GPU fan control role (rohan only)
cd ansible && ansible-playbook playbooks/proxmox-gpu.yml
```

## Hosts

Ansible manages Proxmox hosts (not NixOS VMs):

- **rohan** (192.168.1.24) - Has NVIDIA 1070 Ti
- **gondor** (192.168.1.20)
- **the-shire** (192.168.1.23)

## Roles

- `proxmox-base`: SSH hardening, base packages, authorized keys
- `proxmox-monitoring`: node_exporter (port 9100), smartd
- `nvidia-fan-control`: NVIDIA driver + coolgpus fan control (rohan only)

## Operational Invariants

- The nvidia-fan-control role pins kernel 6.14 because 6.17 lacks headers for DKMS builds. Renovate monitors NVIDIA driver releases to notify when newer drivers support newer kernels.
