#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "[x] 需要 root 权限，请用 sudo bash $0 运行" >&2
    exit 1
  fi
  exec sudo -- bash "$0" "$@"
fi

MODE="set"
case "${1:-}" in
  "") ;;
  --restore)
    MODE="restore"
    shift
    ;;
  -h|--help)
    echo "Usage: sudo bash $0"
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 2
    ;;
esac

if (( $# != 0 )); then
  echo "This script does not accept positional arguments." >&2
  exit 2
fi

if [[ "$MODE" == set ]]; then
  SOURCE_ID=2ca3:4006
  TARGET_ID=2c7c:0125
  ACTION_TEXT="把大疆 USB ID 修改为 Quectel ID"
else
  SOURCE_ID=2c7c:0125
  TARGET_ID=2ca3:4006
  ACTION_TEXT="把 Quectel USB ID 恢复为大疆 ID"
fi

SOURCE_VID="${SOURCE_ID%:*}"
SOURCE_PID="${SOURCE_ID#*:}"
TARGET_VID="${TARGET_ID%:*}"
TARGET_PID="${TARGET_ID#*:}"
NEW_ID_PATH=/sys/bus/usb-serial/drivers/option1/new_id
MM_WAS_ACTIVE=0

die() {
  echo "[x] $*" >&2
  exit 1
}

ensure_dependencies() {
  local missing=0
  local command_name

  for command_name in lsusb socat modprobe udevadm; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing=1
    fi
  done

  (( missing == 0 )) && return

  if command -v apt-get >/dev/null 2>&1; then
    echo "[*] 安装依赖：usbutils socat kmod udev"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y usbutils socat kmod udev
  else
    die "缺少 lsusb/socat/modprobe/udevadm；请先用系统包管理器安装 usbutils、socat、kmod、udev"
  fi

  for command_name in lsusb socat modprobe udevadm; do
    command -v "$command_name" >/dev/null 2>&1 || die "依赖安装后仍找不到：$command_name"
  done
}

usb_count() {
  { lsusb -d "$1" 2>/dev/null || true; } | wc -l | tr -d '[:space:]'
}

# shellcheck disable=SC2329 # Called by the EXIT trap below.
restore_modem_manager() {
  if (( MM_WAS_ACTIVE == 1 )); then
    echo "[*] 恢复 ModemManager"
    systemctl start ModemManager >/dev/null 2>&1 || echo "[!] ModemManager 未能自动恢复，请手动检查" >&2
  fi
}
trap restore_modem_manager EXIT

at_exchange() {
  local port="$1"
  local command_text="$2"

  {
    printf '%s\r' "$command_text" |
      socat -t 2 -T 3 - "$port,rawer,b115200" 2>/dev/null || true
  } | tr -d '\r'
}

reply_ok() {
  local line
  local last_result=""

  while IFS= read -r line; do
    line="$(printf '%s' "$line" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
    case "$line" in
      OK) last_result="OK" ;;
      ERROR|+CMEERROR:*|+CMSERROR:*) last_result="ERROR" ;;
    esac
  done <<<"$1"

  [[ "$last_result" == "OK" ]]
}

reply_has_error() {
  local line

  while IFS= read -r line; do
    line="$(printf '%s' "$line" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
    case "$line" in
      ERROR|+CMEERROR:*|+CMSERROR:*) return 0 ;;
    esac
  done <<<"$1"

  return 1
}

