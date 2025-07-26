#!/bin/sh

# Start cron in the background (Alpine Linux crond doesn't support -b option)
crond -f &

# Start nginx in the foreground
nginx -g 'daemon off;'
