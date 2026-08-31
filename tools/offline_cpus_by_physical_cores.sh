#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./offline_cpus_by_physical_cores.sh --keep <core-list> [--dry-run]
  sudo ./offline_cpus_by_physical_cores.sh --all [--dry-run]
  sudo ./offline_cpus_by_physical_cores.sh --first-n-phys <count> [--dry-run]

Description:
  Keep the specified PHYSICAL cores online (and all their SMT sibling threads),
  online any currently-offline logical CPUs belonging to those physical cores,
  then offline all other currently-online logical CPUs.

Core list format:
  - Single core: 5
  - Range: 0-143
  - Mixed: 0-7,16,20-31

Examples:
  sudo ./offline_cpus_by_physical_cores.sh --keep 0-143
  sudo ./offline_cpus_by_physical_cores.sh --all
  sudo ./offline_cpus_by_physical_cores.sh --first-n-phys 144
  sudo ./offline_cpus_by_physical_cores.sh --keep 0-7,16-23 --dry-run

Notes:
  - Physical core numbers map to topology core_id on single-socket systems.
  - This script is designed for your current server (single socket, SMT=2).
EOF
}

KEEP_LIST=""
DRY_RUN=0
KEEP_ALL=0
FIRST_N_PHYS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP_LIST="${2:-}"
      shift 2
      ;;
    --all)
      KEEP_ALL=1
      shift
      ;;
    --first-n-phys)
      FIRST_N_PHYS="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

OPTION_COUNT=0
[[ -n "$KEEP_LIST" ]] && OPTION_COUNT=$((OPTION_COUNT + 1))
[[ "$KEEP_ALL" -eq 1 ]] && OPTION_COUNT=$((OPTION_COUNT + 1))
[[ -n "$FIRST_N_PHYS" ]] && OPTION_COUNT=$((OPTION_COUNT + 1))

if [[ "$OPTION_COUNT" -ne 1 ]]; then
  echo "Error: exactly one of --keep, --all, or --first-n-phys must be specified." >&2
  usage
  exit 1
fi

if [[ "$DRY_RUN" -eq 0 && "$EUID" -ne 0 ]]; then
  echo "Error: root privileges are required unless using --dry-run." >&2
  exit 1
fi

