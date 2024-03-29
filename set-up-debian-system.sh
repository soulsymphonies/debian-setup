#!/bin/bash

# import settings, if not present show instructions and exit script
if [ -f install.conf ]; then
	source install.conf
else
	echo "ERROR: install.conf not found!"
	echo "Please copy install.conf.template to install.conf first"
	echo "for example use the following command: cp install.conf.template install.conf"
	echo "IMPORTANT: adjust install.conf to your environment"
	echo "exiting script now"
	exit 1;
fi

# setting language non-interactively
LANG=en_US.UTF-8 locale-gen --purge en_US.UTF-8
echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale

# check if root, else use sudo
WHOAMI=$(whoami)
if [ "$WHOAMI" != "root" ]; then
    SUDO=sudo
fi
# adding repositories

${SUDO} apt-get -qq -y install apt-transport-https curl lsb-release ca-certificates software-properties-common dirmngr

echo "adding repositories"
# add stretch-backports
${SUDO} sh -c 'echo "deb http://ftp.de.debian.org/debian/ stretch-backports main contrib non-free" > /etc/apt/sources.list.d/backports.list'

# add debian sury php repository
${SUDO} curl -ssL -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
${SUDO} sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'

# add postgresql repository
${SUDO} wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | ${SUDO} apt-key add -
${SUDO} sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -sc)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# add mariadb 10.2 repository
${SUDO} apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xF1656F24C74CD1D8
${SUDO} sh -c 'echo "deb [arch=amd64] http://mirror2.hs-esslingen.de/mariadb/repo/10.2/debian $(lsb_release -sc) main" > /etc/apt/sources.list.d/mariadb.list'
${SUDO} sh -c 'echo "deb-src http://mirror2.hs-esslingen.de/mariadb/repo/10.2/debian $(lsb_release -sc) main" >> /etc/apt/sources.list.d/mariadb.list'

${SUDO} cat << EOF > /etc/apt/preferences.d/backports.pref
Package: *
Pin: release a=stretch-backports
Pin-Priority: 450
EOF

${SUDO} cat << EOF > /etc/apt/preferences.d/pgdg.pref
Package: *
Pin: origin apt.postgresql.org
Pin-Priority: 900
EOF

${SUDO} cat << EOF > /etc/apt/preferences.d/mariadb.pref
Package: *
Pin: origin mirror2.hs-esslingen.de
Pin-Priority: 900
EOF

${SUDO} apt-get -qq update

###########################################
# install postfix for local mail delivery #
###########################################
echo "installing postfix as local MDA"
${SUDO} debconf-set-selections <<< "postfix postfix/mailname string $HOST_FQDN"
${SUDO} debconf-set-selections <<< "postfix postfix/main_mailer_type string 'local only'"
${SUDO} apt-get -qq install -y postfix


###########################
# setting up bash profile #
###########################


if [ "$WHOAMI" == "root" ]; then
	# activating aliases and color for root
	echo "activating aliases in .bashrc"
	sed -i 's/# eval "`dircolors`"/eval "`dircolors`"/' ~/.bashrc
	sed -i 's/# export LS_OPTIONS=\x27--color=auto\x27/export LS_OPTIONS=\x27--color=auto\x27/' ~/.bashrc
	sed -i 's/# alias ls=\x27ls $LS_OPTIONS\x27/alias ls=\x27ls $LS_OPTIONS\x27/' ~/.bashrc
	sed -i 's/# alias ll=\x27ls $LS_OPTIONS -l\x27/alias ll=\x27ls $LS_OPTIONS -l\x27/' ~/.bashrc
	sed -i 's/# alias l=\x27ls $LS_OPTIONS -lA\x27/alias l=\x27ls $LS_OPTIONS -lA\x27/' ~/.bashrc
	sed -i 's/# alias rm=\x27rm -i\x27/alias rm=\x27rm -i\x27/' ~/.bashrc
	sed -i 's/# alias cp=\x27cp -i\x27/alias cp=\x27cp -i\x27/' ~/.bashrc
	sed -i 's/# alias mv=\x27mv -i\x27/alias mv=\x27mv -i\x27/' ~/.bashrc
	bashrc=$(cat ~/.bashrc)
else 
	touch ~/.bashrc
	bashrc=
fi

# appending history settings if not present
if [[ "$bashrc" != *history-settings* ]]; then
	echo "appending history settings to .bashrc"
    cat files/bash/bash-history-settings.txt >> ~/.bashrc
fi

########################################################
# setting up iptables-persistent and ipset-persistent  #
########################################################

echo "installing iptables-persistent"
${SUDO} apt-get -qq -y install ipset git
${SUDO} debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
${SUDO} debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"
${SUDO} apt-get -qq -y install iptables-persistent

# cloning ipset-persistent repo from github
echo "installing ipset-persistent"
git clone -b debian https://github.com/soulsymphonies/ipset-persistent.git ipset-persistent

if [ ! -d /etc/ipset ]; then
	${SUDO} mkdir -p /etc/ipset
fi

