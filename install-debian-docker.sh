#!/bin/bash

# check if root, else use sudo
WHOAMI=$(whoami)
if [ "$WHOAMI" != "root" ]; then
    SUDO=sudo
fi

echo "install required dependencies"
${SUDO} apt-get -qq -y install \
	apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common > /dev/null

echo "importing docker gpg key"
curl -fsSL https://download.docker.com/linux/debian/gpg | ${SUDO} apt-key add -
	
echo "adding official docker repository"
${SUDO} add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
${SUDO} apt-get update

echo "installing docker"
${SUDO} apt-get -qq -y install docker-ce docker-ce-cli containerd.io > /dev/null

echo "installing docker-compose"
${SUDO} curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
${SUDO} chmod +x /usr/local/bin/docker-compose

echo "testing if everything worked"
docker run hello-world
docker-compose --version

echo "if you have iptables-persistent installed now updated the saved firewall rules, to include docker specifiy chains"
