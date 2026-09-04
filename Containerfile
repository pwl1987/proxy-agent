FROM debian:bookworm-slim

ARG SERVICE_USER=proxy-agent
ARG SERVICE_GROUP=proxy-agent

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       ca-certificates \
       curl \
       iproute2 \
       openssh-client \
       autossh \
       privoxy \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system "$SERVICE_GROUP" \
    && useradd --system --gid "$SERVICE_GROUP" --home-dir "/var/lib/$SERVICE_USER" --create-home --shell /usr/sbin/nologin "$SERVICE_USER" \
    && install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 /run/proxy-agent /var/log/proxy-agent \
    && install -d -o root -g "$SERVICE_GROUP" -m 0750 /etc/proxy-agent /etc/proxy-agent/profiles /opt/proxy-agent

COPY bin /opt/proxy-agent/bin
COPY lib /opt/proxy-agent/lib
COPY backends /opt/proxy-agent/backends
COPY adapters /opt/proxy-agent/adapters
COPY integrations /opt/proxy-agent/integrations
COPY proxy-agent.conf.example /etc/proxy-agent/proxy-agent.conf.example
COPY VERSION /opt/proxy-agent/VERSION

RUN chmod 0755 /opt/proxy-agent/bin/* /opt/proxy-agent/lib/*.sh /opt/proxy-agent/backends/*.sh /opt/proxy-agent/adapters/*.sh /opt/proxy-agent/integrations/*.sh \
    && install -m 0640 -o root -g "$SERVICE_GROUP" /etc/proxy-agent/proxy-agent.conf.example /etc/proxy-agent/proxy-agent.conf \
    && chown -R root:root /opt/proxy-agent

ENV PA_CONFIG=/etc/proxy-agent/proxy-agent.conf \
    PA_STATE_DIR=/run/proxy-agent \
    PA_LOG_DIR=/var/log/proxy-agent

USER $SERVICE_USER
WORKDIR /opt/proxy-agent

ENTRYPOINT ["/opt/proxy-agent/bin/proxy-ctl"]
CMD ["run"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/opt/proxy-agent/bin/proxy-ctl", "status", "--json"]
