#!/bin/bash

# Script permettant l'installation de Keystone sur le Noeud de contrôle

db_name=keystone
db_user=keystone
hostnm=$(hostname -A)
ipaddr=$(ip a | grep global | awk '{print $2}' | cut -d'/' -f1)

echo "Mise à jour de l'OS"
sleep 3

apt-get update -y > /dev/null
apt-get upgrade -y > /dev/null

sed -i '/#NTP=/c\NTP=1.fr.pool.ntp.org' /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd
clear
echo "Vérification de la synchronisation au serveur de temps"
sleep 3
timedatectl timesync-status
sleep 3
clear

echo "Installation et première configuration de Mariadb"
sleep 3
apt-get -y install mariadb-server > /dev/null

CHECK_CHAR_DB1=$(cat /etc/mysql/mariadb.conf.d/50-server.cnf | grep character-set-server | awk '{print $3}')
CHECK_CHAR_DB2=$(cat /etc/mysql/mariadb.conf.d/50-server.cnf | grep collation-server | awk '{print $3}')
CHECK_BIND=$(cat /etc/mysql/mariadb.conf.d/50-server.cnf | grep bind-address | awk '{print $3}')

if [[ $CHECK_CHAR_DB1 != "utf8mb4" ]]; then
    sed -i '/character-set-server/c\character-set-server = utf8mb4' /etc/mysql/mariadb.conf.d/50-server.cnf
fi

if [[ $CHECK_CHAR_DB2 != "utf8mb4_general_ci" ]]; then
    sed -i '/collation-server/c\collation-server = utf8mb4_general_ci' /etc/mysql/mariadb.conf.d/50-server.cnf
fi

if [[ $CHECK_BIND != "0.0.0.0" ]]; then
    sed -i '/bind-address/c\bind-address = 0.0.0.0' /etc/mysql/mariadb.conf.d/50-server.cnf
fi

sed -i '/#max_connections/c\max_connections = 500' /etc/mysql/mariadb.conf.d/50-server.cnf

echo -n 'Veuillez Choisir un mot de passe pour "root" dans Mariadb : '
read passroot1
echo -n 'Tapez à nouveau ce mot de passe : '
read passroot2
while [[ $passroot1 != $passroot2 ]]; do
    echo "Les mots de passe ne correspondent pas."
    echo -n 'Choisir un mot de passe pour "root" dans Mariadb : '
    read passroot1
    echo -n 'Tapez à nouveau ce mot de passe : '
    read passroot2
done
passroot=$passroot1

# Execution de "mysql_secure_installation"
mysqladmin -u root password "$passroot"
mysql -u root -p"$passroot" -e "UPDATE mysql.user SET Password=PASSWORD('$passroot') WHERE User='root'"
mysql -u root -p"$passroot" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -u root -p"$passroot" -e "DELETE FROM mysql.user WHERE User=''"
mysql -u root -p"$passroot" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
mysql -u root -p"$passroot" -e "FLUSH PRIVILEGES"

systemctl enable mariadb
systemctl restart mariadb

echo "MariaDB installé"
sleep 3
clear

echo "Installation et configuration du pack Openstack Wallaby"
sleep 3

apt-get -y install software-properties-common > /dev/null
yes "" | add-apt-repository cloud-archive:wallaby
sleep 3
apt-get update > /dev/null
apt-get -y upgrade > /dev/null

echo "Installation et configuration de RabbitMQ, Memcached et PyMysql"
apt-get -y install rabbitmq-server memcached python3-pymysql > /dev/null
rabbitmqctl add_user openstack password
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
sed -i '/-l 127.0.0.1/c\-l 0.0.0.0' /etc/memcached.conf

systemctl restart mariadb rabbitmq-server memcached
clear

echo "Création de la base de données $db_name"
echo -n "Veuillez entrer le mot de passe de l'utilisateur $db_user 
sur la base de données $db_name : "
read db_pass
mysql -uroot -p${passroot} -e "CREATE DATABASE ${db_name};"
mysql -uroot -p${passroot} -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
mysql -uroot -p${passroot} -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'%' IDENTIFIED BY '${db_pass}';"
mysql -uroot -p${passroot} -e "FLUSH PRIVILEGES;"
echo "base de données $db_name créée."
sleep 3

echo "Installation et configuration de Keystone, cela peut être long..."
sleep 3

apt-get -y install keystone python3-openstackclient apache2 libapache2-mod-wsgi-py3 python3-oauth2client > /dev/null
sed -i "/#memcache_servers = localhost:11211/c\memcache_servers = ${ipaddr}:11211" /etc/keystone/keystone.conf
sed -i "/connection = sqlite:/c\connection = mysql+pymysql://${db_user}:${db_pass}@${ipaddr}/keystone" /etc/keystone/keystone.conf
sed -i "/#provider = fernet/c\provider = fernet" /etc/keystone/keystone.conf

echo "Synchronisation de la base de données : Etape 1"
sleep 3
su -s /bin/bash keystone -c "keystone-manage db_sync"
echo "Synchronisation de la base de données : Etape 2"
sleep 3
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
echo "Synchronisation terminée"
sleep 3
clear
echo -n "Veuillez saisir le mot de passe administrateur de Keystone : "
read keyadminpass
echo -n "Veuillez saisir le nom de la région que vous voulez configurer : "
read region
echo "Installation en cours, Veuillez patienter."
keystone-manage bootstrap --bootstrap-password $keyadminpass \
--bootstrap-admin-url http://$ipaddr:5000/v3/ \
--bootstrap-internal-url http://$ipaddr:5000/v3/ \
--bootstrap-public-url http://$ipaddr:5000/v3/ \
--bootstrap-region-id $region

echo "Lancement du serveur Apache"
sleep 3

sed -i "/^#ServerRoot/a ServerName ${hostnm}" /etc/apache2/apache2.conf

echo "Création du fichier source permettant d'utiliser Keystone : keystonerc.
Ce fichier se trouvera dans le dossier suivant :"
pwd
sleep 5

echo "export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${keyadminpass}
export OS_AUTH_URL=http://${ipaddr}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export PS1='[\u@\h \W(keystone)]\$ '
###########################################
export ROOT_DB_PASS=${passroot}
export IP_CONTROLLER=${ipaddr}
export REGION1=${region}
export KEYSTONE_DB_PASS=${db_pass}" > ~/keystonerc
chmod 600 ~/keystonerc
echo "source ~/keystonerc " >> ~/.bash_profile

if [[ -e ~/keystonerc ]]; then
    source ~/keystonerc
else
    echo 'Le fichier source "keystonerc" ne se trouve pas dans /root'
    exit
fi

echo "Création du projet [Service]"

openstack project create --domain $OS_PROJECT_DOMAIN_NAME --description "Service Project" service
openstack project list
sleep 5

exit