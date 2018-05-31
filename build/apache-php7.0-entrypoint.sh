#!/bin/bash
set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)

error=false
for env in "WORDPRESS_DB_NAME" "WORDPRESS_DB_USER" "WORDPRESS_DB_PASSWORD" "WP_HOME" "WP_SITEURL"; do
    if [ -z "${!env}" ]; then
        error=true
        echo >&2 "error: $env required"
    fi
done

if [ "$error" = true ]; then
     echo >&2 'errors occurred, existing'
    exit 1
fi

DB_FILE=.env

sed -i -e "s,DB_NAME=database_name,DB_NAME=$WORDPRESS_DB_NAME,g" $DB_FILE
sed -i -e "s,DB_USER=database_user,DB_USER=$WORDPRESS_DB_USER,g" $DB_FILE
sed -i -e "s,DB_PASSWORD=database_password,DB_PASSWORD=$WORDPRESS_DB_PASSWORD,g" $DB_FILE
sed -i -e "s,# DB_HOST=localhost,DB_HOST=$WORDPRESS_DB_HOST,g" $DB_FILE
sed -i -e "s,WP_ENV=development,WP_ENV=$WP_ENV,g" $DB_FILE
sed -i -e "s,WP_HOME=http://example.com,WP_HOME=$WP_HOME,g" $DB_FILE

TERM=dumb php -- "$WORDPRESS_DB_HOST" "$WORDPRESS_DB_USER" "$WORDPRESS_DB_PASSWORD" "$WORDPRESS_DB_NAME" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)
$stderr = fopen('php://stderr', 'w');
list($host, $port) = explode(':', $argv[1], 2);
$maxTries = 10;
do {
	$mysql = new mysqli($host, $argv[2], $argv[3], '', (int)$port);
	if ($mysql->connect_error) {
		fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
		--$maxTries;
		if ($maxTries <= 0) {
			exit(1);
		}
		sleep(3);
	}
} while ($mysql->connect_error);
if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[4]) . '`')) {
	fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
	$mysql->close();
	exit(1);
}
$mysql->close();
EOPHP

su -s /bin/bash www-data -c "cd /var/www/html/ && composer install"

if [ ! -e web/.htaccess ]; then
	# NOTE: The "Indexes" option is disabled in the php:apache base image
	cat > web/.htaccess <<-'EOF'
		# BEGIN WordPress
		<IfModule mod_rewrite.c>
					RewriteEngine On
					RewriteBase /
					RewriteRule ^index\.php$ - [L]
					RewriteRule ^wp-admin$ wp-admin/ [R=301,L]
					RewriteCond %{REQUEST_FILENAME} -f [OR]
					RewriteCond %{REQUEST_FILENAME} -d
					RewriteRule ^ - [L]
					RewriteRule ^(.*\.php)$ /wp/$1 [L]
					RewriteRule ^(wp-(content|admin|includes).*)$ wp/$1 [L]
					RewriteRule . index.php [L]
		</IfModule>
		# END WordPress
	EOF
	chown www-data:www-data web/.htaccess
fi

exec "$@"
