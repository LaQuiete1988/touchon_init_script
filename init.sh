#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[33m'
NC='\033[0m'

function usage(){
  echo "Usage: init.sh [OPTION]"
  echo "Available options:"
  echo "--help, -h    help"
  echo "--up          download and start containers"
  echo "--down        stop containers"
  echo "--ps          containers' status"
  echo "--cupd        update containers"
  echo "--setup       docker and docker-compose installation, download and start containers, apps setup"
  if [[ ! -d touchon_dc ]]; then
    echo -e "\nRun   ${YELLOW}./init --setup${NC}   first to configurate system.\n"
  fi
}

function rootfs_expand(){
  resize2fs /dev/mmcblk1p8
}

function iptables_legacy(){
  update-alternatives --set iptables /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
}

function docker_installation(){
  if [[ -e /var/run/docker.sock ]]; then
    docker run hello-world
    if [ $? -eq 0 ]; then
      echo -e "\n${GREEN}[INFO]${NC} Docker is already installed.\n"
    else
      echo -e "\n${RED}[FAIL]${NC} Docker failed to install.\n"
      exit 1
    fi
  else
    sudo apt-get update && sudo apt-get install ca-certificates curl gnupg lsb-release -y
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(lsb_release -is)/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(lsb_release -is) \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update && sudo apt-get install docker-ce -y
    sudo groupadd docker
    sudo usermod -aG docker $USER
    add_startup_script
    reboot
  fi
}

function docker-compose_installation(){
  if [ -x /usr/bin/docker-compose ];
  then
    echo -e "\n${GREEN}[INFO]${NC} Docker-compose is already installed.\n"
  else
    sudo wget -O /usr/bin/docker-compose https://github.com/docker/compose/releases/download/v2.13.0/docker-compose-linux-$(uname -m) \
&& sudo chmod +x /usr/bin/docker-compose
    if [ -x /usr/bin/docker-compose ]; then
      echo -e "\n${GREEN}[INFO]${NC} Docker-compose installed sucsessfully.\n"
    else
      echo -e "\n${RED}[FAIL]${NC} Docker-compose failed to install.\n"
      exit 1
    fi
  fi
}

function reboot(){
  echo -e "\n${YELLOW}[CAUTION]${NC} Now reboot is required. Script will continue after your next login.\nReboot right now?"
  echo -n "Continue? (Y/n) "
  read item
  case "$item" in
    y|Y) sudo reboot ;;
    n|N) echo -e "\n${RED}[WARNING]${NC} You should reboot. Script will continue after your next login.\n"; exit 1 ;;
    *) sudo reboot ;;
  esac
}

function add_startup_script(){
  echo \
'#!/usr/bin/env bash
cd /home/touchon/touchon_init_script
./init.sh --setup
sudo rm /etc/profile.d/startup.sh' | sudo tee /etc/profile.d/startup.sh > /dev/null
  sudo chmod +x /etc/profile.d/startup.sh
}

function check_startup_script(){
  if [[ -e /etc/profile.d/startup.sh ]]; then
    echo -e "\n${RED}[WARNING]${NC} You should reboot. Script will continue after your next login.\n"
    exit 1
  fi
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
    echo -e "\n${GREEN}[INFO]${NC} Docker-compose containers started sucsessfully.\n"
    containers=0
  else
    echo -e "\n${RED}[FAIL]${NC} Docker-compose containers failed to start properly.\n"
    exit 1
    containers=0
  fi
}

function setup_docker-compose(){
    git clone https://github.com/LaQuiete1988/touchon_dc.git
    if [ $? -eq 0 ]; then
      echo -e "\n${GREEN}[INFO]${NC} Docker-compose containers are ready to start.\n"
    else
      echo -e "\n${RED}[FAIL]${NC} Docker-compose files failed to download.\n"
      exit 1
    fi
}

function down_docker-compose(){
  if [[ ! -d touchon_dc ]]; then
    echo -e "\n${RED}[FAIL]${NC} Docker-compose containers are not installed. Please install them first.\n"
    exit 1
  else
    cd touchon_dc && docker-compose down && cd ..
    echo -e "\n${GREEN}[INFO]${NC} Docker-compose containers were stoped.\n"
  fi
}

function up_docker-compose(){
  if [[ -e /var/run/docker.sock ]]; then
    if [[ ! -d touchon_dc ]]; then
      setup_docker-compose
      cd touchon_dc && docker-compose up -d && cd ..
      check_docker-compose
    else
      cd touchon_dc && docker-compose up -d && cd ..
      check_docker-compose
    fi
  else
    echo -e "\n${RED}[FAIL]${NC} Install docker first. Run\n\n     ./init.sh --setup\n"
    exit 1
  fi
}

