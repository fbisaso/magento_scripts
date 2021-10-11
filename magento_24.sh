#!/bin/bash

# USAGE INSTRUCTIONS
# Run the script on a fresh UBUNTU 20 installation
# After the script executes go to: http://{your-ip-address} 


readonly DB_NAME="magento"
readonly DB_USER="mageuser"
readonly DB_PASSWORD="password123"
readonly MAGENTO_ADMIN_USER="admin"
readonly MAGENTO_ADMIN_PASSWORD="magentorocks1"
readonly WEB_ROOT="/var/www/html"

update_packages () {
	sudo apt-get update -y && sudo apt-get upgrade -y
}

install_elastic_search () {
	sudo apt-get install openjdk-8-jdk -y
	curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
	echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
	sudo apt update
	sudo apt install elasticsearch -y
}

install_lamp_stack (){
	echo -e "\n\nInstalling Apache2 Web server\n"
	sudo apt-get install apache2 -y

	echo -e "\n\nInstalling PHP & Requirements\n"
	sudo apt-get install php7.4 php7.4-cli php7.4-json php7.4-common php7.4-mysql php7.4-zip php7.4-gd php7.4-mbstring php7.4-curl php7.4-xml php7.4-bcmath php7.4-soap php7.4-intl -y

	echo -e "\n\nInstalling MySQL\n"
	sudo apt-get install mysql-server mysql-client -y
	sudo service mysql restart

	echo -e "\n\n Changing Permissions for /var/www\n"
	sudo chown -R www-data:www-data /var/www
	echo -e "\n Permissions have been set\n"

	echo -e "\n\nEnabling Modules\n"
	sudo a2enmod rewrite
	sudo a2enmod proxy_http
	sudo phpenmod mcrypt

	echo -e "\n\nRestarting Apache\n"
	sudo service apache2 restart

	echo -e "\n\nLAMP Installation Completed"
}

configure_elastic_search () {
	readonly ES_CONF="/etc/apache2/sites-available/elasticsearch.conf"
	sudo touch "${ES_CONF}"
	sudo echo -e "<VirtualHost *:8080>" > "${ES_CONF}"
	sudo echo -e "\tProxyPass \"/\" \"http://localhost:9200/\"" >> "${ES_CONF}"
	sudo echo -e "\tProxyPassReverse \"/\" \"http://localhost:9200/\"" >> "${ES_CONF}"
	sudo echo -e "</VirtualHost>" >> "${ES_CONF}"

	sudo a2ensite elasticsearch.conf
	sudo service apache2 restart
	sudo service elasticsearch restart
}

setup_database () {
	echo "Setting up database\n"
	readonly Q1="DROP DATABASE IF EXISTS ${DB_NAME};"
	readonly Q2="DROP USER IF EXISTS '${DB_USER}'@'localhost';"
	readonly Q3="CREATE DATABASE ${DB_NAME};"
	readonly Q4="CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
	readonly Q5="GRANT ALL ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
	readonly Q6="FLUSH PRIVILEGES;"
	readonly SQL="${Q1}${Q2}${Q3}${Q4}${Q5}${Q6}"

	sudo mysql -uroot -e "$SQL"

	echo "Database has been created \n"
}

install_composer () {
	echo "Installing Composer\n"
	curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

download_magento () {
	echo "Installing zip/unzip\n"
	sudo apt install unzip -y

	echo "Moving to Web Root"
	cd "${WEB_ROOT}"

	if [ -d magento2 ]; then
		sudo rm -R magento2
	fi

	echo "Downloading magento 2.3\n";
	sudo wget https://github.com/magento/magento2/archive/refs/heads/2.4.3-release.zip

	echo "Unzip Magento\n"
	sudo unzip 2.4.3-release.zip

	echo "Rename magento folder\n"

	sudo mv magento2-2.4.3-release magento2
	sudo rm 2.4.3-release.zip

	echo "Changing file permissions"
	sudo chown -R www-data:www-data /var/www/html/magento2/
	sudo chmod -R 755 /var/www/html/magento2/
}

install_magento () {
	echo "Running Composer\n"
	cd magento2
	sudo -u www-data composer update
	sudo -u www-data composer install

	echo "Installing magento application\n"
	sudo bin/magento setup:install --db-name="${DB_NAME}" --db-user="${DB_USER}" --db-password="${DB_PASSWORD}" --admin-firstname="admin" --admin-lastname="admin" --admin-email="example@email.com" --admin-user="${MAGENTO_ADMIN_USER}" --admin-password="${MAGENTO_ADMIN_PASSWORD}" --timezone="Europe/London"

	change_file_permissions

	sudo bin/magento cron:run
	change_file_permissions

	sudo php -dmemory_limit=2G bin/magento setup:di:compile
	change_file_permissions

	sudo bin/magento deploy:mode:set developer
	sudo bin/magento cache:flush
	change_file_permissions
}

change_file_permissions () {
	sudo chmod -R 755 ./
	sudo chmod -R 777 var/
	sudo chmod -R 777 pub/
	sudo chmod -R 777 app/etc
	sudo chmod -R 777 generated
}

modify_apache_site_config () {

	readonly A2_CONFIG="/etc/apache2/sites-available/000-default.conf";

	echo -e "<VirtualHost *:80>" > "${A2_CONFIG}"
	echo -e "" >> "${A2_CONFIG}"
	echo -e "\tServerAdmin webmaster@localhost" >> "${A2_CONFIG}"
	echo -e "\tDocumentRoot /var/www/html/magento2/pub" >> "${A2_CONFIG}"
	echo -e "" >> "${A2_CONFIG}"
	echo -e "\tErrorLog ${APACHE_LOG_DIR}/error.log" >> "${A2_CONFIG}"
	echo -e "\tCustomLog ${APACHE_LOG_DIR}/access.log combined" >> "${A2_CONFIG}"
	echo -e "" >> "${A2_CONFIG}"
	echo -e "\t<Directory \"/var/www/html\">" >> "${A2_CONFIG}"
	echo -e "\t\tAllowOverride all" >> "${A2_CONFIG}"
	echo -e "\t</Directory>" >> "${A2_CONFIG}"
	echo -e "</VirtualHost>" >> "${A2_CONFIG}"

	sudo service apache2 restart
}



main () {

	if [ "$EUID" -ne 0 ]
	  then echo "Please run as SUDO"
	  exit
	fi

	update_packages
	install_elastic_search
	install_lamp_stack
	configure_elastic_search
	setup_database
	install_composer
	download_magento
	install_magento
	modify_apache_site_config
	echo "ALL IS DONE";
}

main

exit 0
