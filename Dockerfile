FROM ubuntu:16.04

ENV WORDPRESS_VERSION 4.7
ENV WORDPRESS_NAME wordpress
ENV HTTP_PORT 80
ENV HTTP_DOCUMENTROOT **ChangeMe**
ENV PHP_SESSION_PATH /var/www/phpsessions
ENV DEBUG 0

ENV DB_HOST pxc
ENV DB_ADMIN_USER root
ENV DB_ADMIN_PASSWORD **ChangeMe**
ENV DB_WP_NAME **ChangeMe**
ENV DB_WP_USER wpuser
ENV DB_WP_PASSWORD **ChangeMe**

###

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y \
        python-software-properties \
        software-properties-common \
        nginx \
        php7.0-fpm php7.0-mysql \
        supervisor \
        curl \
        haproxy \
        pwgen \
        unzip \
        mysql-client \
        dnsutils

RUN mkdir -p /var/log/supervisor /var/www /run/php
VOLUME [ "/var/www" ]
WORKDIR /var/www

RUN mkdir -p /usr/local/bin
ADD ./bin /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh
ADD ./etc/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ./etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg
ADD ./etc/nginx/sites-enabled/wordpress /etc/nginx/sites-enabled/wordpress

# nginx config
RUN sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf
RUN sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf
RUN echo "daemon off;" >> /etc/nginx/nginx.conf
RUN rm -f /etc/nginx/sites-enabled/default
#RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
#    ln -sf /dev/stderr /var/log/nginx/error.log

# php-fpm config
RUN sed -i -e "s/short_open_tag\s*=\s*Off/short_open_tag = On/g" /etc/php/7.0/fpm/php.ini
RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/7.0/fpm/php.ini
RUN sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php/7.0/fpm/php.ini
RUN sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php/7.0/fpm/php.ini
RUN sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/7.0/fpm/php-fpm.conf
RUN sed -i -e "s,listen\s*=\s*/run/php/php7.0-fpm.sock,listen = 127.0.0.1:9000,g" /etc/php/7.0/fpm/pool.d/www.conf
RUN sed -i -e "s/;listen.allowed_clients\s*=\s*127.0.0.1/listen.allowed_clients = 127.0.0.1/g" /etc/php/7.0/fpm/pool.d/www.conf

# HAProxy
RUN perl -p -i -e "s/ENABLED=0/ENABLED=1/g" /etc/default/haproxy

CMD ["/usr/local/bin/run.sh"]
