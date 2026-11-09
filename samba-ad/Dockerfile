FROM debian:12-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    samba samba-ad-dc samba-ad-provision winbind krb5-user krb5-config smbclient \
    ldb-tools ldap-utils dnsutils procps iproute2 \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh seed.sh /opt/
RUN chmod +x /opt/entrypoint.sh /opt/seed.sh
ENTRYPOINT ["/opt/entrypoint.sh"]