# copy ipset-persistent service files
cd ipset-persistent
${SUDO} cp --parent etc/ipset/README /
${SUDO} cp --parent etc/default/ipset-persistent /
${SUDO} cp --parent etc/init.d/ipset-persistent /
cd ..

# creating ipset-persistent autostart
${SUDO} update-rc.d ipset-persistent defaults
# starting service
${SUDO} systemctl start ipset-persistent.service
# copy ipset configurations
${SUDO} \cp -f files/ipset/*.set /etc/ipset 
# reload configuration
${SUDO} service ipset-persistent reload

###########################
# setting up ssh service  #
###########################
echo "setting up ssh groups and service"
${SUDO} addgroup sshusers
# adding root to the sshusers group
${SUDO} adduser root sshusers
if [ "$WHOAMI" != "root" ]; then
    ${SUDO} adduser $WHOAMI sshusers
fi

# writing sshd configuration
${SUDO} mv /etc/ssh/sshd_config /etc/ssh/sshd_config_backup
${SUDO} \cp -f files/ssh/sshd_config /etc/ssh/sshd_config

##################################
# setting up iptables rules now  #
##################################
# copy config
echo "setting up iptables rules"
${SUDO} mv /etc/iptables/rules.v4 /etc/iptables/rules.v4_backup
${SUDO} mv /etc/iptables/rules.v6 /etc/iptables/rules.v6_backup
${SUDO} \cp -f files/iptables/rules.v4 /etc/iptables/rules.v4
${SUDO} \cp -f files/iptables/rules.v6 /etc/iptables/rules.v6
# reload config
${SUDO} iptables-restore < /etc/iptables/rules.v4
${SUDO} ip6tables-restore < /etc/iptables/rules.v6

###############################
# setting cron email settings #
###############################

${SUDO} sed -i "/PATH/a \\\nMAILTO='$EMAIL'" /etc/crontab
${SUDO} sed -i "/MAILTO/a CRONDARGS=-s -m off" /etc/crontab

#######################################
# Configure Postfix with Smarthost    #
#######################################

# create alias maps
if [ -f /etc/aliases ]; then
	${SUDO} mv /etc/aliases /etc/aliases_backup
fi
${SUDO} \cp -f files/aliases/aliases /etc/aliases
${SUDO} sed -i "s/name@your-email-address/$EMAIL/" /etc/aliases
${SUDO} newaliases

# create a backup of postfix config
${SUDO} \cp -f /etc/postfix/main.cf /etc/postfix/main.cf_backup

# generate generic maps to rewrite sender address from local users/services
${SUDO} cat << EOF > /etc/postfix/generic
root						$EMAIL_FROM
root@$HOSTNAME				$EMAIL_FROM
root@$HOST_FQDN				$EMAIL_FROM
root@localhost				$EMAIL_FROM
@$HOSTNAME					$EMAIL_FROM
@$HOST_FQDN					$EMAIL_FROM
@localhost					$EMAIL_FROM
EOF
${SUDO} postmap /etc/postfix/generic

# generate smtp authentication maps
if [ ! -f /etc/postfix/smtp_auth ]; then
${SUDO} cat <<EOF > /etc/postfix/smtp_auth
$SMTP_RELAY_HOST	$SMTP_RELAY_USERNAME:$SMTP_RELAY_PASSWORD
EOF
else
	${SUDO} echo -e "$SMTP_RELAY_HOST\t$SMTP_RELAY_USERNAME:$SMTP_RELAY_PASSWORD" >> /etc/postfix/smtp_auth
fi
${SUDO} postmap /etc/postfix/smtp_auth

# store contents of main.cf in variable for checks
postfix_main_cf=$(cat /etc/postfix/main.cf)

# setting generic maps, ssl, mail and smarthost options in postfix main.cf
# checking if values already exist to not duplicate values
if [[ "$postfix_main_cf" != *smtp_use_tls* ]]; then
	${SUDO} sed -i "/smtpd_use_tls/a smtp_use_tls=yes" /etc/postfix/main.cf
else
	${SUDO} sed -i "s/smtp_use_tls.*/smtp_use_tls=yes/g" /etc/postfix/main.cf
fi

if [[ "$postfix_main_cf" != *smtp_generic_maps* ]]; then
	${SUDO} sed -i "/inet_protocols/a smtp_generic_maps = hash:/etc/postfix/generic" /etc/postfix/main.cf
else
	${SUDO} sed -i "s/smtp_generic_maps.*/smtp_generic_maps = hash:/etc/postfix/generic/g" /etc/postfix/main.cf
fi

if [[ "$postfix_main_cf" != *smtp_sasl_auth_enable* ]]; then
	${SUDO} sed -i "/smtp_generic_maps/a smtp_sasl_auth_enable = yes" /etc/postfix/main.cf
else
	${SUDO} sed -i "s/smtp_sasl_auth_enable.*/smtp_sasl_auth_enable = yes/g" /etc/postfix/main.cf
fi

if [[ "$postfix_main_cf" != *smtp_sasl_password_maps* ]]; then
	${SUDO} sed -i "/smtp_sasl_auth_enable/a smtp_sasl_password_maps = hash:/etc/postfix/smtp_auth" /etc/postfix/main.cf
