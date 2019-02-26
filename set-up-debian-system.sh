#!/bin/bash
# load specific settings
source install.conf

# setting language non-interactively
LANG=en_US.UTF-8 locale-gen --purge en_US.UTF-8
echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale

WHOAMI=$(whoami)
# adding repositories
if [ "$WHOAMI" != "root" ]; then
    SUDO=sudo
fi

${SUDO} apt-get -y install apt-transport-https curl lsb-release ca-certificates software-properties-common dirmngr

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
${SUDO} sh -c 'echo "deb [arch=amd64,i386,ppc64el] http://mirror2.hs-esslingen.de/mariadb/repo/10.2/debian $(lsb_release -sc) main" > /etc/apt/sources.list.d/mariadb.list'
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

${SUDO} apt-get update

###########################################
# install postfix for local mail delivery #
###########################################
${SUDO} debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
${SUDO} debconf-set-selections <<< "postfix postfix/main_mailer_type string 'local only'"
${SUDO} apt-get install -y postfix


###########################
# setting up bash profile #
###########################

# activating aliases
sed -i 's/# alias ls=\x27ls $LS_OPTIONS\x27/alias ls=\x27ls $LS_OPTIONS\x27/' ~/.bashrc
sed -i 's/# alias ll=\x27ls $LS_OPTIONS -l\x27/alias ll=\x27ls $LS_OPTIONS -l\x27/' ~/.bashrc
sed -i 's/# alias l=\x27ls $LS_OPTIONS -lA\x27/alias l=\x27ls $LS_OPTIONS -lA\x27/' ~/.bashrc

sed -i 's/# alias rm=\x27rm -i\x27/alias rm=\x27rm -i\x27/' ~/.bashrc
sed -i 's/# alias cp=\x27cp -i\x27/alias cp=\x27cp -i\x27/' ~/.bashrc
sed -i 's/# alias mv=\x27mv -i\x27/alias mv=\x27mv -i\x27/' ~/.bashrc

# appending history settings
cat files/bash/bash-history-settings.txt >> ~/.bashrc

########################################################
# setting up iptables-persistent and ipset-persistent  #
########################################################

${SUDO} apt-get -y install ipset git
${SUDO} debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
${SUDO} debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"
${SUDO} apt-get -y install iptables-persistent

# cloning ipset-persistent repo from github
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
${SUDO} addgroup sshusers
# adding root to the sshusers group
${SUDO} adduser root sshusers
if [ "$WHOAMI" != "root" ]; then
    ${SUDO} adduser $WHOAMI sshusers
fi

# writing sshd configuration
${SUDO} mv -f /etc/ssh/sshd_config /etc/ssh/sshd_config_backup
${SUDO} \cp -f files/ssh/sshd_config /etc/ssh/sshd_config

##########################
# install and setup psad #
##########################
${SUDO} apt-get -y install psad
${SUDO} mv -f /etc/psad/auto_dl /etc/psad/auto_dl_backup
${SUDO} cp files/psad/auto_dl /etc/psad/auto_dl
${SUDO} mv -f /etc/psad/psad.conf /etc/psad/psad.conf_backup
${SUDO} cp files/psad/psad.conf /etc/psad/psad.conf

${SUDO} sed -i "s/name@your-email-address/$EMAIL/" /etc/psad/psad.conf
${SUDO} sed -i "s/hostname.yourdomain.tld/$HOSTNAME/" /etc/psad/psad.conf

##################################
# setting up iptables rules now  #
##################################
# copy config
${SUDO} mv -f /etc/iptables/rules.v4 /etc/iptables/rules.v4_backup
${SUDO} mv -f /etc/iptables/rules.v6 /etc/iptables/rules.v6_backup
${SUDO} cp files/iptables/rules.v4 /etc/iptables/rules.v4
${SUDO} cp files/iptables/rules.v6 /etc/iptables/rules.v6
# reload config
${SUDO} iptables-restore < /etc/iptables/rules.v4
${SUDO} ip6tables-restore < /etc/iptables/rules.v6