function status_docker-compose(){
  if [[ ! -d touchon_dc ]]; then
    echo -e "\n${RED}[FAIL]${NC} Docker-compose containers are not installed. Please install them first.\n"
    exit 1
  else
    cd touchon_dc && docker-compose ps && cd ..
  fi
}

function update_docker-compose(){
  if [[ -d touchon_dc ]]; then
    cd touchon_dc && docker-compose down
    git pull origin master
    if [ $? -eq 0 ]; then
      echo -e "\n${GREEN}[INFO]${NC} Docker-compose files were updated.\n"
    else
      echo -e "\n${RED}[FAIL]${NC} Docker-compose files failed to update.\n"
      exit 1
    fi
    docker-compose up -d --no-deps --build && cd ..
    check_docker-compose
  else
    echo -e "\n${RED}[FAIL]${NC} Docker-compose containers are not installed. Please install them first.\n"
    exit 1
  fi
}


function app_installation(){
  docker exec touchon_php-fpm git clone https://$GIT_USERNAME:$GIT_TOKEN@github.com/VladimirDronik/adm.git -b $ADM_VERSION
  docker cp touchon_dc/php-fpm/apps/. touchon_php-fpm:/var/www/adm/
  docker exec touchon_php-fpm sed -i \
-e 's/DB_DATABASE=.*/DB_DATABASE=\${MYSQL_DATABASE}/g' \
-e 's/DB_USERNAME=.*/DB_USERNAME=\${MYSQL_USER}/g' \
-e 's/DB_PASSWORD=.*/DB_PASSWORD=\${MYSQL_PASSWORD}/g' \
adm/.env
  docker exec touchon_php-fpm php adm/artisan key:generate
  docker exec touchon_php-fpm git clone https://$GIT_USERNAME:$GIT_TOKEN@github.com/VladimirDronik/server.git -b $CORE_VERSION
  docker exec touchon_php-fpm sed -i \
-e 's/localhost/mysql/' \
-e 's/127.0.0.1/php-fpm/' \
-e "s/\$dbname =.*/\$dbname = \'\${MYSQL_DATABASE}\';/g" \
-e "s/\$dbuser =.*/\$dbuser = \'\${MYSQL_USER}\';/g" \
-e "s/\$dbpass =.*/\$dbpass = \'\${MYSQL_PASSWORD}\';/g" \
server/include.php
  docker exec touchon_php-fpm sed -i 's/127.0.0.1/php-fpm/' server/server.php
  docker exec touchon_php-fpm sed -i 's/php -f thread.php/cd \".ROOT_DIR.\" \&\& php -f thread.php/' server/classes/SendSocket.php
  docker exec touchon_php-fpm chown -R www-data:www-data adm
  docker exec touchon_php-fpm find /var/www/adm -type f -exec chmod 644 {} \+
  docker exec touchon_php-fpm find /var/www/adm -type d -exec chmod 755 {} \+
  docker exec touchon_php-fpm chmod -R ug+rwx /var/www/adm/storage /var/www/adm/bootstrap/cache
  docker exec touchon_php-fpm ln -s /var/www/server/userscripts /var/www/adm/storage/app/scripts
  docker exec touchon_php-fpm chown -R www-data:www-data /var/www/server/userscripts
  docker exec touchon_php-fpm chmod -R 770 /var/www/server/userscripts
  docker exec -it touchon_php-fpm php adm/artisan migrate --seed --force
  echo -e "\n${YELLOW}[CAUTION]${NC} Please create admin panel superuser.\n"
  docker exec -it touchon_php-fpm php adm/artisan create:user
  echo -e "\n"
  echo -e "====================================================================="
  echo -e "                    ${GREEN}Congrats! Everything is ready${NC}               "
  echo -e "====================================================================="
  echo -e "\n\n\n"
}

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
  echo -e "\n${YELLOW}[CAUTION]${NC} .env file was created. Please fill it out first.\n"
  exit 1
else
  sed /^[A-Z]/s/' '//g -i .env
  if [[ $(sed -n /=$/p .env | wc -l) -gt 0 ]]; then
    echo -e "\n${YELLOW}[CAUTION]${NC} Please fill out .env file\n"
    exit 1
  fi
  export $(grep -v '^#' .env | xargs)
fi

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi
if [[ "${1:-unset}" == "unset" ]]; then
    usage
    exit 1
fi

while [ -n "$1" ]
do
case "$1" in
  --help) usage; exit 1 ;;
  -h) usage; exit 1 ;;
  --up) up_docker-compose ;;
  --down) down_docker-compose ;;
  --ps) status_docker-compose ;;
  --cupd) update_docker-compose ;;
  --setup) docker_installation; docker-compose_installation; up_docker-compose; app_installation ;;
  *) echo "$1 is not an option"; usage; exit 1 ;;
esac
shift
done
