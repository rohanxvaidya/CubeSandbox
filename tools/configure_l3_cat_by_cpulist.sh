#!/usr/bin/env bash
set -euo pipefail

# Configure AMD/Intel CAT L3 allocation for a CPU list using resctrl.
# This script is CPU-based (cpus_list), so it works for workloads that
# create/destroy many threads and include both user and kernel execution.

# 用法

# 全系统核心统一限制（你这个最常用）
# sudo configure_l3_cat_by_cpulist.sh --cpus 0-383 --mask 00ff

# 你自己给映射值
# sudo configure_l3_cat_by_cpulist.sh --cpus 0-383 --mask-map "0=00ff;1=00ff;2=00ff;3=00ff;4=00ff;5=00ff;6=00ff;7=00ff;8=00ff;9=00ff;10=00ff;11=00ff"

# 指定组名
# sudo configure_l3_cat_by_cpulist.sh --group l3_16m --cpus 0-383 --mask 00ff

# 仅预览不生效
# sudo configure_l3_cat_by_cpulist.sh --dry-run --cpus 0-383 --mask 00ff

# 参数说明

# --cpus 必填，例如 0-383 或 0-95,192-287
# --mask 和 --mask-map 二选一
# --mode 可选，默认 shareable，可设 exclusive
# --group 可选，默认 l3cat_group
# 快速验证

# cat /sys/fs/resctrl/l3cat_group/schemata
# cat /sys/fs/resctrl/l3cat_group/cpus_list




SCRIPT_NAME="$(basename "$0")"
RESCTRL_MNT="/sys/fs/resctrl"
GROUP_NAME="l3cat_group"
CPU_LIST=""
MASK_HEX=""
MASK_MAP=""
MODE="shareable"
DRY_RUN=0

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --cpus <cpu-list> [--group <name>] [--mode shareable|exclusive] [--dry-run] \\
    (--mask <hex> | --mask-map <map>)

Required:
  --cpus       CPU list in kernel format, e.g. 0-383 or 0-15,32-47

One of:
  --mask       Single CBM mask to apply on all L3 domains, e.g. 00ff
  --mask-map   Explicit per-domain map, e.g. "0=00ff;1=00ff;2=0fff"
               You may also pass with L3: prefix.

Optional:
  --group      resctrl group name (default: l3cat_group)
  --mode       shareable or exclusive (default: shareable)
  --dry-run    Print actions without writing files

Examples:
  ${SCRIPT_NAME} --cpus 0-383 --mask 00ff
  ${SCRIPT_NAME} --cpus 0-95,192-287 --group l3_16m --mask 00ff
  ${SCRIPT_NAME} --cpus 0-383 --mask-map "0=00ff;1=00ff;2=00ff;3=00ff;4=00ff;5=00ff;6=00ff;7=00ff;8=00ff;9=00ff;10=00ff;11=00ff"

Notes:
  - L3 is shared per domain/CCD; this limits available ways, not physical cache size.
  - Run as root.
EOF
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

log() {
  echo "[INFO] $*"
}

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    die "Please run as root."
  fi
}

cpu_supports_l3_cat() {
  if [[ -r /proc/cpuinfo ]] && grep -qm1 '\<cat_l3\>' /proc/cpuinfo; then
    return 0
  fi
  return 1
}

kernel_supports_resctrl_fs() {
  if [[ -r /proc/filesystems ]] && grep -qE '(^|[[:space:]])resctrl$' /proc/filesystems; then
    return 0
  fi
  return 1
}

verify_resctrl_layout() {
  [[ -d "${RESCTRL_MNT}" ]] || die "resctrl mountpoint missing: ${RESCTRL_MNT}"
  [[ -f "${RESCTRL_MNT}/schemata" ]] || die "resctrl schemata file missing under ${RESCTRL_MNT}"
  [[ -f "${RESCTRL_MNT}/cpus_list" ]] || die "resctrl cpus_list file missing under ${RESCTRL_MNT}"
  [[ -d "${RESCTRL_MNT}/info/L3" ]] || die "L3 CAT info directory missing under ${RESCTRL_MNT}/info/L3"
  [[ -f "${RESCTRL_MNT}/info/L3/cbm_mask" ]] || die "L3 CAT cbm_mask missing under ${RESCTRL_MNT}/info/L3"
  [[ -f "${RESCTRL_MNT}/info/L3/bit_usage" ]] || die "L3 CAT bit_usage missing under ${RESCTRL_MNT}/info/L3"
}

is_resctrl_mounted() {
  grep -qsE "[[:space:]]${RESCTRL_MNT}[[:space:]]resctrl[[:space:]]" /proc/mounts
}

mount_resctrl_if_needed() {
  if ! is_resctrl_mounted; then
    [[ -d "${RESCTRL_MNT}" ]] || die "resctrl mountpoint does not exist: ${RESCTRL_MNT}"
    kernel_supports_resctrl_fs || die "Kernel does not expose resctrl filesystem support (/proc/filesystems has no resctrl)."
    log "Mounting resctrl on ${RESCTRL_MNT}"
    mount -t resctrl resctrl "${RESCTRL_MNT}"
  fi
}

ensure_resctrl_ready() {
  cpu_supports_l3_cat || die "CPU does not advertise cat_l3; L3 CAT is not supported on this host."
  mount_resctrl_if_needed
  verify_resctrl_layout
}

