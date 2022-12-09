#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

function usage(){
  echo "Usage: init.sh [KEYS]"
  echo "Available options:"
  echo "-e   expand rootfs on the hole drive"
  echo "-l   enable iptable legacy mode"
  echo "-h   help"
  echo "-d   docker and docker-compose installation"
  echo "-r   download and start containers"
  echo "-a   apps setup"
  echo "-x   delete docker and docker-compose"
}

function rootfs_expand(){
  resize2fs /dev/mmcblk1p8
}

function iptables_legacy(){
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
}

function docker_installation(){
  if [ $(dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | \
grep -c "ok installed") -eq 0 ]; then
    echo -e "\n"
    echo "==================================================="
    echo "        Docker installation                        "
    echo "==================================================="
	echo -e "\n"
    sudo apt-get update
    sudo apt-get install ca-certificates curl gnupg lsb-release -y
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update && sudo apt-get install docker-ce -y
    sudo usermod -aG docker $USER
    newgrp docker
	echo -e "\n"
    echo "==================================================="
    echo "        Docker was installed                       "
    echo "==================================================="
	echo -e "\n"
  else
    echo -e "${GREEN}Docker is already installed${NC}"
  fi
}

function docker-compose_installation(){
  if [ -x /usr/bin/docker-compose ];
  then
    echo -e "${GREEN}Docker-compose is already installed${NC}"
  else
    echo -e "\n"
    echo "==================================================="
    echo "    Docker-compose installation                    "
    echo "==================================================="
	echo -e "\n"
    sudo wget -O /usr/bin/docker-compose \
https://github.com/docker/compose/releases/download/v2.13.0\
/docker-compose-linux-$(uname -m) && sudo chmod +x /usr/bin/docker-compose
    if [ -x /usr/bin/docker-compose ]; then
      echo -e "${GREEN}[OK]${NC} Docker-compose installed sucsessfully."
	    echo -e "\n"
    else
      echo -e "${RED}[FAIL!]${NC} Docker-compose failed to install."
      exit 1
  fi
}

function check_docker-compose(){
  services=(mysql php-fpm nginx phpmyadmin)
  containers=0
  for i in ${services[@]}; do
    if [[ $(docker ps | grep touchon_$i) ]]; then
      $containers++
    fi
  done
  if [[ $containers -eq 4 ]]; then
    echo -e "${GREEN}[OK]${NC} Docker-compose containers started sucsessfully."
    containers=0
  else
    echo -e "${RED}[FAIL!]${NC} Docker-compose containers failed to start properly."
    exit 1
    containers=0
  fi
}

function setup_docker-compose(){
    git clone https://github.com/LaQuiete1988/touchon_dc.git
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[OK]${NC} Docker-compose containers are ready to start."
    else
      echo -e "${RED}[FAIL!]${NC} Docker-compose files failed to download."
      exit 1
    fi
}

function up_docker-compose(){
  if [[ ! -d touchon_dc ]]; then
    setup_docker-compose
    cd touchon_dc && docker-compose up -d && cd ..
    check_docker-compose
  else
    cd touchon_dc && docker-compose up -d && cd ..
    check_docker-compose
  fi
}

function update_docker-compose(){
  if [[ -d touchon_dc ]]; then
    cd touchon_dc && docker-compose down
    git pull origin master
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[OK]${NC} Docker-compose files were updated."
    else
      echo -e "${RED}[FAIL!]${NC} Docker-compose files failed to update."
      exit 1
    fi
    up_docker-compose
    check_docker-compose
  else
    echo -e "${RED}[FAIL!]${NC} Docker-compose containers are not installed. \
Please install them first."
    exit 1
  fi
}


