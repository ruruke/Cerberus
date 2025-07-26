FROM caddy:2-alpine

# Install logrotate and cron for log management
RUN apk add --no-cache logrotate cronie && \
    rm /etc/logrotate.conf

# Copy logrotate configurations
COPY ./logrotate.d/ /etc/logrotate.d/

# Copy Caddyfile to container
COPY Caddyfile /etc/caddy/Caddyfile

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create log directory with proper permissions
RUN mkdir -p /var/log/caddy && \
    chmod 755 /var/log/caddy

# Create cron directory
RUN mkdir -p /var/run/crond

# Expose port 80
EXPOSE 80

# Use custom entrypoint to start both cron and caddy
ENTRYPOINT ["/entrypoint.sh"]