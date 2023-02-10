#!/bin/bash
# By Tra Viet
# Selinux and Firewall turn off before run this

#Set Time
timedatectl set-timezone Asia/Ho_Chi_Minh
timedatectl set-ntp 1

# Change hostname
sed -i '2d' /etc/hosts
sed -i '3 i 127.0.1.1       icinga.fptgroup.com icinga' /etc/hosts
sed -i '4 i 10.10.100.164   icinga.fptgroup.com icinga' /etc/hosts
hostnamectl set-hostname icinga


# Statics Ip set up

sed -i '5d' /etc/netplan/00-installer-config.yaml
sed -i '5 i \      addresses:' /etc/netplan/00-installer-config.yaml
sed -i '6 i \      - 10.10.100.164/24' /etc/netplan/00-installer-config.yaml
sed -i '7 i \      gateway4: 10.10.100.1' /etc/netplan/00-installer-config.yaml
sed -i '8 i \      nameservers:' /etc/netplan/00-installer-config.yaml
sed -i '9 i \        addresses:' /etc/netplan/00-installer-config.yaml
sed -i '10 i \        - 8.8.8.8' /etc/netplan/00-installer-config.yaml
sed -i '11 i \        - 10.10.100.100' /etc/netplan/00-installer-config.yaml
sed -i '12 i \        - 10.10.100.101' /etc/netplan/00-installer-config.yaml

sudo netplan apply

sleep 3

# Update && Upgrade Ubuntu
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install curl apt-transport-https wget gnupg apache2 apache2-utils -y

sleep 3

#Install PHP for Icinga
sudo apt install -y php php-{common,mysql,xml,xmlrpc,curl,gd,imagick,cli,dev,imap,mbstring,opcache,soap,zip,intl}
sudo apt install -y php php-{cgi,mbstring,net-socket,bcmath} libapache2-mod-php php-xml-util

sleep 3

# Download Icinga2

wget -O - https://packages.icinga.com/icinga.key | apt-key add -

sudo apt-get update

. /etc/os-release; if [ ! -z ${UBUNTU_CODENAME+x} ]; then DIST="${UBUNTU_CODENAME}"; else DIST="$(lsb_release -c| awk '{print $2}')"; fi;
echo "deb https://packages.icinga.com/ubuntu icinga-${DIST} main" | sudo tee /etc/apt/sources.list.d/${DIST}-icinga.list
echo "deb-src https://packages.icinga.com/ubuntu icinga-${DIST} main" | sudo tee -a /etc/apt/sources.list.d/${DIST}-icinga.list
sudo apt-get update

# Install Icinga 2
sudo apt-get install icinga2 -y

# Install monitoring-plugins
sudo apt-get install monitoring-plugins -y
systemctl enable --now icinga2
systemctl start icinga2


# Install monitoring-plugins
sudo apt install icinga2-ido-mysql -y
systemctl restart icinga2

sleep 3

# Download and Install MariaDB
sudo apt update
sudo apt install software-properties-common -y
curl -LsS -O https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=10.7
sudo bash mariadb_repo_setup --mariadb-server-version=10.7
sudo apt update
sudo apt -y install mariadb-common mariadb-server mariadb-client
sudo systemctl enable mariadb
sudo systemctl start mariadb

sleep 3

# Type Y/n follow the question below
mysql_secure_installation <<EOF
y
y
icingafptgroup
icingafptgroup
y
y
y
y
EOF

mysql -u root -p <<EOF
create database icingadb;
grant all privileges on icingadb.* to icingadb@localhost identified by 'icingafptgroup';
Flush Privileges;
exit
EOF

sudo mysql -u root -p icingadb < /usr/share/icinga2-ido-mysql/schema/mysql.sql

sleep 3

sed -i '9d' /etc/icinga2/features-available/ido-mysql.conf
sed -i '9 i \  user = "icingadb", ' /etc/icinga2/features-available/ido-mysql.conf 
sed -i '10d' /etc/icinga2/features-available/ido-mysql.conf
sed -i '10 i \  password = "icingafptgroup", ' /etc/icinga2/features-available/ido-mysql.conf 
sed -i '12d' /etc/icinga2/features-available/ido-mysql.conf
sed -i '12 i \  database = "icingadb", ' /etc/icinga2/features-available/ido-mysql.conf

sudo icinga2 feature enable ido-mysql
sudo systemctl restart icinga2

# Rest API
sudo icinga2 api setup

sleep 3

sudo cat << EOF > /etc/icinga2/conf.d/api-users.conf
/**
 * The ApiUser objects are used for authentication against the API.
 */
object ApiUser "root" {
  password = "83ff8c29d31e8c85"
  // client_cn = ""

  permissions = [ "*" ]
}

/**
 * The ApiUser objects are used for authentication against the API.
 */
object ApiUser "icingaweb2" {
  password = "icingafptgroup"
  permissions = [ "status/query", "actions/*", "objects/modify/*", "objects/query/*" ]
}
EOF

sudo systemctl restart icinga2

sleep 3

# Install Icinga-Web2
sudo apt install icingaweb2 icingacli -y

mysql -u root -p <<EOF
create database icingaweb2;
grant all privileges on icingaweb2.* to icingaweb2@localhost identified by 'icingafptgroup';
Flush Privileges;
exit
EOF

