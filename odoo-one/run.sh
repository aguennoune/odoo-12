#!/bin/bash
DESTINATION=$1
PORT=$2
CHAT=$3
# clone Odoo directory
git clone --depth=1 https://github.com/aguennoune/odoo-12/odoo-one $DESTINATION
rm -rf $DESTINATION/.git
# set permission
mkdir -p $DESTINATION/config
mkdir -p $DESTINATION/pgdata
sudo chmod -R 777 $DESTINATION
# config
if grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then echo $(grep -F "fs.inotify.max_user_watches" /etc/sysctl.conf); else echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf; fi
sudo sysctl -p
sed -i 's/10012/'$PORT'/g' $DESTINATION/docker-compose.yml
sed -i 's/20012/'$CHAT'/g' $DESTINATION/docker-compose.yml
# run Odoo
docker-compose -f $DESTINATION/docker-compose.yml up -d

echo 'Started Odoo @ http://localhost:'$PORT' | Live chat port: '$CHAT