parse_qcfg() {
  local reply="$1"
  local line
  local normalized
  local matches=0
  local pattern='^\+QCFG:"USBCFG",0X([0-9A-F]+),0X([0-9A-F]+),([01]),([01]),([01]),([01]),([01]),([01]),([01])$'

  while IFS= read -r line; do
    normalized="$(printf '%s' "$line" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
    if [[ "$normalized" =~ $pattern ]]; then
      ((matches += 1))
      PERSISTED_VID="$(printf '%04x' "$((16#${BASH_REMATCH[1]}))")"
      PERSISTED_PID="$(printf '%04x' "$((16#${BASH_REMATCH[2]}))")"
      QCFG_FLAGS="${BASH_REMATCH[3]},${BASH_REMATCH[4]},${BASH_REMATCH[5]},${BASH_REMATCH[6]},${BASH_REMATCH[7]},${BASH_REMATCH[8]},${BASH_REMATCH[9]}"
    fi
  done <<<"$reply"

  (( matches == 1 ))
}

collect_candidates() {
  local port
  local properties
  local -a ports=()

  CANDIDATES=()

  shopt -s nullglob
  ports=(/dev/ttyUSB*)
  shopt -u nullglob

  for port in "${ports[@]}"; do
    properties="$(udevadm info --query=property --name="$port" 2>/dev/null || true)"
    grep -qix "ID_VENDOR_ID=$CURRENT_VID" <<<"$properties" || continue
    grep -qix "ID_MODEL_ID=$CURRENT_PID" <<<"$properties" || continue

    if grep -qix 'ID_USB_INTERFACE_NUM=02' <<<"$properties"; then
      CANDIDATES+=("$port")
    fi
  done
}

find_at_port() {
  local port
  local reply

  for _ in {1..10}; do
    collect_candidates
    if (( ${#CANDIDATES[@]} > 1 )); then
      die "检测到多个 interface 02 AT 口，请只保留一个待操作模块"
    fi
    if (( ${#CANDIDATES[@]} == 1 )); then
      port="${CANDIDATES[0]}"
      reply="$(at_exchange "$port" AT)"
      if reply_ok "$reply"; then
        AT_PORT="$port"
        return 0
      fi
    fi
    sleep 1
  done

  return 1
}

ensure_dependencies

source_count="$(usb_count "$SOURCE_ID")"
target_count="$(usb_count "$TARGET_ID")"
device_count=$((source_count + target_count))

(( device_count > 0 )) || die "没有找到 $SOURCE_ID 或 $TARGET_ID。若使用虚拟机，请先把模块直通进来"
(( device_count == 1 )) || die "检测到多个支持的模块，请只保留一个待操作模块"

if (( source_count == 1 )); then
  CURRENT_ID="$SOURCE_ID"
  CURRENT_VID="$SOURCE_VID"
  CURRENT_PID="$SOURCE_PID"
else
  CURRENT_ID="$TARGET_ID"
  CURRENT_VID="$TARGET_VID"
  CURRENT_PID="$TARGET_PID"
fi

echo "[*] $ACTION_TEXT：$CURRENT_ID -> $TARGET_ID"

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ModemManager; then
  echo "[*] 临时停止 ModemManager，避免占用 AT 口"
  systemctl stop ModemManager
  MM_WAS_ACTIVE=1
fi

modprobe option || die "无法加载 option USB 串口驱动"
declare -a CANDIDATES=()
collect_candidates

if (( ${#CANDIDATES[@]} == 0 )); then
  [[ -e "$NEW_ID_PATH" ]] || die "内核没有提供 $NEW_ID_PATH"
  if ! printf '%s %s\n' "$CURRENT_VID" "$CURRENT_PID" >"$NEW_ID_PATH" 2>/dev/null; then
    echo "[*] option 驱动可能已经登记该 USB ID，继续检测 interface 02"
  fi
  udevadm settle
fi

AT_PORT=
if ! find_at_port; then
  echo "[!] 属于 $CURRENT_ID 的串口属性：" >&2
  for port in /dev/ttyUSB*; do
    [[ -e "$port" ]] || continue
    echo "--- $port" >&2
    udevadm info -q property -n "$port" 2>/dev/null |
      grep -Ei '^(ID_VENDOR_ID|ID_MODEL_ID|ID_USB_INTERFACE_NUM)=' >&2 || true
  done
  die "找不到能返回 OK 的 AT 口。请检查 USB 直通和 option 驱动"
fi

echo "[✓] AT 口：$AT_PORT"

echo "[*] 读取当前持久 USB 配置"
read_reply="$(at_exchange "$AT_PORT" 'AT+QCFG="usbcfg"')"
printf '%s\n' "$read_reply"
reply_ok "$read_reply" || die "USB 配置读取失败，未做修改"

PERSISTED_VID=
PERSISTED_PID=
QCFG_FLAGS=
parse_qcfg "$read_reply" || die "无法唯一解析 USB 配置，未做修改"
persisted_id="${PERSISTED_VID}:${PERSISTED_PID}"

case "$persisted_id" in
  "$SOURCE_ID"|"$TARGET_ID") ;;
  *) die "模块中保存的是未知 USB ID $persisted_id，拒绝覆盖" ;;
esac

did_write=0
if [[ "$persisted_id" != "$TARGET_ID" ]]; then
  target_vid_upper="${TARGET_VID^^}"
  target_pid_upper="${TARGET_PID^^}"
  expected_flags="$QCFG_FLAGS"
  set_command="AT+QCFG=\"usbcfg\",0x${target_vid_upper},0x${target_pid_upper},${QCFG_FLAGS}"

  echo "[*] 写入持久 USB 配置（保留现有 USB 功能布局）"
  write_reply="$(at_exchange "$AT_PORT" "$set_command")"
  printf '%s\n' "$write_reply"
  if ! reply_ok "$write_reply"; then
    echo "[!] 没有收到明确的 OK，将以回读结果判断是否写入成功" >&2
  fi

  echo "[*] 回读 USB 配置"
  read_reply="$(at_exchange "$AT_PORT" 'AT+QCFG="usbcfg"')"
  printf '%s\n' "$read_reply"
  reply_ok "$read_reply" || die "USB 配置回读失败，未执行重启"

  PERSISTED_VID=
  PERSISTED_PID=
  QCFG_FLAGS=
  parse_qcfg "$read_reply" || die "无法唯一解析回读配置，未执行重启"
  persisted_id="${PERSISTED_VID}:${PERSISTED_PID}"
  [[ "$persisted_id" == "$TARGET_ID" ]] || die "回读值不是目标 ID $TARGET_ID，未执行重启"
  [[ "$QCFG_FLAGS" == "$expected_flags" ]] || die "回读的 USB 功能布局发生变化，未执行重启"
  did_write=1
else
  echo "[✓] 模块中保存的 USB ID 已经是 $TARGET_ID"
fi

if [[ "$CURRENT_ID" == "$TARGET_ID" && "$did_write" == 0 ]]; then
  echo "[✓] 设备当前及持久 USB ID 都是 $TARGET_ID，无需重复执行"
  exit 0
fi

echo "[*] 重启模块；串口立即断开属于正常现象"
cfun_reply="$(at_exchange "$AT_PORT" 'AT+CFUN=1,1')"
printf '%s\n' "$cfun_reply"
reply_has_error "$cfun_reply" && die "模块明确拒绝重启，请断电重插后再检查"

for _ in {1..30}; do
  source_count="$(usb_count "$SOURCE_ID")"
  target_count="$(usb_count "$TARGET_ID")"
  if (( source_count == 0 && target_count == 1 )); then
    echo "[✓] 完成：设备现在是 $TARGET_ID"
    exit 0
  fi
  sleep 1
done

source_count="$(usb_count "$SOURCE_ID")"
target_count="$(usb_count "$TARGET_ID")"
if (( source_count == 0 && target_count == 1 )); then
  echo "[✓] 完成：设备现在是 $TARGET_ID"
  exit 0
fi
if (( source_count > 0 )); then
  die "模块仍然枚举为 $SOURCE_ID；请断电重插模块后再次运行本脚本"
fi
if (( target_count > 1 )); then
  die "重枚举后检测到多个 $TARGET_ID，无法确认操作对象"
fi

echo "[!] 配置已写入并回读成功，但当前 Linux 暂时看不到 $TARGET_ID。" >&2
echo "[!] 若使用虚拟机，请把新出现的 $TARGET_ID 重新直通，然后再次运行本脚本完成验证。" >&2
exit 2
