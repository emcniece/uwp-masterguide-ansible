#Ubuntu/WordPress Master Guide

This guide will cover VM setup, basic system administration and WordPress security and optimization techniques for a solid, low-budget, ~~secure~~ multi-user multi-domain machine.

**Note:** Security is not fully implemented for multiple domains - use at your own risk!

Inspired by Ashley Rich's [Hosting WordPress Yourself](https://deliciousbrains.com/hosting-wordpress-setup-secure-virtual-server/). [View all references below](#reference).


We'll assume that you have access to a fresh Ubuntu 14.x VM already - go ahead and log in. In-depth analysis of this tutorial can be read about in the link above - we will move through this guide here as efficiently as possible.

Want to automate this process? [Check out the Ansible Playbook version over here](/ansible/)!

**Chapters**

1. [Ubuntu setup](#ubuntu-setup)
1. [Nginx, PHP, MySQL](#nginx-php-mysql)
1. [Setting up a new domain and website](#new-site-setup)
1. [Monitoring and Caching](#monitoring-and-caching)
1. [Cron, Email, Automatic Backups](#cron-email-and-backups)
1. [SSL and SPDY](#ssl-and-spdy)
1. [Nginx Security, specialized caching, and auto server updates](#advanced-server-configuration)
1. [Cheat Sheet](#cheat-sheet)
1. [Troubleshooting](#troubleshooting)
1. [Future Improvements](#future-improvements)
1. [Reference](#reference)

----

## Ubuntu Setup

First step:

    apt-get update && apt-get upgrade

### Set the host name

This host name should be the first or top-level domain name. Particularly important during reverse DNS lookup

    echo "mysite.com" > /etc/hostname
    hostname -F /etc/hostname

If *etc/default/dhcpcd* exists, comment out `SET_HOSTNAME='yes'`

    sudo nano /etc/default/dhcpcd
        #SET_HOSTNAME='yes'

Set hosts file

    wget http://ipinfo.io/ip -qO -
    sudo nano /etc/hosts
        52.33.54.155 mysite.com  # server IP address

Set timezone:

    timedatectl set-timezone America/Vancouver

Perform updates:

    apt-get update && apt-get upgrade && apt-get autoremove

Create website user (with no password which is good)

    sudo groupadd mysite_com
    useradd -g mysite_com mysite_com

Update SSH config

    sudo nano /etc/ssh/sshd_config
        Port 2200
        PermitRootLogin no

    sudo service ssh restart

(log in again if needed)

Firewall

    sudo apt-get install ufw
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow 443/tcp
    sudo ufw show added
    sudo ufw enable
    sudo ufw status verbose

Fail2ban

    sudo apt-get install fail2ban && sudo service fail2ban start

## Nginx, PHP, MySQL

### Install Nginx

    sudo add-apt-repository ppa:rtcamp/nginx -y
    sudo apt-get update
    sudo apt-get install nginx-custom -y

Verify installation:

    nginx -v

Also, visiting IP / URL in browser should show Nginx homepage (http://52.33.54.155/)

Basic Nginx config: make note of return values from here:

    grep processor /proc/cpuinfo | wc -l
        (returns 1)
    ulimit -n
        (return 1024)

Configure Nginx:

    sudo nano /etc/nginx/nginx.conf
        user www-data;
        worker_processes 1;      # from above: 1 process per core

        events{
            worker_connections 1024;    # from above: num cores * ulimit
            multi_accept on;
        }
        http{
            keepalive_timeout 15;
            server_tokens off;
            client_max_body_size 64m;

            gzip_proxied any;
            gzip_comp_level 2;
            gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        }

Test Nginx config:

    sudo nginx -t
    sudo service nginx restart


### PHP-FPM

Install PHP and modules

    sudo apt-add-repository ppa:ondrej/php5-5.6 -y
    sudo apt-get update
    sudo apt-get install php5-fpm php5-common php5-mysqlnd php5-xmlrpc php5-curl php5-gd php5-cli php-pear php5-dev php5-imap php5-mcrypt

Test install

    php5-fpm -v

#### Configure PHP-FPM Default Site

    sudo nano /etc/php5/fpm/pool.d/www.conf
        user = www-data
        group = www-data
        listen.owner = www-data
        listen.group = www-data


    sudo nano /etc/php5/fpm/php.ini
        upload_max_filesize = 64M
        post_max_size = 64M

Test install

    sudo php5-fpm -t
    sudo service php5-fpm restart

Verify that all previous services are running: (shift-M for memory sort)

    top

#### Add Site-Specific Pools

For each site on the server, add a process pool

    sudo nano /etc/php5/fpm/pool.d/mysite_com.conf
        [mysite_com]
        user = mysite_com
        group = mysite_com
        listen = /var/run/php5-fpm-mysite_com.sock
        listen.owner = www-data
        listen.group = www-data
        php_admin_value[disable_functions] = exec,passthru,shell_exec,system
        php_admin_flag[allow_url_fopen] = off
        pm = dynamic
        pm.max_children = 5
        pm.start_servers = 2
        pm.min_spare_servers = 1
        pm.max_spare_servers = 3
        security.limit_extensions = .php .php3 .php4 .php5
        chdir = /

    sudo service php5-fpm restart

### MySQL

Install MySQL

    sudo apt-get install mysql-server
    sudo mysql_install_db
    sudo mysql_secure_installation

### Catch-All Server Block

    sudo rm /etc/nginx/sites-available/default
    sudo rm /etc/nginx/sites-enabled/default
    sudo nano /etc/nginx/nginx.conf

        # Under the include sites-enabled line:
        include /etc/nginx/sites-enabled/*;
        server {
            listen 80 default_server;
            server_name _;
            return 444;
        }

Test Nginx

    sudo nginx -t
    sudo service nginx restart

Visiting site in a browser should now be an error: (http://52.33.54.155/)

[Nginx conf example](https://gist.githubusercontent.com/A5hleyRich/d88e6de510dd8e303153/raw/9724dab6d0945a144ec823efaad7e8039cafe903/nginx.conf)

## New Site Setup

### Configure Nginx Site
Create new folder structure

    mkdir /var/www/mysite.com
    mkdir /var/www/mysite.com/logs
    mkdir /var/www/mysite.com/public
    chmod -R 755 /var/www/mysite.com

Create new configuration file

    sudo nano /etc/nginx/sites-available/mysite.com

Create site config - match FPM sock with pool defined above

    server {
        server_name mysite.com www.mysite.com;

        access_log /var/www/mysite.com/logs/access.log;
        error_log /var/www/mysite.com/logs/error.log;

        root /var/www/mysite.com/public/;
        index index.php;

        location / {
            try_files $uri $uri/ /index.php?$args;
        }

        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/var/run/php5-fpm-mysite_com.sock;
            fastcgi_index index.php;
            include fastcgi_params;
        }
    }

Symlink to sites-enabled

    sudo ln -s /etc/nginx/sites-available/mysite.com /etc/nginx/sites-enabled/mysite.com

Test Nginx

    sudo nginx -t
    sudo service nginx restart

### Create MySQL Database

Login, create database

    mysql -u root -p
        CREATE DATABASE mysite_wp;
        CREATE USER 'mysite_wp'@'localhost' IDENTIFIED BY 'password';
        GRANT ALL PRIVILEGES ON mysite_wp.* TO 'mysite_wp'@'localhost';
        FLUSH PRIVILEGES;
        exit;

### Install WP-CLI

Useful for fast WP setup

    cd
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    php wp-cli.phar --info

Move to PATH

    chmod +x wp-cli.phar
    sudo mv wp-cli.phar /usr/local/bin/wp
    alias wp="wp --allow-root"

Test PATH (should open wp-cli)

    wp

### Install WordPress

Use WP-CLI to install

    cd /var/www/mysite.com/public
    wp core download
    wp core config --dbname=mysite_wp --dbuser=mysite_wp --dbpass=password
    wp core install --url=http://mysite.com --title='My Website' --admin_user=adminuser --admin_email=info@mysite.com --admin_password=password2

Visit your site in a browser!


## Monitoring and Caching

### Install New Relic monitoring

Sign up for new server account first, then follow instructions

    echo deb http://apt.newrelic.com/debian/ newrelic non-free >> /etc/apt/sources.list.d/newrelic.list
    wget -O- https://download.newrelic.com/548C16BF.gpg | apt-key add -
    apt-get update
    apt-get install newrelic-sysmond
    nrsysmond-config --set license_key=1234567890qwertyuiopasdfghjklzxcvbnm0123
    /etc/init.d/newrelic-sysmond start

### Opcode Cache

Ensure Opcache is running: search for `opcache.enable`

    sudo nano /etc/php5/fpm/php.ini
        opcache.enable=1
        opcache.memory_consumption=64

Enable Opcache

    sudo php5enmod opcache
    sudo service php5-fpm restart


### Object Cache

Install Redis

    sudo apt-get install redis-server
    sudo apt-get install php5-redis

Set max memory usage

    sudo nano /etc/redis/redis.conf
        maxmemory 64mb
        requirepass mySecretPasswd
        bind 127.0.0.1

    sudo chmod 700 /var/lib/redis
    sudo chown redis:root /etc/redis/redis.conf
    sudo chmod 600 /etc/redis/redis.conf
    sudo ufw allow from 127.0.0.1 to any port 6379
    sudo ufw status
    sudo service redis-server restart
    sudo service php5-fpm restart

Install Redis Cache WP plugin

    cd /var/www/mysite.com/public
    wp plugin install redis-cache
    wp plugin activate redis-cache

Add wp-config.php redis configuration

    sudo nano wp-config.php
        define('WP_REDIS_DATABASE', 1); // choose a number that doesn't conflict with other sites!


### Page Cache

Alter Nginx site config: prepend fascgi lines, BEFORE server block

    sudo nano /etc/nginx/sites-available/mysite.com

        fastcgi_cache_path /var/www/mysite.com/cache levels=1:2 keys_zone=WP_MYSITECOM:100m inactive=60m;
        server{
            ...
        }

Don't cache certain pages: wp-admin, logged-in users, etc. Add before first location{} block:

    set $skip_cache 0;

    # POST requests and urls with a query string should always go to PHP
    if ($request_method = POST) {
        set $skip_cache 1;
    }
    if ($query_string != "") {
        set $skip_cache 1;
    }

    # Don’t cache uris containing the following segments
    if ($request_uri ~* "/wp-admin/|/xmlrpc.php|wp-.*.php|/feed/|index.php|sitemap(_index)?.xml") {
        set $skip_cache 1;
    }

    # Don’t use the cache for logged in users or recent commenters
    if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
        set $skip_cache 1;
    }

Add fastcgi bypass in the PHP location block

    fastcgi_cache_bypass $skip_cache;
    fastcgi_no_cache $skip_cache;
    fastcgi_cache WP_MYSITECOM;
    fastcgi_cache_valid 60m;

Add a custom location block to purge

    location ~ /purge(/.*) {
        fastcgi_cache_purge WP_MYSITECOM "$scheme$request_method$host$1";
    }

Close site config!

Add an extra header response for easy cache determining. Insert below Gzip settings

    sudo nano /etc/nginx/nginx.conf
        ##
        # Cache Settings
        ##

        add_header Fastcgi-Cache $upstream_cache_status;

        ##
        # FastCGI Cache
        ##

        fastcgi_cache_key "$scheme$request_method$host$request_uri";

    sudo service nginx restart

Install Nginx Helper WP Plugin

    wp plugin install nginx-helper
    wp plugin activate nginx-helper

Configure Nginx Helper cache path

    cd /var/www/mysite.com/public/
    nano wp-config.php
        define('RT_WP_NGINX_HELPER_CACHE_PATH', '/var/www/mysite.com/cache/');

## Cron, Email, and Backups

### Cron (Automated system tasks)

Native WP cron hurts users - use crontab! **SKIP THIS IF PLANNING TO USE [AUTOMATED TASKS](#wp-automated-updates-and-checks)**

    cd /var/www/mysite.com/public/
        nano wp-config.php
            define('DISABLE_WP_CRON', true);

    crontab -e
        */5 * * * * cd /var/www/mysite.com/public; php -q wp-cron.php >/dev/null 2>&1

### Email: Mandrill

Install Mandrill

    wp plugin install wpmandrill
    wp plugin activate wpmandrill

- Create Mandrill account, set up API key (Settings -> API Keys)
- Navigate to WP Mandrill settings page, enter API key
- **Optional:** Test cron/Mandrill [with this plugin](https://gist.githubusercontent.com/A5hleyRich/6de1712ce5f46662c8ba/raw/914d19b1d16fe5f2cf3825fe7d542a98bc477e12/cron-test.php)

### Automatic Backups

Set up single site backups. **SKIP THIS IF PLANNING FOR MULTI-DOMAIN SERVER!!**

    cd /var/www/mysite.com/
    mkdir backups
    nano backup.sh
        #!/bin/bash

        cd /var/www/mysite.com/public

        # Backup database
        wp db export ../backups/`date +%Y%m%d`_database.sql --add-drop-table

        # Backup uploads directory
        tar -zcf ../backups/`date +%Y%m%d`_uploads.tar.gz wp-content/uploads
    chmod u+x backup.sh
    crontab -e
        0 5 * * 0 sh /var/www/mysite.com/backup.sh


## SSL and SPDY

### SSL

Skipping for now... sorry! See [the tutorial](https://deliciousbrains.com/hosting-wordpress-yourself-ssl-spdy/) for more info.

### SPDY

**This will only work on 443 with an SSL cert!**

Enable Nginx SPDY: insert server `listen 443 ssl spdy;` line

    sudo nano /etc/nginx/sites-available/mysite.com
        server {
            listen 443 ssl spdy;
            server_name mysite.com www.mysite.com;


Ensure SPDY is working with https://spdycheck.org/


## Advanced Server Configuration

### Security: XSS, Clickjacking, MIME Sniffing (oh my)

Edit either global nginx.conf, or perform on a site-by-site basis. Insert security header within the `http` block:

    sudo nano /etc/nginx/nginx.conf
        ##
        # Security
        ##

        add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval';" always;
        add_header X-Xss-Protection "1; mode=block" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

    sudo nginx -t
    sudo service nginx reload

Test security headers with https://securityheaders.io/

### Automatic Server Updates

Enable automatic security updates (not non-essential updates)

    sudo apt-get install unattended-upgrades
    sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
        // Automatically upgrade packages from these (origin:archive) pairs
        Unattended-Upgrade::Allowed-Origins {
            "${distro_id}:${distro_codename}-security";
            ...
        Unattended-Upgrade::Automatic-Reboot-Time "04:00";

### WP Automated Updates and Checks

Install tasks script: performs actions for multiple sites:

- cron (5min)
- DB/Uploads dir backup to S3
- File permission updates
- WP checksum verification

Install scripts:

    cd
    sudo apt-get install unzip git
    git clone https://github.com/A5hleyRich/simple-automated-tasks.git
    cd simple-automated-tasks
    mv .tasks ~/
    cd
    rm -rf simple-automated-tasks

    nano ~/.tasks/sites.sh
        SITES=(
            "mysite.com"
            ...

If not using AWS S3 storage for backup: comment lines

    nano ~/.tasks/backups.sh
        # Send to S3
        # aws s3 cp "../backups/$DATABASE_FILE.gz" "s3://$i/backups/" --storage-class REDUCED_REDUNDANCY
        # aws s3 cp "../backups/$UPLOADS_FILE" "s3://$i/backups/" --storage-class REDUCED_REDUNDANCY

If not using Pushbullet for checksum change notifications: comment line, add logging through Mandrill

    nano ~/.tasks/checksums.sh
        # curl -u $TOKEN: https://api.pushbullet.com/v2/pushes -d type=note -d title="Server" -d body="Checksums verification failed for the following sites:$ERRORS"

        curl -A 'Mandrill-Curl/1.0' -d '{"key":"xx-mandrill-api-key-xx","message":{"html":"<p>Checksums failed for the following sites: $ERRORS<\/p>","subject":"Server Checsums Failed","from_email":"noreply@mysite.com","from_name":"MySite Webserver","to":[{"email":"user@mysite.com","name":"User McName","type":"to"}],"headers":{"Reply-To":"noreply@mysite.com"},"important":false},"async":false}' 'https://mandrillapp.com/api/1.0/messages/send.json'

Revamp cron tasks: remove single site cron, add new task services

    crontab -e
        */5 * * * * cd /root/.tasks; bash cron.sh >/dev/null 2>&1
        # 0 5 * * * cd /root/.tasks; bash backups.sh >/dev/null 2>&1
        0 6 * * * cd /root/.tasks; bash permissions.sh >/dev/null 2>&1
        0 7 * * * cd /root/.tasks; bash checksums.sh >/dev/null 2>&1

### WooCommerce / WP eCommerce FastCGI Caching

Not covered - refer to [the tutorial](https://deliciousbrains.com/hosting-wordpress-yourself-nginx-security-tweaks-woocommerce-caching-auto-server-updates/) for details.


## Cheat Sheet

Web folder directory structure:

    /var/
        www/
            mysite.com/
                backups/
                cache/
                logs/
                public/
            site2.ca/
            site3.ca/

Machine Services

    service nginx status
    service php5-fpm status
    service mysql status

Testing configuration

    nginx -t
    php5-fpm -t

### Full WP site definition

(replace `sitename` and `SITENAME` (fastcgi zone) )

    fastcgi_cache_path /var/www/sitename.ca/cache levels=1:2 keys_zone=SITENAME:100m inactive=60m;

    server {
        server_name sitename.ca www.sitename.ca;

        access_log /var/www/sitename.ca/logs/access.log;
        error_log /var/www/sitename.ca/logs/error.log;

        root /var/www/sitename.ca/public/;
        index index.php;

        set $skip_cache 0;

        # POST requests and urls with a query string should always go to PHP
        if ($request_method = POST) {
            set $skip_cache 1;
        }
        if ($query_string != "") {
            set $skip_cache 1;
        }

        # Don’t cache uris containing the following segments
        if ($request_uri ~* "/wp-admin/|/xmlrpc.php|wp-.*.php|/feed/|index.php|sitemap(_index)?.xml") {
            set $skip_cache 1;
        }

        # Don’t use the cache for logged in users or recent commenters
        if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
            set $skip_cache 1;
        }

        # Prevent uploads PHP execution
        location ~* /(?:uploads|files)/.*\.php$ {
            deny all;
        }

        # Hide sensitive files
        location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)$|^(\..*|Entries.*|Repository|Root|Tag|Template)$|\.php_
        {
            return 444;
        }

        # Prevent CGI scripts
        location ~* \.(pl|cgi|py|sh|lua)\$ {
            return 444;
        }

        # Restrict WP pain points
        location ~ /(\.|wp-config.php|wp-comments-post.php|readme.html|license.txt) {
            deny all;
        }

        location / {
            try_files $uri $uri/ /index.php?$args;
        }

        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/var/run/php5-fpm-sitename_ca.sock;
            fastcgi_index index.php;
            include fastcgi_params;

            fastcgi_cache_bypass $skip_cache;
            fastcgi_no_cache $skip_cache;
            fastcgi_cache SITENAME;
            fastcgi_cache_valid 60m;
        }

        location ~ /purge(/.*) {
            fastcgi_cache_purge SITENAME "$scheme$request_method$host$1";
        }
    }

### WP Plugin Install List

    wp plugin install nginx-helper
    wp plugin activate nginx-helper
    wp plugin install redis-cache
    wp plugin activate redis-cache
    wp plugin install wpmandrill
    wp plugin activate wpmandrill

### New Site Setup Tasklist

1. Create new user and group
1. Add PHP5-FPM Site-Specific Pool
1. Create site directory structure
1. Add Nginx site definition
1. WordPress?
    1. Create site database and user
    1. Install system files
    1. Add `wp-config.php` defines
        - Nginx helper
        - Disable cron
        - Redis database #
        - Redis passwd
1. Add site to tasks (backup, alerts)


## Troubleshooting

**PHP5-FPM isn't working?** Try reinstalling.

    sudo apt-get remove php5 php5-cgi php5-fpm
    sudo apt-get install php5 php5-cgi php5-fpm

## Future Improvements

- [Properly jailshell WP](https://www.digitalocean.com/community/tutorials/how-to-use-firejail-to-set-up-a-wordpress-installation-in-a-jailed-environment)
- [Advanced Security](https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-ossec-security-notifications-on-ubuntu-14-04)


## Reference

### Tutorials

- [Hosting WordPress Yourself by Ashley Rich](https://deliciousbrains.com/hosting-wordpress-setup-secure-virtual-server/)
- [How To Secure Your Redis Installation](https://www.digitalocean.com/community/tutorials/how-to-secure-your-redis-installation-on-ubuntu-14-04)
- [Securing WordPress on Nginx by Rastislav Lamos](https://lamosty.com/2015/04/securing-your-wordpress-site-running-on-nginx/)
- [Nginx PHP-FPM with Chroot by George](https://gir.me.uk/nginx-php-fpm-with-chroot/)

### Code Samples

- [Ashley Rich's Simple Automated Tasks](https://github.com/A5hleyRich/simple-automated-tasks)
- [Nginx Configuration Sample](https://gist.githubusercontent.com/A5hleyRich/d88e6de510dd8e303153/raw/9724dab6d0945a144ec823efaad7e8039cafe903/nginx.conf)
- [WP Cron Test Plugin](https://gist.githubusercontent.com/A5hleyRich/6de1712ce5f46662c8ba/raw/914d19b1d16fe5f2cf3825fe7d542a98bc477e12/cron-test.php)

### Testing Tools
- [Security Headers](https://securityheaders.io/)
- [Gzip Compression Test](http://www.gidnetwork.com/tools/gzip-test.php)