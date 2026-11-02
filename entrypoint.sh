#!/bin/sh
# Render the Xray config from the template using NODE_UUID / NODE_PATH.
# If either is unset, generate a random one and print it to the log ONCE,
# so it can be read back from the platform logs. Prefer setting both env
# vars in the panel so the values stay stable across restarts.
set -e

UUID="${NODE_UUID:-}"
WSPATH="${NODE_PATH:-}"
GENERATED=""

if [ -z "$UUID" ]; then
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  GENERATED="NODE_UUID=$UUID"
fi

if [ -z "$WSPATH" ]; then
  HEX="$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
  WSPATH="/dx-$HEX"
  GENERATED="$GENERATED NODE_PATH=$WSPATH"
fi

if [ -n "$GENERATED" ]; then
  echo "[entrypoint] generated credentials (set them as env vars to keep them stable): $GENERATED"
fi

mkdir -p /etc/xray
sed -e "s|__UUID__|$UUID|g" -e "s|__PATH__|$WSPATH|g" \
  /config.template.json > /etc/xray/config.json

exec xray run -c /etc/xray/config.json
