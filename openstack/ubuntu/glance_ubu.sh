#!/bin/bash

if [[ -e ~/keystonerc ]]; then
    source ~/keystonerc
else
    echo 'Le fichier source "keystonerc" ne se trouve pas dans /root'
    exit
fi

clear

echo "Installation de Glance"
sleep 3

echo -n "Entrer le mot de passe de l'utilisateur [glance] : "
read GLANCE_USER_PASSWORD
echo "export GLANCE_USER_PASSWORD=${GLANCE_USER_PASSWORD}" >> ~/keystonerc

echo "Création de l'utilisateur [glance] dans le projet [service]"
openstack user create --domain $OS_PROJECT_DOMAIN_NAME --project service --password $GLANCE_USER_PASSWORD glance
sleep 3

echo "Ajout du rôle [admin] à l'utilisateur [glance]"
openstack role add --project service --user glance admin
sleep 3

echo "Création du service [image] pour [glance]"
openstack service create --name glance --description "OpenStack Image service" image
sleep 3

echo "Création du Enpoint (public) pour [glance]"
openstack endpoint create --region $REGION1 image public http://$IP_CONTROLLER:9292
sleep 3

echo "Création du Enpoint (interne) pour [glance]"
openstack endpoint create --region $REGION1 image internal http://$IP_CONTROLLER:9292
sleep 3

echo "Création du Enpoint (admin) pour [glance]"
openstack endpoint create --region $REGION1 image admin http://$IP_CONTROLLER:9292

echo "Création de la base de données (glance)"
echo -n "Veuillez le mot de passe pour l'accès de [glance] à la base de données (glance) : "
read GLANCE_DB_PASSWORD
echo "export GLANCE_DB_PASSWORD=${GLANCE_DB_PASSWORD}" >> ~/keystonerc

mysql -uroot -p${ROOT_DB_PASS} -e "CREATE DATABASE glance;"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on glance.* to glance@'localhost' identified by '${GLANCE_DB_PASSWORD}';"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on glance.* to glance@'%' identified by '${GLANCE_DB_PASSWORD}';"
mysql -uroot -p${ROOT_DB_PASS} -e "flush privileges;"

echo "Installation de Glance"
sleep 3
apt-get -y install glance > /dev/null

echo "Création du fichier de configuration de Glance"
sleep 3
mv /etc/glance/glance-api.conf /etc/glance/glance-api.conf.org
echo "[DEFAULT]
bind_host = 0.0.0.0

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/

[database]
# Info de connexion à MariaDB
connection = mysql+pymysql://glance:${GLANCE_DB_PASSWORD}@${IP_CONTROLLER}/glance

# Infos d'autentification à Keystone
[keystone_authtoken]
www_authenticate_uri = http://${IP_CONTROLLER}:5000
auth_url = http://${IP_CONTROLLER}:5000
memcached_servers = ${IP_CONTROLLER}:11211
auth_type = password
project_domain_name = ${OS_PROJECT_DOMAIN_NAME}
user_domain_name = ${OS_PROJECT_DOMAIN_NAME}
project_name = service
username = glance
password = ${GLANCE_USER_PASSWORD}

[paste_deploy]
flavor = keystone" > /etc/glance/glance-api.conf
chmod 640 /etc/glance/glance-api.conf
chown root:glance /etc/glance/glance-api.conf

echo "Synchronisation de [glance] avec la base de données (glance)"
sleep 3
su -s /bin/bash glance -c "glance-manage db_sync" > /dev/null
systemctl restart glance-api
systemctl enable glance-api
sleep 3
clear

echo -n "Voulez vous ajouter une image d'Ubuntu Server à des fins de tests ? (o/n) :"
read UBTEST
#while [[ $UBTEST != "o" ]] || [[ $UBTEST != "n" ]]; do
#    echo -n "Voulez vous ajouter une image d'Ubuntu Server à des fins de tests ? (o/n) :"
#    read UBTEST
#done
if [[ $UBTEST == "o" ]]; then
    mkdir -p /var/kvm/images
    echo "La version du Ubuntu Server sera la suivante :"
    echo "20.04"
    sleep 3
    wget http://cloud-images.ubuntu.com/releases/20.04/release/ubuntu-20.04-server-cloudimg-amd64.img -P /var/kvm/images
    modprobe nbd
    qemu-nbd --connect=/dev/nbd0 /var/kvm/images/ubuntu-20.04-server-cloudimg-amd64.img
    sleep 5
    mount /dev/nbd0p1 /mnt
    sleep 5
    sed -i "/disable_root:/a ssh_pwauth: true" /mnt/etc/cloud/cloud.cfg
    sed -i "/lock_passwd: True/c\     lock_passwd: False" /mnt/etc/cloud/cloud.cfg
    umount /mnt
    sleep 3
    qemu-nbd --disconnect /dev/nbd0p1
    sleep 3
    openstack image create "Ubuntu2004" --file /var/kvm/images/ubuntu-20.04-server-cloudimg-amd64.img --disk-format qcow2 --container-format bare --public
    sleep 3
    openstack image list
else
    break
fi