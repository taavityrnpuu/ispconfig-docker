# ispconfig-docker

[ISPConfig 3.2](https://www.ispconfig.org/) "perfect server" — nginx + PHP-FPM, MariaDB, Postfix/Dovecot/Rspamd/ClamAV, Pure-FTPd, BIND9, Radicale (CalDAV/CardDAV), phpMyAdmin and Roundcube — packaged as a **single systemd container**.

Builds from Debian or Ubuntu and runs the ISPConfig autoinstaller unattended on first boot.

## Build & run

```bash
docker compose build --build-arg BASE_IMAGE=ubuntu:24.04
docker compose up -d
```

First boot runs the autoinstaller (a few minutes). Watch it with `docker compose logs -f ispconfig`.

## Access

| Service | Port |
| --- | --- |
| ISPConfig control panel | `8080` (https) |
| SSH | `2222` |
| HTTP / HTTPS | `80` / `443` |
| SMTP / submission / SMTPS | `25` / `587` / `465` |
| IMAP / IMAPS | `143` / `993` |
| POP3 / POP3S | `110` / `995` |
| FTP (+ passive) | `21` / `20000-21000` |
| DNS (BIND) | `53` tcp+udp |
| Radicale | `5232` |

## Default credentials

| Account | User | Password |
| --- | --- | --- |
| ISPConfig panel | `admin` | `admin` |
| MySQL root | `root` | `rootpw` |
| ISPConfig DB | `ispconfig` | `isppw` |
| Radicale | `admin` | `admin` |

Override `MYSQL_ROOT_PASSWORD`, `ISP_DB_PASSWORD` and `ISP_CONFIG_VERSION` in the compose environment, and change the panel/Radicale passwords after first login.

## Configuration

- `BASE_IMAGE` — `debian:12`, `ubuntu:22.04` or `ubuntu:24.04`.
- `PHP_VERSION` — an extra PHP from the Sury repo, decoupled from the base (default `8.4`).
- `ISP_PHP_VERSION` — the distro-default PHP version ISPConfig's OS profile manages (must match the base: `8.3` for ubuntu:24.04, `8.2` for debian:12, `8.1` for ubuntu:22.04).

Two things the Dockerfile already handles so the panel comes up clean:

1. **ISPConfig hardcodes one default PHP version per distro** and writes its FPM pools + nginx sockets for it, so `ISP_PHP_VERSION` is installed alongside `PHP_VERSION` (a `PHP_VERSION`-only install 502s the panel).
2. **Sury's php-fpm units ship `ProtectSystem=full`** (mounts `/usr` read-only), which would break the panel's writable `interface/temp`. The build drops `ProtectSystem=no` onto both php-fpm services.
