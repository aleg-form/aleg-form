#!/bin/bash

if [[ -e ~/keystonerc ]]; then
    source ~/keystonerc
else
    echo 'Le fichier source "keystonerc" ne se trouve pas dans /root'
    exit
fi

echo "Création du user [nova] dnas le projet [service]"
echo -n "Veuillez entrer le mot de passe de l'utilisateur [nova] : "
read NOVA_USER_PASSWORD
echo "export NOVA_USER_PASSWORD=${NOVA_USER_PASSWORD}" >> ~/keystonerc
sleep 3
openstack user create --domain $OS_USER_DOMAIN_NAME --project service --password $NOVA_USER_PASSWORD nova
echo "Ajout de [nova] dans le rôle [admin]"
sleep 3
openstack role add --project service --user nova admin

echo "Création du user [placement] dans le projet [service]"
echo -n "Veuillez entrer le mot de passe de l'utilisateur [placement] : "
read PLACEMENT_USER_PASSWORD
echo "export PLACEMENT_USER_PASSWORD=${PLACEMENT_USER_PASSWORD}" >> ~/keystonerc
sleep 3
openstack user create --domain $OS_USER_DOMAIN_NAME --project service --password $PLACEMENT_USER_PASSWORD placement
echo "Ajout du user [placement] dans le rôle [admin]"
sleep 3
openstack role add --project service --user placement admin

echo "Création d'une entrée de service pour [nova] (compute)"
sleep 3
openstack service create --name nova --description "OpenStack Compute service" compute

echo "Création d'une entrée de service pour [placement]"
sleep 3
openstack service create --name placement --description "OpenStack Compute Placement service" placement

echo "Création d'un endpoint (public) pour [nova]"
sleep 3
openstack endpoint create --region $REGION1 compute public http://$IP_CONTROLLER:8774/v2.1/%\(tenant_id\)s

echo "Création d'un endpoint (interne) pour [nova]"
sleep 3
openstack endpoint create --region $REGION1 compute internal http://$IP_CONTROLLER:8774/v2.1/%\(tenant_id\)s

echo "Création d'un endpoint (admin) pour [nova]"
sleep 3
openstack endpoint create --region $REGION1 compute admin http://$IP_CONTROLLER:8774/v2.1/%\(tenant_id\)s

echo "Création d'un endpoint (public) pour [placement]"
sleep 3
openstack endpoint create --region $REGION1 placement public http://$IP_CONTROLLER:8778

echo "Création d'un endpoint (interne) pour [placement]"
sleep 3
openstack endpoint create --region $REGION1 placement internal http://$IP_CONTROLLER:8778

echo "Création d'un endpoint (admin) pour [placement]"
sleep 3
openstack endpoint create --region $REGION1 placement admin http://$IP_CONTROLLER:8778
sleep 5

clear

echo "Création des bases de données pour les utilisateurs [nova] et [placement]"
echo -n "Veuillez créer le mot de passe de [nova] pour la base de données (nova) : "
read NOVA_DB_PASS
echo "export NOVA_DB_PASS=${NOVA_DB_PASS}" >> ~/keystonerc
echo -n "Veuillez créer le mot de passe de [placement] pour la base de données (placement) : "
read PLACEMENT_DB_PASS
echo "export PLACEMENT_DB_PASS=${PLACEMENT_DB_PASS}" >> ~/keystonerc
sleep 3

