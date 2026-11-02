# Personal Xray node for Deployxa (VLESS + WebSocket, env-configured).
# Stage 1: fetch the official Xray-core release binary.
FROM alpine:3.20 AS dl
ARG XRAY_VERSION=v25.8.3
RUN apk add --no-cache curl unzip ca-certificates \
 && curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" \
 && unzip -o /tmp/xray.zip -d /tmp/xray xray \
 && chmod +x /tmp/xray/xray

# Stage 2: a tiny Python front server (front.py, stdlib only) listens
# on port 3000 (health check on `/` + WS relay); Xray itself listens
# on loopback port 3001 only. Python instead of nginx because the
# platform's restricted filesystem denied nginx its log/temp dirs;
# front.py writes nothing to disk.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates python3
COPY --from=dl /tmp/xray/xray /usr/local/bin/xray
COPY entrypoint.sh /entrypoint.sh
COPY front.py /front.py
COPY config.template.json /config.template.json
RUN chmod +x /entrypoint.sh
EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
