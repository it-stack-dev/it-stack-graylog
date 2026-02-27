# Dockerfile — IT-Stack GRAYLOG wrapper
# Module 20 | Category: infrastructure | Phase: 4
# Base image: graylog/graylog:5.2

FROM graylog/graylog:5.2

# Labels
LABEL org.opencontainers.image.title="it-stack-graylog" \
      org.opencontainers.image.description="Graylog centralized log management" \
      org.opencontainers.image.vendor="it-stack-dev" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/it-stack-dev/it-stack-graylog"

# Copy custom configuration and scripts
COPY src/ /opt/it-stack/graylog/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
