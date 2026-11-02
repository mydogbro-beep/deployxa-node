#!/bin/sh
# Render the Xray config and the nginx front-server config from the
# templates using NODE_UUID / NODE_PATH. If either is unset, generate a
# random one and print it to the log ONCE, so it can be read back from
# the platform logs. Prefer setting both env vars in the panel so the
# values stay stable across restarts.
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

# nginx fronts port 3000: `/` answers the platform health check and the
# secret WS path is proxied to Xray on 127.0.0.1:3001. Fail loudly if
# nginx does not come up, otherwise the deployment looks alive but the
# health check (and the node) are dead.
sed -e "s|__PATH__|$WSPATH|g" \
  /nginx.conf.template > /etc/nginx/nginx.conf
nginx -t -c /etc/nginx/nginx.conf
nginx -c /etc/nginx/nginx.conf

exec xray run -c /etc/xray/config.json
