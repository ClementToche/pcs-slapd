FROM debian:buster

LABEL maintainer="ClementTOCHE"
LABEL version="1.0.0"
LABEL description="SLAPD server"

ARG DEBIAN_FRONTEND=noninteractive
ARG PCS_LDAP_GID
ARG PCS_LDAP_UID
ARG PCS_TLS_GID

RUN if [ -z "${PCS_LDAP_GID}" ]; \
        then groupadd -g 2021 -r openldap; \
    else \
        groupadd -r -g ${PCS_LDAP_GID} openldap; \
    fi \
    && if [ -z "${PCS_TLS_GID}" ]; \
        then groupadd -g 2022 -r tls; \
    else \
        groupadd -r -g ${PCS_TLS_GID} tls; \
    fi \
    && if [ -z "${PCS_LDAP_UID}" ]; \
        then useradd -u 2021 -r -g openldap openldap; \
    else \
        useradd -r -g openldap -u ${PCS_LDAP_UID} openldap; \
    fi \
    && usermod -a -G tls openldap;

# Upgrade the system
RUN apt-get update && apt-get -y upgrade && apt-get install -y -qq \
    slapd \
    ldap-utils

# Clean-up apt 
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Utility scripts
COPY inputs/pcs-logger /usr/sbin/
RUN chown root:root /usr/sbin/pcs-logger
RUN chmod 755 /usr/sbin/pcs-logger

# Entry script
COPY inputs/entry.sh /entry.sh
RUN chown root:root /entry.sh
RUN chmod 760 /entry.sh

# LDAP conf file
COPY inputs/ldap-deb.conf /etc/ldap/ldap-deb.conf
RUN chown root:root /etc/ldap/ldap-deb.conf
RUN chmod 660 /etc/ldap/ldap-deb.conf

# Certs mountpoint
RUN mkdir /etc/ldap/certs
RUN chown openldap:openldap /etc/ldap/certs

# Clean-up default files installed by apt (detection if ldap has been init or not)
RUN rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*

ENTRYPOINT ["/entry.sh"]

# Declare Volumes for LDAP config, DB and Certs
VOLUME ["/etc/ldap/slapd.d/", "/var/lib/ldap/", "/mnt/certs/"]

# We need these port open from the docker
EXPOSE 389/tcp
