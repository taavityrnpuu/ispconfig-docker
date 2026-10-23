# ISPConfig "perfect server" in a single systemd container (nginx variant + Radicale CalDAV).
#
# Only Debian / Ubuntu are supported by the ISPConfig autoinstaller.
# CentOS / RHEL / SUSE have no autoinstall support, so "whatever distro"
# is not achievable for ISPConfig specifically. BASE_IMAGE can be swapped
# between debian:12 / ubuntu:22.04 / ubuntu:24.04. PHP is installed from the
# Sury (deb.sury.org) repo, so PHP_VERSION is decoupled from the base distro
# and defaults to 8.4.

ARG BASE_IMAGE=debian:12
FROM ${BASE_IMAGE}

ARG MYSQL_ROOT_PASSWORD=rootpw
ARG ISP_DB_PASSWORD=isppw
ARG ISP_CONFIG_VERSION=3.2.12p1
ARG PHP_VERSION=8.4
ARG ISP_PHP_VERSION=8.3

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    TERM=xterm \
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
    ISP_DB_PASSWORD=${ISP_DB_PASSWORD} \
    ISP_CONFIG_VERSION=${ISP_CONFIG_VERSION}

# --- systemd as init ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends systemd systemd-sysv dbus && \
    ln -sf /lib/systemd/system/multi-user.target /etc/systemd/system/default.target && \
    (systemctl mask \
        systemd-remount-fs.service \
        dev-hugepages.mount \
        sys-fs-fuse-connections.mount \
        systemd-logind.service \
        getty.target \
        console-getty.service \
        systemd-udevd.service \
        systemd-udev-trigger.service \
        systemd-udev-settle.service \
        systemd-udevd-control.socket \
        systemd-udevd-kernel.socket || true)

# --- base tools ---
RUN apt-get install -y --no-install-recommends \
        ca-certificates apt-transport-https wget curl gnupg2 lsb-release sudo \
        openssh-server cron rsyslog logrotate nano \
        unzip bzip2 arj nomarch lzop cabextract lrzip zip haveged \
        python3 python3-pip

# 7z archive support: p7zip on Debian / older Ubuntu, `7zip` on Ubuntu 24.04+
RUN (apt-get install -y --no-install-recommends p7zip || true) && \
    (apt-get install -y --no-install-recommends p7zip-full || true) && \
    (apt-get install -y --no-install-recommends 7zip || true)

# --- PHP from Sury (newer than the base distro default) ---
RUN install -d /usr/share/keyrings && \
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list && \
    apt-get update

# --- nginx + PHP-FPM ---
# ISPConfig's OS profile manages a fixed "default" PHP version (8.3 on
# ubuntu:24.04, 8.2 on debian:12, 8.1 on ubuntu:22.04) and writes its FPM pools
# + nginx sockets for that version, so it must be installed or the UI/apps 502.
# PHP_VERSION is an additional, newer Sury version decoupled from the base.
RUN apt-get install -y --no-install-recommends \
        nginx nginx-extras memcached php-pear && \
    for V in ${ISP_PHP_VERSION} ${PHP_VERSION}; do \
        apt-get install -y --no-install-recommends \
            php${V}-fpm php${V}-cli php${V}-common php${V}-mysql php${V}-curl php${V}-gd \
            php${V}-intl php${V}-imap php${V}-pspell php${V}-sqlite3 php${V}-tidy \
            php${V}-xsl php${V}-zip php${V}-mbstring php${V}-soap php${V}-opcache \
            php${V}-readline php${V}-xml php${V}-ldap php${V}-bz2 \
            php${V}-imagick php${V}-apcu php${V}-memcached; \
    done

# Sury's php-fpm units ship ProtectSystem=full (mounts /usr read-only), but
# ISPConfig lives in /usr/local/ispconfig and the FPM workers write to
# interface/temp + server/temp there. The hardened unit makes /usr read-only, so
# the UI's IDS check fails with "temp is not writable" -> 500. Disable it.
RUN for V in ${ISP_PHP_VERSION} ${PHP_VERSION}; do \
        mkdir -p /etc/systemd/system/php${V}-fpm.service.d && \
        printf '[Service]\nProtectSystem=no\n' > /etc/systemd/system/php${V}-fpm.service.d/override.conf; \
    done

# --- MariaDB ---
RUN apt-get install -y --no-install-recommends mariadb-server mariadb-client

# --- mail: postfix + dovecot + rspamd + clamav ---
RUN apt-get install -y --no-install-recommends \
        postfix postfix-mysql postfix-doc getmail6 rkhunter binutils \
        dovecot-imapd dovecot-pop3d dovecot-mysql dovecot-sieve dovecot-lmtpd \
        rspamd redis-server clamav clamav-daemon \
        libnet-ldap-perl libauthen-sasl-perl libio-string-perl \
        libio-socket-ssl-perl libnet-ident-perl libnet-dns-perl \
        libdbd-mysql-perl postgrey

# --- FTP ---
RUN apt-get install -y --no-install-recommends pure-ftpd-common pure-ftpd-mysql quota quotatool

# --- DNS ---
RUN apt-get install -y --no-install-recommends bind9 dnsutils

# --- stats ---
RUN apt-get install -y --no-install-recommends \
        awffull awstats geoip-database libclass-dbi-mysql-perl libtimedate-perl goaccess

# --- jailkit + fail2ban ---
RUN apt-get install -y --no-install-recommends jailkit fail2ban

# --- webmail + db admin ---
RUN apt-get install -y --no-install-recommends \
        phpmyadmin roundcube roundcube-core roundcube-mysql roundcube-plugins

# --- CalDAV / CardDAV (Radicale) ---
RUN apt-get install -y --no-install-recommends radicale python3-bcrypt && \
    python3 -c "import bcrypt; print('admin:' + bcrypt.hashpw(b'admin', bcrypt.gensalt()).decode())" > /etc/radicale/users && \
    chown radicale:radicale /etc/radicale/users && chmod 640 /etc/radicale/users && \
    mkdir -p /var/lib/radicale/collections && chown radicale:radicale /var/lib/radicale/collections

COPY radicale.config /etc/radicale/config
RUN chown root:radicale /etc/radicale/config && chmod 640 /etc/radicale/config && \
    systemctl enable radicale.service

# --- ISPConfig unattended-install pieces ---
COPY autoinstall.ini /etc/ispconfig/autoinstall.ini
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ispconfig-install.sh /usr/local/bin/ispconfig-install.sh
COPY ispconfig-install.service /etc/systemd/system/ispconfig-install.service
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/ispconfig-install.sh && \
    ln -sf /etc/systemd/system/ispconfig-install.service /etc/systemd/system/multi-user.target.wants/ispconfig-install.service

RUN update-alternatives --set php /usr/bin/php${PHP_VERSION} 2>/dev/null || true

# --- persistent journal for diagnostics ---
RUN mkdir -p /var/log/journal && \
    chown root:systemd-journal /var/log/journal && \
    chmod 2755 /var/log/journal && \
    { [ -s /etc/machine-id ] || cat /proc/sys/kernel/random/uuid > /etc/machine-id; }

STOPSIGNAL SIGRTMIN+3

EXPOSE 22 80 443 8080 25 465 587 110 143 993 995 21 53 5232 3306

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
