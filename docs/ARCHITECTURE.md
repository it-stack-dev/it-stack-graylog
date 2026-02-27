# Architecture — IT-Stack GRAYLOG

## Overview

Graylog aggregates logs from all IT-Stack services via syslog/GELF, providing search, alerting, and dashboards integrated with Zabbix.

## Role in IT-Stack

- **Category:** infrastructure
- **Phase:** 4
- **Server:** lab-proxy1 (10.0.50.15)
- **Ports:** 9000 (Web UI), 1514 (Syslog), 12201 (GELF)

## Dependencies

| Dependency | Type | Required For |
|-----------|------|--------------|
| FreeIPA | Identity | User directory |
| Keycloak | SSO | Authentication |
| PostgreSQL | Database | Data persistence |
| Redis | Cache | Sessions/queues |
| Traefik | Proxy | HTTPS routing |

## Data Flow

```
User → Traefik (HTTPS) → graylog → PostgreSQL (data)
                       ↗ Keycloak (auth)
                       ↗ Redis (sessions)
```

## Security

- All traffic over TLS via Traefik
- Authentication delegated to Keycloak OIDC
- Database credentials via Ansible Vault
- Logs shipped to Graylog
