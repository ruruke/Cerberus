FROM caddy:2-alpine

# Copy Caddyfile to container
COPY Caddyfile /etc/caddy/Caddyfile

# Create log directory
RUN mkdir -p /var/log/caddy

# Expose port 80
EXPOSE 80

# Caddy will automatically use /etc/caddy/Caddyfile