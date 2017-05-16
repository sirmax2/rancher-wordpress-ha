#!/bin/bash

set -e

[ "$DEBUG" == "1" ] && set -x && set +e

# Required variables
sleep 5
export DB_HOSTS=`dig +short ${DB_HOST}`
if [ -z "${DB_HOSTS}" ]; then
   echo "*** ERROR: Could not determine which containers are part of PXC service."
   echo "*** Is PXC service linked with the alias \"${DB_HOST}\"?"
   echo "*** If not, please link gluster service as \"${DB_HOST}\""
   echo "*** Exiting ..."
   exit 1
fi

if [ "${DB_ADMIN_PASSWORD}" == "**ChangeMe**" -o -z "${DB_ADMIN_PASSWORD}" ]; then
   DB_ADMIN_PASSWORD=${DB_ENV_PXC_ROOT_PASSWORD}
   if [ "${DB_ADMIN_PASSWORD}" == "**ChangeMe**" -o -z "${DB_ADMIN_PASSWORD}" ]; then
      echo "ERROR: Could not retreive PXC_ROOT_PASSWORD from PXC service - DB_ENV_PXC_ROOT_PASSWORD env var is empty - Exiting..."
      exit 0
   fi
fi

if [ "${DB_WP_NAME}" == "**ChangeMe**" -o -z "${DB_WP_NAME}" ]; then
   DB_WP_NAME=`echo "${WORDPRESS_NAME}" | sed "s/\./_/g"`
fi

if [ "${DB_WP_PASSWORD}" == "**ChangeMe**" -o -z "${DB_WP_PASSWORD}" ]; then
   echo "*** ERROR: DB_WP_PASSWORD is not set - Exiting ..."
fi

if [ "${HTTP_DOCUMENTROOT}" == "**ChangeMe**" -o -z "${HTTP_DOCUMENTROOT}" ]; then
   HTTP_DOCUMENTROOT=/var/www/${WORDPRESS_NAME}
fi


### Prepare configuration
# nginx config
perl -p -i -e "s/HTTP_PORT/${HTTP_PORT}/g" /etc/nginx/sites-enabled/wordpress
HTTP_ESCAPED_DOCROOT=`echo ${HTTP_DOCUMENTROOT} | sed "s/\//\\\\\\\\\//g"`
perl -p -i -e "s/HTTP_DOCUMENTROOT/${HTTP_ESCAPED_DOCROOT}/g" /etc/nginx/sites-enabled/wordpress

# php-fpm config
PHP_ESCAPED_SESSION_PATH=`echo ${PHP_SESSION_PATH} | sed "s/\//\\\\\\\\\//g"`
perl -p -i -e "s/;?session.save_path\s*=.*/session.save_path = \"${PHP_ESCAPED_SESSION_PATH}\"/g" /etc/php/7.0/fpm/php.ini

if [ ! -d ${HTTP_DOCUMENTROOT} ]; then
   mkdir -p ${HTTP_DOCUMENTROOT}
fi

if [ ! -d ${PHP_SESSION_PATH} ]; then
   mkdir -p ${PHP_SESSION_PATH}
   chown www-data:www-data ${PHP_SESSION_PATH}
fi

if [ ! -e ${HTTP_DOCUMENTROOT}/index.php ]; then
   echo "=> Installing wordpress in ${HTTP_DOCUMENTROOT} - this may take a while ..."
   touch ${HTTP_DOCUMENTROOT}/index.php
   curl -o /tmp/wordpress.tar.gz "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"
   tar -zxf /tmp/wordpress.tar.gz -C /tmp/
   mv /tmp/wordpress/* ${HTTP_DOCUMENTROOT}/
   chown -R www-data:www-data ${HTTP_DOCUMENTROOT}
fi

if grep "PXC nodes here" /etc/haproxy/haproxy.cfg >/dev/null; then
   PXC_HOSTS_HAPROXY=""
   PXC_HOSTS_COUNTER=0

   for host in `echo ${DB_HOSTS} | sed "s/,/ /g"`; do
      PXC_HOSTS_HAPROXY="$PXC_HOSTS_HAPROXY\n  server pxc$PXC_HOSTS_COUNTER $host:3306 check"
      if [ $PXC_HOSTS_COUNTER -gt 0 ]; then
         PXC_HOSTS_HAPROXY="$PXC_HOSTS_HAPROXY backup"
      fi
      PXC_HOSTS_COUNTER=$((PXC_HOSTS_COUNTER+1))
   done
   perl -p -i -e "s/DB_ADMIN_USER/${DB_ADMIN_USER}/g" /etc/haproxy/haproxy.cfg
   perl -p -i -e "s/DB_ADMIN_PASSWORD/${DB_ADMIN_PASSWORD}/g" /etc/haproxy/haproxy.cfg
   perl -p -i -e "s/.*server pxc.*//g" /etc/haproxy/haproxy.cfg
   perl -p -i -e "s/# PXC nodes here.*/# PXC nodes here\n${PXC_HOSTS_HAPROXY}/g" /etc/haproxy/haproxy.cfg
