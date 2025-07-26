# Multi-stage build for Cerberus
FROM rust:1.85-slim AS builder

# Install dependencies for building
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Set work directory
WORKDIR /app

# Copy Cargo files
COPY Cargo.toml Cargo.lock ./

# Copy source code
COPY src/ ./src/

# Build the application in release mode
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -m -u 1001 cerberus-user

# Set work directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder --chown=cerberus-user:cerberus-user /app/target/release/cerberus /usr/local/bin/cerberus

# Create necessary directories
RUN mkdir -p /app/built /app/config \
    && chown -R cerberus-user:cerberus-user /app

# Switch to non-root user
USER cerberus-user

# Create default config directory
VOLUME ["/app/config", "/app/built"]

# Expose commonly used ports
EXPOSE 80 8080 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD cerberus validate || exit 1

# Default command
ENTRYPOINT ["cerberus"]
CMD ["generate"]