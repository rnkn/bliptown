# Bliptown

## Configuration

```shell-session
# syspatch
# cat <<EOF >> /etc/mail/aliases
root: rnkn
mayor: rnkn
# newaliases
# cat <<EOF > /etc/doas.conf
permit persist keepenv :wheel
# usermod -G wheel,wsrc rnkn
# cat <<EOF > /etc/ssh/sshd_config
PermitRootLogin no
StrictModes no
DenyUsers demo
AuthorizedKeysFile /home/bliptown/users/%u/_pubkeys.txt
PasswordAuthentication no
# rcctl restart sshd
# cat <<EOF > /etc/hostname.vio0
inet autoconf
inet alias **.***.**.*** 255.255.255.255
# cat <<EOT > /etc/fstab
***********.b none swap sw
***********.a / ffs rw 1 1
***********.l /home ffs rw,nodev,nosuid,userquota=/var/quotas/home.user 1 2
***********.d /tmp ffs rw,nodev,nosuid,userquota=/var/quotas/tmp.user 1 2
***********.f /usr ffs ro,nodev 1 2
***********.g /usr/X11R6 ffs rw,nodev 1 2
***********.h /usr/local ffs rw,wxallowed,nodev 1 2
***********.k /usr/obj ffs rw,nodev,nosuid 1 2
***********.j /usr/src ffs rw,nodev,nosuid 1 2
***********.e /var ffs rw,nodev,nosuid 1 2
# quotacheck -a
# quotaon /home /tmp
# ln -s /usr/bin/openrsync rsync
# crontab -l | head -2
MAXMIND_ID=*******
MAXMIND_KEY=************************************_mmk
# geolite2_endpoint="https://${MAXMIND_ID}:${MAXMIND_KEY}@download.maxmind.com/geoip/databases/GeoLite2-Country/download?suffix=tar.gz"
# ftp -Vo /tmp/geolite2-country.tar.gz "$geolite2_endpoint"
# tar -C /var/db/GeoIP -xzf /tmp/geolite2-country.tar.gz
# mv /var/db/GeoIP/GeoLite2-Country_*/*.mmdb \
	/var/db/GeoIP/geolite2-country-current.mmdb
# rm -rf /var/db/GeoIP/GeoLite2-Country_*
```

## Installation

Install required packages:

```shell-session
# pkg_add sqlite3 libffi md4c libqrencode png git sqlports libmaxminddb \
	curl jq monit p5-DBI p5-DBD-SQLite pkglocatedb
```

Build and install [Carton](https://metacpan.org/pod/Carton):

```shell-session
$ cd /tmp
$ ftp https://cdn.openbsd.org/pub/OpenBSD/$(uname -r)/{ports.tar.gz,SHA256.sig}
$ signify -Cp /etc/signify/openbsd-$(uname -r | cut -c 1,3)-base.pub -x SHA256.sig ports.tar.gz
# cd /usr
# tar xzf /tmp/ports.tar.gz
# chown -R :wsrc ports
# chmod -R g+w ports
$ /usr/ports/infrastructure/bin/portgen p5 Carton
$ cd /usr/ports/mystuff/cpan/p5-Carton
# make install
```

Install Bliptown app:

```shell-session
$ git init --bare /home/rnkn/git/bliptown.git
$ cd /usr/local/www
$ git clone /home/rnkn/git/bliptown.git
$ cd bliptown
# carton install
# cd etc
# cp hourly.local daily.local weekly.local \
	httpd.conf pf.conf relayd.conf monitrc motd /etc
# install -m 755 -o root -g bin etc/rc.d/bliptown_helper /etc/rc.d/
# install -m 755 -o root -g bin etc/rc.d/bliptown /etc/rc.d/
# cat <<EOF >> /etc/login.conf
bliptown:\
	:setenv=\
BLIPTOWN_SECRET=***********,\
BLIPTOWN_HEALTH_FILE=/tmp/bliptown.health,\
BLIPTOWN_HELPER_HEALTH_FILE=/tmp/bliptown_helper.health,\
BLIPTOWN_HELPER_SOCKET=/var/run/bliptown_helper.sock,\
BLIPTOWN_DOMAIN=blip.town,\
BLIPTOWN_IPV4=**.***.**.***,\
BLIPTOWN_IPV6=****:****:****:****::*,\
BLIPTOWN_USER_HOME=/home/bliptown/users,\
BLIPTOWN_DB=/var/db/bliptown/users.db,\
BLIPTOWN_LOG_HOME=/var/log/bliptown,\
BLIPTOWN_GEOIP_DB=/var/db/GeoIP/geolite2-country-current.mmdb,\
BLIPTOWN_MD4C_LIB=/usr/local/lib/libmd4c-html.so.0.0,\
BLIPTOWN_MD4C_HTML_LIB=/usr/local/lib/libmd4c-html.so.0.0,\

bliptown_helper:\
	:setenv=\
BLIPTOWN_HELPER_HEALTH_FILE=/tmp/bliptown_helper.health,\
BLIPTOWN_HELPER_SOCKET=/var/run/bliptown_helper.sock,\
BLIPTOWN_HELPER_PREFORK=4,\
BLIPTOWN_DOMAIN=blip.town,\
BLIPTOWN_GID=****,\
BLIPTOWN_USER_HOME=/home/bliptown/users,\
BLIPTOWN_KEYPAIR_FILE=/etc/relayd-keypairs.conf,\
BLIPTOWN_ACME_FILE=/etc/acme-domains.conf:

EOF
# sh /etc/weekly.local
# rcctl enable httpd relayd bliptown_helper bliptown monit
# rcctl start httpd relayd bliptown_helper bliptown monit
```

Install optional packages:

```shell-session
# pkg_add rlwrap emacs vim nano sfeed stagit
```