function app_installation(){
  docker exec touchon_php-fpm git clone \
  https://$GIT_USERNAME:$GIT_TOKEN@github.com/VladimirDronik/adm.git \
  -b $ADM_VERSION
  docker cp touchon_dc/php-fpm/apps/. touchon_php-fpm:/var/www/adm/
  docker exec touchon_php-fpm sed -i \
  -e 's/DB_DATABASE=.*/DB_DATABASE=\${MYSQL_DATABASE}/g' \
  -e 's/DB_USERNAME=.*/DB_USERNAME=\${MYSQL_USER}/g' \
  -e 's/DB_PASSWORD=.*/DB_PASSWORD=\${MYSQL_PASSWORD}/g' \
  adm/.env
  docker exec touchon_php-fpm php adm/artisan key:generate
  docker exec touchon_php-fpm git clone \
  https://$GIT_USERNAME:$GIT_TOKEN@github.com/VladimirDronik/server.git \
  -b $CORE_VERSION
  docker exec touchon_php-fpm sed -i \
  -e 's/localhost/mysql/' \
  -e 's/127.0.0.1/php-fpm/' \
  server/include.php
  docker exec touchon_php-fpm sed -i 's/127.0.0.1/php-fpm/' server/server.php
  docker exec touchon_php-fpm sed -i \
  's/php -f thread.php/cd \".ROOT_DIR.\" \&\& php -f thread.php/' \
  server/classes/SendSocket.php
  docker exec touchon_php-fpm sed -i \
  -e "s/\$dbname =.*/\$dbname = \'\${MYSQL_DATABASE}\';/g" \
  -e "s/\$dbuser =.*/\$dbuser = \'\${MYSQL_USER}\';/g" \
  -e "s/\$dbpass =.*/\$dbpass = \'\${MYSQL_PASSWORD}\';/g" \
  server/include.php
  docker exec touchon_php-fpm \
  chown -R www-data:www-data /var/www/adm && \
  find /var/www/adm -type f -exec chmod 644 {} \+ && \
  find /var/www/adm -type d -exec chmod 755 {} \+ && \
  chmod -R ug+rwx /var/www/adm/storage /var/www/adm/bootstrap/cache && \
  ln -s /var/www/server/userscripts /var/www/adm/storage/app/scripts && \
  chown -R www-data:www-data /var/www/server/userscripts && \
  chmod -R 770 /var/www/server/userscripts
  docker exec -it touchon_php-fpm php adm/artisan migrate --seed --force
  docker exec -it touchon_php-fpm php adm/artisan create:user
}

function docker_delete(){
  apt-get purge docker-ce -y
  apt autoremove -y
  rm -rf /etc/apt/keyrings
  echo "" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  rm /usr/bin/docker-compose
  usermod touchon,adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,render,netdev,spi,i2c,gpio $USER
}

#rootfs_expand
#iptables_legacy
#docker_installation
#docker-compose_installation
#run_dc
#app_installation

if [[ ! -f .env ]]; then
  echo \
'#For GitHUB
GIT_USERNAME=
GIT_TOKEN=
ADM_VERSION=
CORE_VERSION=

#For MYSQL and app containers
MYSQL_USER=
MYSQL_DATABASE=
MYSQL_PASSWORD=
MYSQL_ROOT_PASSWORD=' \
  > .env
  echo '.env file was created. Please fill it out first.'
  exit 1
else
  sed /^[A-Z]/s/' '//g -i .env
  if [[ $(sed -n /=$/p .env | wc -l) -gt 0 ]]; then
    echo -e "Please fill out .env file"
    exit 1
  fi
  export $(grep -v '^#' .env | xargs)
fi

if [[ $# -eq 0 ]]; then
  echo -e "No keys found. "
  exit 1
fi
if [[ "${1:-unset}" == "unset" ]]; then
  echo -e "No keys found. "
  exit 1
fi

while [ -n "$1" ]
do
case "$1" in
  -e) rootfs_expand ;;
  -l) iptables_legacy ;;
  -h) usage; exit 254 ;;
  -d) docker_installation; docker-compose_installation ;;
  -r) setup_dc ;;
  -a) app_installation ;;
  -x) docker_delete ;;
  *) echo "$1 is not an option" ;;
esac
shift
done


#while getopts ":e:l:h:d:p:r:s:t:" opt; do
#	case $opt in
#		e) rootfs_expand ;;
#		l) iptables_legacy ;;
#		h) usage; exit 254 ;;
#		d) docker_installation; docker-compose_installation ;;
#		r) run_dc ;;
#		a) app_installation ;;
#	esac
#done