fi

if [ ! -e ${HTTP_DOCUMENTROOT}/wp-config.php ] && [ -e ${HTTP_DOCUMENTROOT}/wp-config-sample.php ] ; then
   
### Prepare mysql ###
   mysql -u ${DB_ADMIN_USER} -p${DB_ADMIN_PASSWORD} -h${DB_HOST} -e "INSERT INTO mysql.user (Host,User) values ('%','haproxy_check'); FLUSH PRIVILEGES;"
   echo "=> Configuring wordpress..."
   touch ${HTTP_DOCUMENTROOT}/wp-config.php
   sed -e "s/database_name_here/$DB_WP_NAME/
   s/username_here/$DB_WP_USER/
   s/password_here/$DB_WP_PASSWORD/
   s/localhost/127.0.0.1/
   /'AUTH_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'SECURE_AUTH_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'LOGGED_IN_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'NONCE_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'AUTH_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'SECURE_AUTH_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'LOGGED_IN_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/
   /'NONCE_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/" ${HTTP_DOCUMENTROOT}/wp-config-sample.php > ${HTTP_DOCUMENTROOT}/wp-config.php
   chown www-data:www-data ${HTTP_DOCUMENTROOT}/wp-config.php
   chmod 640 ${HTTP_DOCUMENTROOT}/wp-config.php

  # Download nginx helper plugin
  curl -O `curl -i -s https://wordpress.org/plugins/nginx-helper/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+"`
  unzip -o nginx-helper.*.zip -d ${HTTP_DOCUMENTROOT}/wp-content/plugins
  chown -R www-data:www-data ${HTTP_DOCUMENTROOT}/wp-content/plugins/nginx-helper

  # Activate nginx plugin and set up pretty permalink structure once logged in
  cat << ENDL >> ${HTTP_DOCUMENTROOT}/wp-config.php
\$plugins = get_option( 'active_plugins' );
if ( count( \$plugins ) === 0 ) {
  require_once(ABSPATH .'/wp-admin/includes/plugin.php');
  \$wp_rewrite->set_permalink_structure( '/%postname%/' );
  \$pluginsToActivate = array( 'nginx-helper/nginx-helper.php' );
  foreach ( \$pluginsToActivate as \$plugin ) {
    if ( !in_array( \$plugin, \$plugins ) ) {
      activate_plugin( '${HTTP_DOCUMENTROOT}/wp-content/plugins/' . \$plugin );
    }
  }
}
ENDL

  echo "=> Creating database ${DB_WP_NAME}, username ${DB_WP_NAME}, with password ${DB_WP_PASSWORD} ..."
  service haproxy start
  sleep 2
  mysql -h 127.0.0.1 -u ${DB_ADMIN_USER} -p${DB_ADMIN_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS ${DB_WP_NAME}; GRANT ALL PRIVILEGES ON ${DB_WP_NAME}.* TO '${DB_WP_USER}'@'10.42.%' IDENTIFIED BY '${DB_WP_PASSWORD}'; FLUSH PRIVILEGES;"
  service haproxy stop
fi

if [ ! -e ${HTTP_DOCUMENTROOT}/healthcheck.txt ]; then
   echo "OK" > ${HTTP_DOCUMENTROOT}/healthcheck.txt
fi

/usr/bin/supervisord
