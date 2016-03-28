#!/usr/bin/env bash

GITHUB_PAT="REPLACE_THIS"

MAGENTO_PUBLIC_KEY="REPLACE_THIS"
MAGENTO_PRIVATE_KEY="REPLACE_THIS"

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

function installComposer() {
	echo "Installing Composer"
	
	cd ${TOOLS_DIRECTORY}
	curl -sS https://getcomposer.org/installer | php -- --install-dir ${TOOLS_DIRECTORY} 2> /dev/null
	ln -s ${TOOLS_DIRECTORY}composer.phar /usr/local/bin/composer
}

function installMagento2() {
	echo "Installing Magento2"

	cd ${MAGENTO_DIRECTORY}
	rm -Rf *

	chown vagrant:www-data ${MAGENTO_DIRECTORY}
	chmod g+s ${MAGENTO_DIRECTORY}

	sudo -u vagrant composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition ${MAGENTO_DIRECTORY}

	chmod g+w ${MAGENTO_DIRECTORY} -R
	chmod +x ./bin/magento

	sudo -u vagrant ./bin/magento setup:install --base-url=${BASE_URL} \
	--db-host=${DB_HOST} --db-name=${DB_NAME} --db-user=${DB_USER} --db-password=${DB_PASSWORD} \
	--admin-firstname=Magento --admin-lastname=User --admin-email=user@example.com \
	--admin-user=admin --admin-password=password123 --language=de_DE \
	--currency=EUR --timezone=Europe/Berlin --backend-frontname=admin

	sudo -u vagrant ./bin/magento deploy:mode:set developer
}

echo "Adding user vagrant to group www-data"
usermod -a -G www-data vagrant

echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Updating Ubuntu-Repositories"
apt-get update 2> /dev/null

echo "Installing Git"
apt-get install git -y 2> /dev/null

echo "Installing Apache2"
apt-get install apache2 -y 2> /dev/null

echo "Installing PHP5-FPM & PHP5-CLI"
apt-get install libapache2-mod-php5 php5-cli -y 2> /dev/null

echo "Installing PHP extensions"
apt-get install curl php5-xdebug php-apc php5-intl php5-xsl php5-curl php5-gd php5-mcrypt php5-mysql -y 2> /dev/null

echo "Enable rewrite-Module"
a2enmod rewrite 2> /dev/null

echo "Enable mcrypt-Module"
php5enmod mcrypt 2> /dev/null

echo "Set memory limit to 512 MB"
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php5/apache2/php.ini 2> /dev/null

if ! grep -q 'xdebug.remote_enable = 1' /etc/php5/mods-available/xdebug.ini; then
	echo "${XDEBUG_CONF}" >> /etc/php5/mods-available/xdebug.ini
fi

if ! grep -q '<Directory' /etc/apache2/sites-enabled/000-default.conf; then
	sed -i 's/<\/VirtualHost>/\t<Directory \/var\/www\/html>\n\t\tAllowOverride All\n\t<\/Directory>\n<\/VirtualHost>/' /etc/apache2/sites-enabled/000-default.conf
fi

echo "Restart Apache2"
service apache2 restart 2> /dev/null

echo "Installing DebConf-Utils"
apt-get install debconf-utils -y 2> /dev/null

debconf-set-selections <<< "mysql-server mysql-server/root_password password password"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password password"

echo "Installing MySQL-Server"
apt-get install mariadb-server -y 2> /dev/null

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

if [ ! -f "/home/vagrant/.composer/auth.json" ]; then
	sudo -u vagrant composer config -g http-basic.repo.magento.com ${MAGENTO_PUBLIC_KEY} ${MAGENTO_PRIVATE_KEY}
	sudo -u vagrant composer config -g github-oauth.github.com ${GITHUB_PAT}
fi

if [ ! -f "${MAGENTO_DIRECTORY}index.php" ]; then
	installMagento2
fi