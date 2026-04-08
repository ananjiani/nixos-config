#!/usr/bin/env bash
# Shared topology and helpers for lab-shutdown / lab-startup
# shellcheck disable=SC2034

# --- Topology ---

declare -A PROXMOX_VMS=(
  [gondor]="boromir"
  [rohan]="theoden"
  [the-shire]="samwise pippin frodo"
)

declare -A VM_HOST=(
  [boromir]=gondor
  [theoden]=rohan
  [samwise]=the-shire
  [pippin]=the-shire
  [frodo]=the-shire
)

declare -A VM_ID=(
  [boromir]=100
  [theoden]=104
  [samwise]=103
  [pippin]=105
  [frodo]=102
)

declare -A K3S_ROLE=(
  [boromir]=server
  [samwise]=server
  [theoden]=server
  [rivendell]=agent
)

declare -A CAN_SSH=(
  [gondor]=1 [rohan]=1 [the-shire]=1
  [boromir]=1 [samwise]=1 [theoden]=1
  [pippin]=1 [rivendell]=1
  # frodo (HAOS) has no SSH
)

declare -A MAC_ADDR=(
  [gondor]="b4:2e:99:39:df:9e"
  [rohan]="bc:5f:f4:e9:25:8f"
  [the-shire]="18:60:24:27:80:40"
  [rivendell]="00:e0:9d:87:1d:e4"
)

ALL_PROXMOX=(gondor rohan the-shire)
ALL_VMS=(boromir samwise theoden pippin frodo)
ALL_K3S=(boromir samwise theoden rivendell)
ALL_BARE=(rivendell)

# Every valid node name
ALL_NODES=("${ALL_PROXMOX[@]}" "${ALL_VMS[@]}" "${ALL_BARE[@]}")

# --- Logging ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "\n${BLUE}[STEP]${NC} ${BOLD}$*${NC}"; }

# --- Helpers ---

is_valid_node() {
  local name=$1
  for node in "${ALL_NODES[@]}"; do
    [[ "$node" == "$name" ]] && return 0
  done
  return 1
}

is_in_array() {
  local needle=$1; shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

wait_for_ssh() {
  local host=$1 max=${2:-30} attempt=0
  while (( attempt < max )); do
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${host}" true &>/dev/null; then
      return 0
    fi
    (( attempt++ ))
    sleep 5
  done
  return 1
}

run_or_dry() {
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[dry-run]${NC} $*"
  else
    "$@"
  fi
}

confirm() {
  if $AUTO_YES; then return 0; fi
  read -rp "Proceed? [y/N] " response
  [[ "$response" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
}

# --- Argument parsing ---

parse_args() {
  TARGETS=()
  DRY_RUN=false
  AUTO_YES=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)     TARGETS+=("${ALL_NODES[@]}") ;;
      --k3s)     TARGETS+=("${ALL_K3S[@]}") ;;
      --vms)     TARGETS+=("${ALL_VMS[@]}") ;;
      --proxmox) TARGETS+=("${ALL_PROXMOX[@]}") ;;
      --dry-run) DRY_RUN=true ;;
      --yes|-y)  AUTO_YES=true ;;
      --help|-h) show_help; exit 0 ;;
      -*)        error "Unknown option: $1"; exit 1 ;;
      *)
        if is_valid_node "$1"; then
          TARGETS+=("$1")
        else
          error "Unknown node: $1"
          error "Valid nodes: ${ALL_NODES[*]}"
          exit 1
        fi
        ;;
    esac
    shift
  done

  # Deduplicate
  if [[ ${#TARGETS[@]} -gt 0 ]]; then
    readarray -t TARGETS < <(printf '%s\n' "${TARGETS[@]}" | sort -u)
  fi

  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    show_help
    exit 1
  fi
}

# --- Dependency resolution ---

resolve_shutdown_deps() {
  # If a Proxmox host is targeted, add all its VMs
  local expanded=("${TARGETS[@]}")
  for target in "${TARGETS[@]}"; do
    if [[ -n "${PROXMOX_VMS[$target]+x}" ]]; then
      for vm in ${PROXMOX_VMS[$target]}; do
        expanded+=("$vm")
      done
    fi
  done
  readarray -t TARGETS < <(printf '%s\n' "${expanded[@]}" | sort -u)
}

resolve_startup_deps() {
  # If a VM is targeted, ensure its Proxmox host is reachable; add if not
  local expanded=("${TARGETS[@]}")
  for target in "${TARGETS[@]}"; do
    if [[ -n "${VM_HOST[$target]+x}" ]]; then
      local host="${VM_HOST[$target]}"
      if ! ssh -o ConnectTimeout=2 -o BatchMode=yes "root@${host}" true &>/dev/null; then
        warn "$host is unreachable — adding to startup targets"
        expanded+=("$host")
      fi
    fi
  done
  readarray -t TARGETS < <(printf '%s\n' "${expanded[@]}" | sort -u)
}

# --- Classification ---

classify_targets() {
  TARGET_PROXMOX=()
  TARGET_K3S=()
  TARGET_VMS_SSH=()
  TARGET_VMS_QM=()
  TARGET_BARE=()

  for target in "${TARGETS[@]}"; do
    # Proxmox host?
    if is_in_array "$target" "${ALL_PROXMOX[@]}"; then
      TARGET_PROXMOX+=("$target")
    fi
    # k3s node?
    if [[ -n "${K3S_ROLE[$target]+x}" ]]; then
      TARGET_K3S+=("$target")
    fi
    # VM?
    if [[ -n "${VM_HOST[$target]+x}" ]]; then
      if [[ -n "${CAN_SSH[$target]+x}" ]]; then
        TARGET_VMS_SSH+=("$target")
      else
        TARGET_VMS_QM+=("$target")
      fi
    fi
    # Bare metal?
    if is_in_array "$target" "${ALL_BARE[@]}"; then
      TARGET_BARE+=("$target")
    fi
  done
}

# --- Help (overridden by each script for specific examples) ---

show_topology() {
  cat <<'TOPO'
Topology:
  gondor ──── boromir  (k3s server)
  rohan ───── theoden  (k3s server)
  the-shire ┬ samwise  (k3s server)
            ├ pippin   (plain VM)
            └ frodo    (Home Assistant, no SSH)
  rivendell   (bare metal HTPC, k3s agent)
TOPO
}

show_common_options() {
  cat <<'OPTS'
Targets (mix and match):
  gondor, rohan, the-shire    Proxmox hosts (auto-includes their VMs)
  boromir, samwise, theoden   k3s server VMs
  pippin                      Plain VM
  frodo                       Home Assistant OS VM (no SSH)
  rivendell                   Bare metal HTPC + k3s agent

Groups:
  --all       Everything
  --k3s       All k3s nodes (boromir, samwise, theoden, rivendell)
  --vms       All VMs (boromir, samwise, theoden, pippin, frodo)
  --proxmox   All Proxmox hosts + their VMs

Options:
  --dry-run   Show plan without executing
  --yes, -y   Skip confirmation prompt
  --help, -h  This message
OPTS
}
