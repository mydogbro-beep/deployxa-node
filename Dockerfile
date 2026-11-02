# Personal Xray node for Deployxa (VLESS + WebSocket, env-configured).
# Stage 1: fetch the official Xray-core release binary.
FROM alpine:3.20 AS dl
ARG XRAY_VERSION=v25.8.3
RUN apk add --no-cache curl unzip ca-certificates \
 && curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" \
 && unzip -o /tmp/xray.zip -d /tmp/xray xray \
 && chmod +x /tmp/xray/xray

# Stage 2: nginx fronts port 3000 (health check on `/` + WS proxy);
# Xray itself listens on loopback port 3001 only.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates nginx
COPY --from=dl /tmp/xray/xray /usr/local/bin/xray
COPY entrypoint.sh /entrypoint.sh
COPY config.template.json /config.template.json
COPY nginx.conf.template /nginx.conf.template
RUN chmod +x /entrypoint.sh
EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
