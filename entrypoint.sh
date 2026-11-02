#!/bin/sh
# Render the Xray config from the template using NODE_UUID / NODE_PATH,
# start the Python front server on port 3000, then run Xray in the
# foreground. If either env var is unset, generate a random one and
# print it to the log ONCE, so it can be read back from the platform
# logs. Prefer setting both env vars in the panel so the values stay
# stable across restarts.
#
# The rendered config goes to /tmp: the platform runs the container
# with a restricted filesystem, and /tmp is the one place that stays
# writable (this is also why the front server is a Python script that
# writes nothing, instead of nginx, which needed writable log/temp
# dirs and died on startup).
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

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${XRAY_CONFIG:-/tmp/config.json}"

sed -e "s|__UUID__|$UUID|g" -e "s|__PATH__|$WSPATH|g" \
  "$HERE/config.template.json" > "$CONFIG"

# Front server: port 3000 answers the platform health check on `/` and
# relays the secret WS path to Xray on 127.0.0.1:3001. It must actually
# be alive before we hand over to Xray, otherwise the deployment looks
# up but the health check (and the node) are dead.
NODE_PATH="$WSPATH" python3 "$HERE/front.py" &
FRONT_PID=$!
sleep 1
if ! kill -0 "$FRONT_PID" 2>/dev/null; then
  echo "[entrypoint] ERROR: front server (front.py) died immediately, aborting" >&2
  exit 1
fi

exec xray run -c "$CONFIG"