mysql -uroot -p${ROOT_DB_PASS} -e "create database nova;"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on nova.* to nova@'localhost' identified by '${NOVA_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on nova.* to nova@'%' identified by '${NOVA_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "create database nova_api;"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on nova_api.* to nova@'localhost' identified by '${NOVA_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on nova_api.* to nova@'%' identified by '${NOVA_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "create database placement;"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on placement.* to placement@'localhost' identified by '${PLACEMENT_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on placement.* to placement@'%' identified by '${PLACEMENT_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "create database nova_cell0;"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on nova_cell0.* to nova@'localhost' identified by '${NOVA_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "grant all privileges on nova_cell0.* to nova@'%' identified by '${NOVA_DB_PASS}';"
mysql -uroot -p${ROOT_DB_PASS} -e "flush privileges;"

echo "Bases de données (nova), (nova_api), (placement), (nova_cell0) créées."
sleep 3

echo "Installation de Nova"
sleep 3
apt-get -y install nova-api nova-conductor nova-scheduler nova-novncproxy placement-api python3-novaclient > /dev/null
mv /etc/nova/nova.conf /etc/nova/nova.conf.org
echo "[DEFAULT]
# define IP address
my_ip = ${IP_CONTROLLER}
state_path = /var/lib/nova
enabled_apis = osapi_compute,metadata
log_dir = /var/log/nova
# RabbitMQ connection info
transport_url = rabbit://openstack:${KEYSTONE_DB_PASS}@${IP_CONTROLLER}

[api]
auth_strategy = keystone

# Glance connection info
[glance]
api_servers = http://${IP_CONTROLLER}:9292

[oslo_concurrency]
lock_path = $state_path/tmp

# MariaDB connection info
[api_database]
connection = mysql+pymysql://nova:${NOVA_DB_PASS}@${IP_CONTROLLER}/nova_api

[database]
connection = mysql+pymysql://nova:${NOVA_DB_PASS}@${IP_CONTROLLER}/nova

# Keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://${IP_CONTROLLER}:5000
auth_url = http://${IP_CONTROLLER}:5000
memcached_servers = ${IP_CONTROLLER}:11211
auth_type = password
project_domain_name = ${OS_USER_DOMAIN_NAME}
user_domain_name = ${OS_USER_DOMAIN_NAME}
project_name = service
username = nova
password = ${NOVA_USER_PASSWORD}

[placement]
auth_url = http://${IP_CONTROLLER}:5000
os_region_name = ${REGION1}
auth_type = password
project_domain_name = ${OS_USER_DOMAIN_NAME}
user_domain_name = ${OS_USER_DOMAIN_NAME}
project_name = service
username = placement
password = ${PLACEMENT_USER_PASSWORD}

[wsgi]
api_paste_config = /etc/nova/api-paste.ini" > /etc/nova/nova.conf

chmod 640 /etc/nova/nova.conf
chgrp nova /etc/nova/nova.conf

mv /etc/placement/placement.conf /etc/placement/placement.conf.org
echo "[DEFAULT]
debug = false

[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://${IP_CONTROLLER}:5000
auth_url = http://${IP_CONTROLLER}:5000
memcached_servers = ${IP_CONTROLLER}:11211
auth_type = password
project_domain_name = ${OS_USER_DOMAIN_NAME}
user_domain_name = ${OS_USER_DOMAIN_NAME}
project_name = service
username = placement
password = ${PLACEMENT_USER_PASSWORD}

[placement_database]
connection = mysql+pymysql://placement:${PLACEMENT_DB_PASS}@${IP_CONTROLLER}/placement" > /etc/placement/placement.conf
chmod 640 /etc/placement/placement.conf
chgrp placement /etc/placement/placement.conf
clear

echo "Synchronisation des Bases de données avec [nova] et [placement]"
sleep 3
echo "[placement] <=> (placement)"
sleep 3
su -s /bin/bash placement -c "placement-manage db sync"
echo "[nova] <=> (nova_api)"
sleep 5
su -s /bin/bash nova -c "nova-manage api_db sync"
sleep 3
echo "[nova] <=> (nova_cell0)"
sleep 5
su -s /bin/bash nova -c "nova-manage cell_v2 map_cell0"
sleep 3
echo "[nova] <=> (nova)"
sleep 5
su -s /bin/bash nova -c "nova-manage db sync"
sleep 3
echo "Création de la cellule cell1"
su -s /bin/bash nova -c "nova-manage cell_v2 create_cell --name cell1"
sleep 3
echo "Redémarrage de Apache2, nova-api, nova-conductor, nova-scheduler, nova-novncproxy"
systemctl restart apache2
sleep 3
for service in api conductor scheduler novncproxy; do
systemctl restart nova-$service
done
echo "Redémarrage terminé"
sleep 3
clear
echo 'Liste des services "compute"'
openstack compute service list
sleep 5
echo "La suite de l'installation de Nova sevra se faire sur un autre noeud 'network'
Vous pouvez d'or et déjà envoyer le fichier keystonerc sur le noeud en question
si vous connaissez son adresse ip et nécessite un accès root en SSH sur ce dernier."
while true
do
    read -r -p "Désirez-vous procéder ainsi ? (o/n) : " sendrc
    case $sendrc in
        [o/O][u/U][i/I]|[o/O])
    read -p "Veuillez entrer l'adresse IP du noeud Network : " IP_NETWORK_NODE
    echo "export IP_NETWORK_NODE=${IP_NETWORK_NODE}" >> ~/keystonerc
    scp ~/keystonerc root@$IP_NETWORK_NODE:/root
    break
    ;;
        [n/N][o/O][i/N]|[n/N])
    break
    ;;
        *)
    echo "Entrée invalide..."
    ;;
    esac
done

exit

