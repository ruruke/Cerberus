#!/bin/bash

# Generate docker-compose.yaml from config.toml
# Usage: ./generate-docker-compose.sh [config.toml]

CONFIG_FILE="${1:-config.toml}"
OUTPUT_FILE="./built/docker-compose.yaml"

# Create built directory if it doesn't exist
mkdir -p ./built

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found!"
    exit 1
fi

echo "Generating docker-compose.yaml from $CONFIG_FILE..."

# Extract configuration values using grep and sed
PROXY_PORT=$(grep -E "^\s*listen_port\s*=" "$CONFIG_FILE" | head -1 | sed 's/.*=\s*\([0-9]*\).*/\1/')
PROXY_PORT=${PROXY_PORT:-80}

# Check if TLS is enabled
TLS_ENABLED=$(grep -E "^\s*enabled\s*=\s*true" "$CONFIG_FILE" | head -1)
if [ -n "$TLS_ENABLED" ]; then
    PROXY_EXTERNAL_PORT="8443"
    PROXY_INTERNAL_PORT="443"
else
    PROXY_EXTERNAL_PORT="8080"
    PROXY_INTERNAL_PORT="80"
fi

# Generate docker-compose.yaml
cat > "$OUTPUT_FILE" << EOF
version: '3.8'

services:
  proxy:
    build: ./built/proxy
    restart: always
    ports:
      - "${PROXY_EXTERNAL_PORT}:${PROXY_INTERNAL_PORT}"
    volumes:
      - ./built/proxy/:/etc/caddy/
      - ./built/logs/:/var/log/caddy/
    networks:
      - front-net
      - back-net

  anubis:
    image: ghcr.io/techarohq/anubis:latest
    restart: always
    environment:
      BIND: ":8080"
      DIFFICULTY: "5"
      METRICS_BIND: ":9090"
      SERVE_ROBOTS_TXT: "true"
      TARGET: "http://proxy-2:${PROXY_PORT}"
      POLICY_FNAME: "/data/cfg/botPolicy.json"
    volumes:
      - ./built/config/botPolicy.json:/data/cfg/botPolicy.json:ro
    networks:
      - front-net
      - back-net

  proxy-2:
    build: ./built/proxy-2
    restart: always
    volumes:
      - ./built/proxy-2/:/etc/caddy/
      - ./built/logs/:/var/log/caddy/
      - ./built/ssl/:/etc/ssl/
    networks:
      - back-net

networks:
  front-net:
    driver: bridge
  back-net:
    driver: bridge
EOF

echo "docker-compose.yaml generated successfully!"
echo "External port: $PROXY_EXTERNAL_PORT"
echo "Internal port: $PROXY_INTERNAL_PORT"
echo "Proxy layer 2 port: $PROXY_PORT"