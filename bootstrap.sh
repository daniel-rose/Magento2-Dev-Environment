#!/usr/bin/env bash

MAGENTO_GITHUB="https://github.com/magento/magento2.git"
MAGENTO_PARENT_DIRECTORY="/var/www/"
MAGENTO_DIRECTORY="/var/www/html/"

DB_HOST="localhost"
DB_NAME="magento"
DB_USER="magento"
DB_PASSWORD="password"

BASE_URL="http://127.0.0.1:8080/"

TOOLS_DIRECTORY="/opt/tools/"

XDEBUG_CONF=$(cat <<EOF
xdebug.remote_enable = 1
xdebug.remote_connect_back = 1
xdebug.remote_port = 9000
xdebug.scream = 0 
xdebug.cli_color = 1
xdebug.show_local_vars = 1
xdebug.max_nesting_level = 500
EOF
)

FASTCGI_CONF=$(cat <<EOF
<IfModule mod_fastcgi.c>
	AddType application/x-httpd-fastphp5 .php
	Action application/x-httpd-fastphp5 /php5-fcgi
	Alias /php5-fcgi /usr/lib/cgi-bin/php5-fcgi
	FastCgiExternalServer /usr/lib/cgi-bin/php5-fcgi -socket /var/run/php5-fpm.sock -pass-header Authorization
	<Directory /usr/lib/cgi-bin>
		Require all granted
	</Directory>
</IfModule>
EOF
)

function installComposer() {
	echo "Installing Composer"
	
	cd ${TOOLS_DIRECTORY}
	curl -sS https://getcomposer.org/installer | php -- --install-dir ${TOOLS_DIRECTORY} 2> /dev/null
	ln -s ${TOOLS_DIRECTORY}composer.phar /usr/local/bin/composer
}

function installMagento2() {
	echo "Installing Magento2"

	cd ${MAGENTO_PARENT_DIRECTORY}
	rm -Rf html

	git clone ${MAGENTO_GITHUB} html
	cd html

	composer install

	chown www-data:www-data ${MAGENTO_DIRECTORY} -R
	chmod g+w ${MAGENTO_PARENT_DIRECTORY} -R

	cd bin
	sudo -u vagrant ./magento setup:install --base-url=${BASE_URL} \
	--db-host=${DB_HOST} --db-name=${DB_NAME} --db-user=${DB_USER} --db-password=${DB_PASSWORD} \
	--admin-firstname=Magento --admin-lastname=User --admin-email=user@example.com \
	--admin-user=admin --admin-password=password123 --language=de_DE \
	--currency=EUR --timezone=Europe/Berlin 
}

echo "Adding user vagrant to group www-data"
usermod -a -G www-data vagrant

echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Add multiverse repository"
apt-add-repository multiverse

echo "Updating Ubuntu-Repositories"
apt-get update 2> /dev/null

echo "Installing Git"
apt-get install git -y 2> /dev/null

echo "Installing Apache2"
apt-get install apache2-mpm-worker -y 2> /dev/null

echo "Installing PHP5-FPM & PHP5-CLI"
apt-get install libapache2-mod-fastcgi php5-fpm php5-cli -y 2> /dev/null

echo "Installing PHP extensions"
apt-get install curl php5-xdebug php-apc php5-intl php5-xsl php5-curl php5-gd php5-mcrypt php5-mysql -y 2> /dev/null

echo "Enable FastCGI-Module"
a2enmod actions fastcgi alias 2> /dev/null

echo "Enable rewrite-Module"
a2enmod rewrite 2> /dev/null

echo "Enable mcrypt-Module"
php5enmod mcrypt 2> /dev/null

echo "${FASTCGI_CONF}" > /etc/apache2/mods-enabled/fastcgi.conf

echo "Set memory limit to 512 MB"
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php5/fpm/php.ini 2> /dev/null

if ! grep -q 'xdebug.remote_enable = 1' /etc/php5/mods-available/xdebug.ini; then
	echo "${XDEBUG_CONF}" >> /etc/php5/mods-available/xdebug.ini
fi

echo "Restart PHP5-FPM"
service php5-fpm restart 2> /dev/null

echo "Restart Apache2"
service apache2 restart 2> /dev/null

echo "Installing DebConf-Utils"
apt-get install debconf-utils -y 2> /dev/null

debconf-set-selections <<< "mysql-server mysql-server/root_password password password"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password password"

echo "Installing MySQL-Server"
apt-get install mysql-server-5.6 -y 2> /dev/null

echo "Creating Database"
mysql -u root --password="password" -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password="password" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}'"
mysql -u root --password="password" -e "FLUSH PRIVILEGES"

debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean false'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2'
 
debconf-set-selections <<< 'phpmyadmin phpmyadmin/app-password-confirm password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/admin-pass password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/password-confirm password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/setup-password password password'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/database-type select mysql'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/app-pass password password'
 
debconf-set-selections <<< 'dbconfig-common dbconfig-common/mysql/app-pass password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/mysql/app-pass password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/password-confirm password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/app-password-confirm password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/app-password-confirm password password'
debconf-set-selections <<< 'dbconfig-common dbconfig-common/password-confirm password password'

echo "Installing PHPMyAdmin"
apt-get install phpmyadmin -y 2> /dev/null

if [[ ! -d ${TOOLS_DIRECTORY} ]]; then
	cd /opt
	mkdir tools
fi

if [ ! -f "/usr/local/bin/composer" ]; then
	installComposer
fi

if [ ! -f "${MAGENTO_DIRECTORY}index.php" ]; then
	installMagento2
fi