expand_cpu_list() {
  local list="$1"
  local -a out=()
  local item start end i

  IFS=',' read -r -a items <<< "$list"
  for item in "${items[@]}"; do
    if [[ "$item" =~ ^[0-9]+$ ]]; then
      out+=("$item")
    elif [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if (( start > end )); then
        echo "Invalid range: $item" >&2
        exit 1
      fi
      for ((i=start; i<=end; i++)); do
        out+=("$i")
      done
    else
      echo "Invalid core list item: $item" >&2
      exit 1
    fi
  done

  printf '%s\n' "${out[@]}" | awk '!seen[$0]++' | sort -n
}

normalize_cpu_list() {
  local list="$1"
  local -a arr=()
  mapfile -t arr < <(expand_cpu_list "$list")
  (IFS=,; echo "${arr[*]}")
}

PRESENT_LOGICAL_LIST="$(cat /sys/devices/system/cpu/present)"
ONLINE_LOGICAL_LIST="$(cat /sys/devices/system/cpu/online)"
OFFLINE_LOGICAL_LIST="$(cat /sys/devices/system/cpu/offline 2>/dev/null || true)"
mapfile -t PRESENT_LOGICAL_CPUS < <(expand_cpu_list "$PRESENT_LOGICAL_LIST")
mapfile -t ONLINE_LOGICAL_CPUS < <(expand_cpu_list "$ONLINE_LOGICAL_LIST")
mapfile -t KEEP_PHYS_CORES < <(expand_cpu_list "$KEEP_LIST")

# Build physical-core index -> logical sibling list map from all present CPUs.
# Physical core index is assigned by sorting unique thread_siblings groups by
# their first logical CPU ID (matches this server's 0..191 physical core style).
declare -A UNIQUE_SIBLINGS
declare -A SIBLING_DELTAS
for cpu in "${PRESENT_LOGICAL_CPUS[@]}"; do
  topo_dir="/sys/devices/system/cpu/cpu${cpu}/topology"
  sib_file="${topo_dir}/thread_siblings_list"
  [[ -f "$sib_file" ]] || continue

  siblings="$(normalize_cpu_list "$(cat "$sib_file")")"
  UNIQUE_SIBLINGS["$siblings"]=1
  IFS=',' read -r -a sib_arr <<< "$siblings"
  if [[ "${#sib_arr[@]}" -eq 2 ]]; then
    delta="$((sib_arr[1] - sib_arr[0]))"
    SIBLING_DELTAS["$delta"]=1
  fi
done

EXPECTED_THREADS_PER_CORE=2
TOTAL_PRESENT="${#PRESENT_LOGICAL_CPUS[@]}"
EXPECTED_PHYS="$((TOTAL_PRESENT / EXPECTED_THREADS_PER_CORE))"

if [[ "${#SIBLING_DELTAS[@]}" -eq 1 ]]; then
  SIBLING_DELTA="$(printf '%s\n' "${!SIBLING_DELTAS[@]}")"
  if (( SIBLING_DELTA > 0 )) && (( TOTAL_PRESENT == SIBLING_DELTA * EXPECTED_THREADS_PER_CORE )); then
    unset UNIQUE_SIBLINGS
    declare -A UNIQUE_SIBLINGS
    for ((first=0; first<SIBLING_DELTA; first++)); do
      second=$((first + SIBLING_DELTA))
      UNIQUE_SIBLINGS["${first},${second}"]=1
    done
  fi
fi

mapfile -t SORTED_SIBLING_GROUPS < <(
  for sib in "${!UNIQUE_SIBLINGS[@]}"; do
    first="${sib%%,*}"
    echo "${first}|${sib}"
  done | sort -n -t'|' -k1,1 | cut -d'|' -f2-
)

declare -a PHYS_INDEX_TO_SIBLINGS=()
for i in "${!SORTED_SIBLING_GROUPS[@]}"; do
  PHYS_INDEX_TO_SIBLINGS[$i]="${SORTED_SIBLING_GROUPS[$i]}"
done

TOTAL_PHYS="${#PHYS_INDEX_TO_SIBLINGS[@]}"

if [[ "$KEEP_ALL" -eq 1 ]]; then
  KEEP_LIST="0-$((TOTAL_PHYS - 1))"
  mapfile -t KEEP_PHYS_CORES < <(expand_cpu_list "$KEEP_LIST")
elif [[ -n "$FIRST_N_PHYS" ]]; then
  if ! [[ "$FIRST_N_PHYS" =~ ^[0-9]+$ ]]; then
    echo "Error: --first-n-phys requires a non-negative integer." >&2
    exit 1
  fi
  if (( FIRST_N_PHYS <= 0 )); then
    echo "Error: --first-n-phys must be greater than 0." >&2
    exit 1
  fi
  if (( FIRST_N_PHYS > TOTAL_PHYS )); then
    echo "Error: --first-n-phys=$FIRST_N_PHYS exceeds detected physical core count $TOTAL_PHYS." >&2
    exit 1
  fi
  KEEP_LIST="0-$((FIRST_N_PHYS - 1))"
  mapfile -t KEEP_PHYS_CORES < <(expand_cpu_list "$KEEP_LIST")
fi

# Collect logical CPUs to keep online.
declare -A KEEP_LOGICAL_SET
for phys_idx in "${KEEP_PHYS_CORES[@]}"; do
  if (( phys_idx < 0 || phys_idx >= TOTAL_PHYS )); then
    echo "Warning: physical core index $phys_idx out of range [0,$((TOTAL_PHYS - 1))]; skipping." >&2
    continue
  fi
  siblings="${PHYS_INDEX_TO_SIBLINGS[$phys_idx]}"
  while IFS= read -r sib_cpu; do
    KEEP_LOGICAL_SET["$sib_cpu"]=1
  done < <(expand_cpu_list "$siblings")
done

if [[ "${#KEEP_LOGICAL_SET[@]}" -eq 0 ]]; then
  echo "Error: no valid CPUs were selected to keep online." >&2
  exit 1
fi

# Determine logical CPUs that should be onlined and offlined.
declare -A ONLINE_LOGICAL_SET
for cpu in "${ONLINE_LOGICAL_CPUS[@]}"; do
  ONLINE_LOGICAL_SET["$cpu"]=1
done

declare -a TO_ONLINE=()
for cpu in "${!KEEP_LOGICAL_SET[@]}"; do
  if [[ -z "${ONLINE_LOGICAL_SET[$cpu]:-}" ]]; then
    TO_ONLINE+=("$cpu")
  fi
done
if [[ "${#TO_ONLINE[@]}" -gt 0 ]]; then
  mapfile -t TO_ONLINE < <(printf '%s\n' "${TO_ONLINE[@]}" | sort -n)
fi

declare -a TO_OFFLINE=()
for cpu in "${ONLINE_LOGICAL_CPUS[@]}"; do
  if [[ -z "${KEEP_LOGICAL_SET[$cpu]:-}" ]]; then
    TO_OFFLINE+=("$cpu")
  fi
done

if [[ "${#TO_ONLINE[@]}" -eq 0 && "${#TO_OFFLINE[@]}" -eq 0 ]]; then
  echo "Nothing to change. Current online CPUs already match requested keep set."
  exit 0
fi

# Safety check: do not attempt to offline CPU0.
for cpu in "${TO_OFFLINE[@]}"; do
  if [[ "$cpu" -eq 0 ]]; then
    echo "Error: computed result would offline CPU0; aborting for safety." >&2
    exit 1
  fi
done

echo "Requested keep physical cores: $KEEP_LIST"
echo "Detected physical core count : $TOTAL_PHYS"
echo "Present logical CPUs        : $PRESENT_LOGICAL_LIST"
echo "Current online logical CPUs : $ONLINE_LOGICAL_LIST"
if [[ -n "$OFFLINE_LOGICAL_LIST" ]]; then
  echo "Current offline logical CPUs: $OFFLINE_LOGICAL_LIST"
fi
echo "Will keep logical CPU count  : ${#KEEP_LOGICAL_SET[@]}"
echo "Will online logical CPU count : ${#TO_ONLINE[@]}"
if [[ "${#TO_ONLINE[@]}" -gt 0 ]]; then
  echo "Online CPU list              : $(IFS=,; echo "${TO_ONLINE[*]}")"
fi
echo "Will offline logical CPU count: ${#TO_OFFLINE[@]}"
echo "Offline CPU list             : $(IFS=,; echo "${TO_OFFLINE[*]}")"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[DRY-RUN] No changes applied."
  exit 0
fi

for cpu in "${TO_ONLINE[@]}"; do
  online_file="/sys/devices/system/cpu/cpu${cpu}/online"
  if [[ -f "$online_file" ]]; then
    echo 1 > "$online_file"
  fi
done

for cpu in "${TO_OFFLINE[@]}"; do
  online_file="/sys/devices/system/cpu/cpu${cpu}/online"
  if [[ -f "$online_file" ]]; then
    echo 0 > "$online_file"
  fi
done

NEW_ONLINE="$(cat /sys/devices/system/cpu/online)"
echo "Done. New online logical CPUs: $NEW_ONLINE"
