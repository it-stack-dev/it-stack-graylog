# IT-Stack GRAYLOG — Module 20

Graylog aggregates logs from all IT-Stack services via syslog/GELF, providing search, alerting, and dashboards integrated with Zabbix.

**Category:** infrastructure · **Phase:** 4 · **Server:** lab-proxy1  
**Ports:** 9000 (Web UI), 1514 (Syslog), 12201 (GELF)

---

## Quick Start — Lab 01 (Standalone)

```bash
# Clone and run standalone lab
git clone https://github.com/it-stack-dev/it-stack-graylog.git
cd it-stack-graylog
make test-lab-01
```

## Lab Progression

| Lab | Name | Duration | Purpose |
|-----|------|----------|---------|
| [01-standalone](docs/labs/01-standalone.md) | Standalone | 30–60 min | Basic functionality in isolation |
| [02-external](docs/labs/02-external.md) | External Dependencies | 45–90 min | Network integration, external services |
| [03-advanced](docs/labs/03-advanced.md) | Advanced Features | 60–120 min | Production features, performance |
| [04-sso](docs/labs/04-sso.md) | SSO Integration | 90–120 min | Keycloak OIDC/SAML authentication |
| [05-integration](docs/labs/05-integration.md) | Advanced Integration | 90–150 min | Multi-module ecosystem integration |
| [06-production](docs/labs/06-production.md) | Production Deployment | 120–180 min | HA cluster, monitoring, DR |

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Module Manifest

See [$repo.yml](it-stack-graylog.yml) for full module metadata.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [organization guide](https://github.com/it-stack-dev/.github/blob/main/CONTRIBUTING.md).

## License

Apache 2.0 — see [LICENSE](LICENSE).
