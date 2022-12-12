#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

function usage(){
  echo "Usage: init.sh [KEYS]"
  echo "Available options:"
#  echo "-e   expand rootfs on the hole drive"
#  echo "-l   enable iptable legacy mode"
  echo "-h       help"
  echo "-s       docker and docker-compose installation"
  echo "-up      download and start containers"
  echo "-down    stop containers"
  echo "-upd     update containers"
  echo "-as      apps setup"
  echo "-all     docker and docker-compose installation, download and start containers, apps setup"
  echo "-x       delete docker and docker-compose"
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
    # echo "==================================================="
    # echo "        Docker installation                        "
    # echo "==================================================="
    sudo apt-get update
    sudo apt-get install ca-certificates curl gnupg lsb-release -y
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update && sudo apt-get install docker-ce -y
    sudo usermod -aG docker $USER
    reboot
    # if [ $? -eq 0 ]; then
    #   echo -e "${GREEN}[OK]${NC} Docker was installed sucsessfully."
    # else
    #   echo -e "${RED}[FAIL!]${NC} Docker failed to install."
    #   exit 1
    # fi
	  # echo -e "\n"
    # echo "==================================================="
    # echo "        Docker was installed                       "
    # echo "==================================================="
	  # echo -e "\n"
  else
    docker run hello-world
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Docker is already installed${NC}"
    else
      echo -e "${RED}[FAIL!]${NC} Docker failed to install."
      exit 1
    fi

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
    sudo wget -O /usr/bin/docker-compose https://github.com/docker/compose/releases/download/v2.13.0/docker-compose-linux-$(uname -m) \
&& sudo chmod +x /usr/bin/docker-compose
    if [ -x /usr/bin/docker-compose ]; then
      echo -e "${GREEN}[OK]${NC} Docker-compose installed sucsessfully."
	    echo -e "\n"
    else
      echo -e "${RED}[FAIL!]${NC} Docker-compose failed to install."
      exit 1
    fi
  fi
}

function reboot(){
  echo -e "Now reboot is required. You should run the script once again after reboot.\nReboot right now?"
  echo -n "Продолжить? (Y/n) "
  read item
  case "$item" in
    y|Y) sudo reboot ;;
    n|N) echo "You should reboot before you'll able to continue."; exit 1 ;;
    *) sudo reboot ;;
  esac
}

function check_docker-compose(){
  services=(mysql php-fpm nginx phpmyadmin)
  containers=0
  for i in ${services[@]}; do
    if [[ $(docker ps | grep touchon_$i) ]]; then
      containers=$((containers+1))
    fi
  done
  if [[ $containers -eq ${#services[@]} ]]; then
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

function down_docker-compose(){
  if [[ ! -d touchon_dc ]]; then
    echo -e "${RED}[FAIL!]${NC} Docker-compose containers are not installed. Please install them first."
    exit 1
  else
    cd touchon_dc && docker-compose down && cd ..
    echo -e "${GREEN}[OK]${NC} Docker-compose containers were stoped."
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
    docker-compose up -d --no-deps --build && cd ..
    check_docker-compose
  else
    echo -e "${RED}[FAIL!]${NC} Docker-compose containers are not installed. Please install them first."
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
  docker exec touchon_php-fpm chown -R www-data:www-data adm
  docker exec touchon_php-fpm find /var/www/adm -type f -exec chmod 644 {} \+
  docker exec touchon_php-fpm find /var/www/adm -type d -exec chmod 755 {} \+
  docker exec touchon_php-fpm chmod -R ug+rwx /var/www/adm/storage /var/www/adm/bootstrap/cache
  docker exec touchon_php-fpm ln -s /var/www/server/userscripts /var/www/adm/storage/app/scripts
  docker exec touchon_php-fpm chown -R www-data:www-data /var/www/server/userscripts
  docker exec touchon_php-fpm chmod -R 770 /var/www/server/userscripts
  docker exec -it touchon_php-fpm php adm/artisan migrate --seed --force
  docker exec -it touchon_php-fpm php adm/artisan create:user
}

function docker_delete(){
  sudo apt-get purge docker-ce -y
  sudo apt autoremove -y
  sudo rm -rf /etc/apt/keyrings
  echo "" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo rm /usr/bin/docker-compose
  sudo usermod -G touchon,adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,render,netdev,spi,i2c,gpio $USER
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
  # -e) rootfs_expand ;;
  # -l) iptables_legacy ;;
  -h) usage; exit 254 ;;
  -s) docker_installation; docker-compose_installation  ;;
  -up) up_docker-compose ;;
  -down) down_docker-compose ;;
  -upd) update_docker-compose ;;
  -as) app_installation ;;
  -all) docker_installation; docker-compose_installation; up_docker-compose; app_installation ;;
  -x) docker_delete ;;
  *) echo "$1 is not an option"; usage; exit 254 ;;
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
