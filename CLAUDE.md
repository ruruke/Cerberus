# Cerberus - Multi-Layer Proxy Architecture

## Overview

Cerberus is a dynamic configuration-driven multi-layer proxy architecture system that generates Docker configurations from TOML settings. It provides DDoS protection, load balancing, auto-scaling, and flexible proxy management.

## Architecture Evolution

**Previous**: Static nginx configuration
```
Internet → proxy → anubis → proxy-2 → Backend Services
```

**Current**: Dynamic multi-proxy architecture
```
Internet → HAProxy/Proxy → Anubis (DDoS) → Proxy-2 → Backend Services
```

## Key Features

- **Dynamic Configuration**: TOML-driven setup generation
- **Multiple Proxy Support**: Caddy, HAProxy, Nginx, Traefik
- **Auto-Scaling**: CPU/Memory/Connection-based scaling
- **DDoS Protection**: Anubis AI Firewall integration
- **Template System**: Pre-configured setups for common use cases
- **CLI Management**: Complete service lifecycle control
- **Testing Framework**: Automated configuration validation

## File Structure

```
cerberus/
├── cerberus.sh           # Main CLI controller
├── config.toml          # Runtime configuration (gitignored)
├── config-example.toml  # Template configuration
├── SPECIFICATION.md     # Complete system specification
├── lib/
│   ├── core/           # Core functionality
│   ├── generators/     # Configuration generators
│   ├── scaling/        # Auto-scaling system
│   ├── templates/      # Template management
│   └── testing/        # Test framework
├── templates/          # Pre-built configurations
├── built/             # Generated configurations
└── tests/             # Test suites
```

## CLI Usage

```bash
# Configuration Management
./cerberus.sh generate              # Generate all configurations
./cerberus.sh init --template name  # Initialize from template
./cerberus.sh validate              # Validate configuration
./cerberus.sh clean                 # Clean built directory

# Service Management
./cerberus.sh up [service]          # Start services
./cerberus.sh down [service]        # Stop services
./cerberus.sh restart [service]     # Restart services
./cerberus.sh logs [service]        # View logs
./cerberus.sh ps                    # Service status

# Scaling Management
./cerberus.sh scale [service] [num] # Manual scaling
./cerberus.sh scale auto            # Enable auto-scaling
./cerberus.sh scale status          # Scaling status

# Monitoring & Debugging
./cerberus.sh status                # System overview
./cerberus.sh health                # Health checks
./cerberus.sh metrics               # Performance metrics
./cerberus.sh test                  # Run tests
```

## Configuration System

The system uses TOML configuration with the following structure:

### Basic Configuration
```toml
[project]
name = "cerberus"
scaling = true

[[proxies]]
name = "haproxy-lb"
type = "haproxy"
external_port = 8080
algorithm = "roundrobin"

[[services]]
name = "misskey"
domain = "mi.ruruke.moe"
upstream = "http://192.0.2.1:3000"
```

### Advanced Features
- Multi-proxy layer definitions
- Dynamic service discovery
- Auto-scaling configuration
- DDoS protection rules
- SSL/TLS management

## Current Services (Migration from Legacy)

### Core Services
- **Misskey**: Social media platform (mi.ruruke.moe)
- **Media Proxy**: Image/media handling (media.ruruke.moe)
- **Storage**: S3-compatible storage proxy (storage.ruruke.moe)
- **Summaly**: URL preview service (summaly.ruruke.moe)
- **Homepage**: Personal homepage (ruru.my)

### Infrastructure Services
- **HAProxy**: Load balancer with health checks
- **Anubis**: DDoS protection with AI challenges
- **Caddy**: HTTP/2, automatic HTTPS, reverse proxy
- **Scaler**: Auto-scaling monitor and controller

## Development Philosophy

The system prioritizes:

1. **Reliability**: Extensive error handling and validation
2. **Flexibility**: Support for diverse proxy configurations
3. **Scalability**: Dynamic resource allocation based on load
4. **Maintainability**: Modular design with clear separation of concerns
5. **Testability**: Comprehensive test coverage for all functionality

## Migration Notes

This system replaces the previous static nginx-based configuration with:
- Dynamic configuration generation
- Multi-proxy support
- Automated scaling
- Enhanced monitoring
- Improved maintainability

The legacy configuration is preserved in the git history and can be referenced for service endpoints and specific routing requirements.

## Testing Strategy

- **Unit Tests**: Individual component validation
- **Integration Tests**: Multi-service interaction testing
- **Load Tests**: Performance and scaling validation
- **Security Tests**: DDoS protection and access control verification

## Performance Considerations

- **Resource Monitoring**: CPU, memory, and connection tracking
- **Scaling Policies**: Configurable thresholds and cooldowns
- **Load Distribution**: Multiple algorithms (round-robin, least-conn, etc.)
- **Caching**: Intelligent proxy caching strategies

## Security Features

- **Multi-layer Defense**: Defense in depth architecture
- **Access Control**: IP-based and authentication-based restrictions
- **DDoS Protection**: AI-powered challenge-response system
- **SSL/TLS**: Automatic certificate management
- **Audit Logging**: Comprehensive security event logging

This architecture provides a robust, scalable, and maintainable foundation for high-traffic web applications with advanced protection and monitoring capabilities.