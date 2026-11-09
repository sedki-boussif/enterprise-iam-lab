FROM debian:12-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    krb5-user libsasl2-modules-gssapi-mit ldap-utils dnsutils \
    freeradius-utils iputils-ping ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY krb5.conf /etc/krb5.conf
ENV LDAPSASL_NOCANON=on
CMD ["sleep", "infinity"]