else
	${SUDO} sed -i "s/smtp_sasl_password_maps.*/smtp_sasl_password_maps = hash:/etc/postfix/smtp_auth/g" /etc/postfix/main.cf
fi

if [[ "$postfix_main_cf" != *smtp_sasl_security_options* ]]; then
	${SUDO} sed -i "/smtp_sasl_password_maps/a smtp_sasl_security_options = noanonymous" /etc/postfix/main.cf
else
	${SUDO} sed -i "s/smtp_sasl_security_options.*/smtp_sasl_security_options = noanonymous/g" /etc/postfix/main.cf
fi

if [[ "$postfix_main_cf" != *smtp_tls_security_level* ]]; then
	${SUDO} sed -i "/smtp_sasl_security_options/a smtp_tls_security_level = encrypt" /etc/postfix/main.cf
else
	${SUDO} sed -i "s/smtp_tls_security_level.*/smtp_tls_security_level = encrypt/g" /etc/postfix/main.cf
fi

${SUDO} sed -i "s/mydestination =.*/mydestination = localhost/g" /etc/postfix/main.cf
${SUDO} sed -i "s/inet_interfaces =.*/inet_interfaces = loopback-only/g" /etc/postfix/main.cf
${SUDO} sed -i "s/myhostname =.*/myhostname = $HOST_FQDN/g" /etc/postfix/main.cf
${SUDO} sed -i "s/relayhost =.*/relayhost = [$SMTP_RELAY_HOST]:$SMTP_RELAY_PORT/g" /etc/postfix/main.cf

# check if default_transport is present
if [[ "$postfix_main_cf" != *default_transport* ]]; then
	# if default_transport is not present, add and set it
	${SUDO} sed -i "/relayhost/a default_transport = smtp" /etc/postfix/main.cf
else
	# if default_transport is present, just set it
	${SUDO} sed -i "s/default_transport =.*/default_transport = smtp/g" /etc/postfix/main.cf
fi

# check if relay_transport is present
if [[ "$postfix_main_cf" != *relay_transport* ]]; then
	# if relay_transport is not present, add and set it
	${SUDO} sed -i "/default_transport/a relay_transport = smtp" /etc/postfix/main.cf
else
	# if relay_transport is present, just set it
	${SUDO} sed -i "s/relay_transport =.*/relay_transport = smtp/g" /etc/postfix/main.cf
fi

#reload postfix service to take new settings
${SUDO} systemctl restart postfix

##########################
# install and setup psad #
##########################
echo "setting up psad"
${SUDO} apt-get -qq -y install psad
${SUDO} mv /etc/psad/auto_dl /etc/psad/auto_dl_backup
${SUDO} \cp -f files/psad/auto_dl /etc/psad/auto_dl
${SUDO} mv /etc/psad/psad.conf /etc/psad/psad.conf_backup
${SUDO} \cp -f files/psad/psad.conf /etc/psad/psad.conf

${SUDO} sed -i "s/name@your-email-address/$EMAIL/" /etc/psad/psad.conf
${SUDO} sed -i "s/hostname.yourdomain.tld/$HOST_FQDN/" /etc/psad/psad.conf

# update psad signatures
${SUDO} psad --sig-update
# show psad status
${SUDO} psad -S

# copy signature update script
${SUDO} \cp -f files/scripts/psad-sig-update.sh /usr/local/bin/psad-sig-update.sh

echo "setting up cronjob for psad signature update"
if [ -f /var/spool/cron/crontabs/root ]; then
	cronjobs=$(cat /var/spool/cron/crontabs/root)
else
	${SUDO} touch /var/spool/cron/crontabs/root
	cronjob=
fi

if [[ "$cronjobs" != *psad-sig-update.sh* ]]; then
	(${SUDO} crontab -u root -l; ${SUDO} echo "# update psad signatures") | ${SUDO} crontab -u root -
	(${SUDO} crontab -u root -l; ${SUDO} echo "0 5 * * * /usr/local/bin/psad-sig-update.sh > /dev/null 2>&1") | ${SUDO} crontab -u root -
fi

#####################################################
# install and configure automatic software updates  #
#####################################################
${SUDO} apt-get -qq install -y unattended-upgrades apt-listchanges

# backup and copy new config file
${SUDO} mv /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades_backup
${SUDO} \cp -f files/apt/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades

# setting actual email address
${SUDO} sed -i "s/name@your-email-address/$EMAIL/" /etc/apt/apt.conf.d/50unattended-upgrades

# adjust configuration for auto upgrades and change lists
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
	${SUDO} mv /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades_backup
fi
${SUDO} \cp -f files/apt/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades

if [ -f /etc/apt/listchanges.conf ]; then
	${SUDO} mv /etc/apt/listchanges.conf /etc/apt/listchanges.conf_backup
fi
${SUDO} \cp -f files/apt/listchanges.conf /etc/apt/listchanges.conf

# finally restart ssh daemon
${SUDO} systemctl restart sshd