validate_group_name() {
  [[ "${GROUP_NAME}" =~ ^[a-zA-Z0-9_.-]+$ ]] || die "Invalid group name: ${GROUP_NAME}"
}

validate_cpus() {
  [[ -n "${CPU_LIST}" ]] || die "--cpus is required"
  [[ "${CPU_LIST}" =~ ^[0-9,-]+$ ]] || die "Invalid --cpus format: ${CPU_LIST}"
}

validate_mode() {
  [[ "${MODE}" == "shareable" || "${MODE}" == "exclusive" ]] || die "--mode must be shareable or exclusive"
}

validate_mask_hex() {
  [[ "${MASK_HEX}" =~ ^[0-9a-fA-F]+$ ]] || die "Invalid --mask hex: ${MASK_HEX}"
}

read_cbm_mask_hex() {
  local cbm_mask
  cbm_mask="$(tr 'A-F' 'a-f' < "${RESCTRL_MNT}/info/L3/cbm_mask")"
  [[ -n "${cbm_mask}" ]] || die "Empty cbm_mask in ${RESCTRL_MNT}/info/L3/cbm_mask"
  echo "${cbm_mask}"
}

validate_mask_against_platform() {
  local mask_lc="$1"
  local cbm_mask
  local mask_value
  local max_value

  cbm_mask="$(read_cbm_mask_hex)"
  mask_value=$((16#${mask_lc}))
  max_value=$((16#${cbm_mask}))

  (( mask_value > 0 )) || die "Mask must be non-zero: ${mask_lc}"
  (( (mask_value & ~max_value) == 0 )) || die "Mask ${mask_lc} exceeds platform cbm_mask ${cbm_mask}"
}

extract_l3_domain_ids() {
  local bit_usage
  bit_usage="$(cat "${RESCTRL_MNT}/info/L3/bit_usage")"
  echo "${bit_usage}" | tr ';' '\n' | awk -F'=' 'NF==2 {print $1}'
}

build_l3_map_from_mask() {
  local mask_lc
  mask_lc="$(echo "${MASK_HEX}" | tr 'A-F' 'a-f')"
  validate_mask_against_platform "${mask_lc}"
  local ids
  ids="$(extract_l3_domain_ids)"
  [[ -n "${ids}" ]] || die "No L3 domains detected in ${RESCTRL_MNT}/info/L3/bit_usage"

  local first=1
  local out=""
  local id
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    if [[ ${first} -eq 1 ]]; then
      out+="${id}=${mask_lc}"
      first=0
    else
      out+=";${id}=${mask_lc}"
    fi
  done <<< "${ids}"

  echo "${out}"
}

normalize_mask_map() {
  local map="${MASK_MAP}"
  map="${map#L3:}"
  map="${map#l3:}"
  [[ -n "${map}" ]] || die "--mask-map cannot be empty"

  # Lightweight validation for entries like domain=hex separated by ';'
  local IFS=';'
  local item
  for item in ${map}; do
    [[ "${item}" =~ ^[0-9]+=[0-9a-fA-F]+$ ]] || die "Invalid --mask-map entry: ${item}"
    validate_mask_against_platform "$(echo "${item#*=}" | tr 'A-F' 'a-f')"
  done

  echo "${map}"
}

write_file() {
  local path="$1"
  local value="$2"
  if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "DRY-RUN: echo '${value}' > ${path}"
  else
    echo "${value}" > "${path}"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cpus)
        CPU_LIST="$2"
        shift 2
        ;;
      --mask)
        MASK_HEX="$2"
        shift 2
        ;;
      --mask-map)
        MASK_MAP="$2"
        shift 2
        ;;
      --group)
        GROUP_NAME="$2"
        shift 2
        ;;
      --mode)
        MODE="$2"
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
        die "Unknown argument: $1"
        ;;
    esac
  done

  need_root
  validate_group_name
  validate_cpus
  validate_mode

  if [[ -n "${MASK_HEX}" && -n "${MASK_MAP}" ]]; then
    die "Use only one of --mask or --mask-map"
  fi
  if [[ -z "${MASK_HEX}" && -z "${MASK_MAP}" ]]; then
    die "One of --mask or --mask-map is required"
  fi

  ensure_resctrl_ready

  local l3_map
  if [[ -n "${MASK_HEX}" ]]; then
    validate_mask_hex
    l3_map="$(build_l3_map_from_mask)"
  else
    l3_map="$(normalize_mask_map)"
  fi

  local grp_dir="${RESCTRL_MNT}/${GROUP_NAME}"
  if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "DRY-RUN: mkdir -p ${grp_dir}"
  else
    mkdir -p "${grp_dir}"
  fi

  log "Applying mode=${MODE} group=${GROUP_NAME} cpus=${CPU_LIST}"
  log "Applying schemata: L3:${l3_map}"

  write_file "${grp_dir}/mode" "${MODE}"
  write_file "${grp_dir}/schemata" "L3:${l3_map}"
  write_file "${grp_dir}/cpus_list" "${CPU_LIST}"

  log "Done."
  log "Check with: cat ${grp_dir}/schemata && cat ${grp_dir}/cpus_list"
}

main "$@"