# Set up SSL for HTTPS
sed -i '395 i [ icinga.fptgroup.com ]' /etc/ssl/openssl.cnf
sed -i '396 i subjectAltName = DNS:icinga.fptgroup.com' /etc/ssl/openssl.cnf

sleep 3
# Generate SSL Key
openssl genrsa -aes128 2048 > /etc/ssl/private/icinga.key
openssl rsa -in /etc/ssl/private/icinga.key -out /etc/ssl/private/icinga.key
openssl req -utf8 -new -key /etc/ssl/private/icinga.key -out /etc/ssl/private/icinga.csr << EOF

VN
Ho Chi Minh
Ho Chi Minh
FPTGroup
icinga
icinga.fptgroup.com
icinga@icinga.fptgroup.com
icingafptgroup
FPTGroup
EOF

openssl x509 -in /etc/ssl/private/icinga.csr -out /etc/ssl/private/icinga.crt -req -signkey /etc/ssl/private/icinga.key -extfile /etc/ssl/openssl.cnf -extensions icinga.fptgroup.com -days 3650

chmod 644 /etc/ssl/private/icinga.key

sleep 3

sudo cat << EOF > /etc/apache2/sites-available/icinga.fptgroup.com.conf 
<VirtualHost *:80> 
    ServerName icinga.fptgroup.com
    ServerAlias www.icinga.fptgroup.com
    Redirect permanent / https://icinga.fptgroup.com
</VirtualHost>

<VirtualHost *:443>

    ServerName icinga.fptgroup.com
    ServerAlias www.icinga.fptgroup.com
    ServerAdmin admin@icinga.fptgroup.com
    DocumentRoot "/usr/share/icingaweb2/public"

    ErrorLog ${APACHE_LOG_DIR}/www.icinga.fptgroup.com_error.log
    CustomLog ${APACHE_LOG_DIR}/www.icinga.fptgroup.com_access.log combined

    SSLEngine on
    SSLCertificateFile /etc/ssl/private/icinga.crt
    SSLCertificateKeyFile /etc/ssl/private/icinga.key

   <Directory "/usr/share/icingaweb2/public">
      Options FollowSymlinks
      AllowOverride All
      Require all granted
      SetEnv ICINGAWEB_CONFIGDIR "/etc/icingaweb2"

      EnableSendfile Off

      <IfModule mod_rewrite.c>
          RewriteEngine on
          # modified base
          RewriteBase /
          RewriteCond %{REQUEST_FILENAME} -s [OR]
          RewriteCond %{REQUEST_FILENAME} -l [OR]
          RewriteCond %{REQUEST_FILENAME} -d
          RewriteRule ^.*$ - [NC,L]
          RewriteRule ^.*$ index.php [NC,L]
      </IfModule>

      <IfModule !mod_rewrite.c>
          DirectoryIndex error_norewrite.html
          ErrorDocument 404 /error_norewrite.html
      </IfModule>
   </Directory>

</VirtualHost>
EOF

sleep 3

sudo a2enmod ssl
sudo a2dissite 000-default.conf
sudo a2ensite icinga.fptgroup.com.conf
sudo apache2ctl configtest
sudo systemctl reload apache2

# Master - Client Icinga
sudo icinga2 node wizard

#sudo icinga2 pki ticket --cn 'ws22'
# Create Zone for Master
sudo mkdir -p /etc/icinga2/zones.d/icinga.fptgroup.com/
# sudo cat << EOF > /etc/icinga2/zones.d/icinga.fptgroup.com/icinga.fptgroup.com.conf
# // Endpoints
# object Endpoint "w22" {
# }
# // Zones
# object Zone "w22" {
#     endpoints = [ "w22" ]
#     parent = "icinga.fptgroup.com"
# }
# // Host Objects
# object Host "w22" {
#     check_command = "hostalive"
#     address = "10.10.100.100"
#     vars.client_endpoint = name
# }
# EOF

# Configure File 
sudo cat << EOF > /etc/icinga2/zones.d/icinga.fptgroup.com/services.conf
// Ping
 apply Service "Ping" {
 check_command = "ping4"
 assign where host.address // check executed on master
 }
 // System Load
 apply Service "System Load" {
 check_command = "load"
 command_endpoint = host.vars.client_endpoint // Check executed on client01
 assign where host.vars.client_endpoint
 }
 // SSH Service
 apply Service "SSH Service" {
 check_command = "ssh"
 command_endpoint = host.vars.client_endpoint
 assign where host.vars.client_endpoint
 }
 // Icinga 2 Service
 apply Service "Icinga2 Service" {
 check_command = "icinga"
 command_endpoint = host.vars.client_endpoint
 assign where host.vars.client_endpoint
 }
EOF

sudo icinga2 daemon -C
sudo systemctl restart icinga2
# sudo icingacli setup token create

# Allow Firewall Port Forward
sudo ufw allow proto tcp from any to any port 80,443,5665,22
sudo ufw allow proto tcp from 10.10.100.161 to any port 10050,10051
sudo ufw allow proto tcp from 10.10.100.162 to any port 9115
sudo ufw enable


sudo passwd user <<EOF
Fpt@@123
Fpt@@123
EOF

