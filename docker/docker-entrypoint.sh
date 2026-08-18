#!/bin/sh
set -eu

config_path="${CONFIG_PATH:-/opt/vohive/config/config.yaml}"
table_path=/opt/vohive/data/mcc-mnc-table.json

mkdir -p "$(dirname "$config_path")" /opt/vohive/data /opt/vohive/logs

if [ ! -s "$config_path" ]; then
  cp /usr/share/vohive/config.yaml "$config_path"
  chmod 0600 "$config_path"
  echo "Created default config: $config_path"
fi

if [ ! -s "$table_path" ]; then
  cp /usr/share/vohive/mcc-mnc-table.json "$table_path"
  chmod 0644 "$table_path"
  echo "Created MCC/MNC table: $table_path"
fi

if [ "$#" -eq 0 ]; then
  set -- /opt/vohive/bin/vohive -c "$config_path"
elif [ "${1#-}" != "$1" ]; then
  set -- /opt/vohive/bin/vohive "$@"
fi

exec "$@"
