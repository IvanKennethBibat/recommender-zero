# Same major version as the db service, so pg_dump matches the server
FROM postgres:16.15

RUN apt-get update \
    && apt-get install -y --no-install-recommends awscli \
    && rm -rf /var/lib/apt/lists/*

COPY backup.sh /usr/local/bin/backup.sh

# A fresh named volume mounted here inherits this ownership, so the non-root user can write dumps
RUN mkdir /backups && chown postgres:postgres /backups

USER postgres

ENTRYPOINT ["/usr/local/bin/backup.sh"]
