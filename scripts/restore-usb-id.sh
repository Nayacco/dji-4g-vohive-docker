#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  "") ;;
  -h|--help)
    echo "Usage: sudo bash $0"
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 2
    ;;
esac

exec bash "$SCRIPT_DIR/set-usb-id.sh" --restore "$@"
