fastcgi_cache_path {{ webroot }}/{{ site_url }}/cache levels=1:2 keys_zone={{ fpm_poolname }}:100m inactive=60m;

#server {
#    listen 443;
#    server_name {{ site_url }};
#    rewrite ^(.*) http://$host$1 permanent;
#}

server {
    listen 80;
    server_name {{ site_url }} www.{{ site_url }};

    access_log {{ webroot }}/{{ site_url }}/logs/access.log;
    error_log {{ webroot }}/{{ site_url }}/logs/error.log;

    root {{ webroot }}/{{ site_url }}/public/;
    index index.php index.html;

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

    # Deny referal spam
    if ( $http_referer ~* (jewelry|viagra|nude|girl|nudit|casino|poker|porn|sex|teen|babes) ) {
        return 403;
    }

    # Block some nasty robots
    if ($http_user_agent ~ (msnbot|Purebot|Baiduspider|Lipperhey|Mail.Ru|scrapbot) ) {
        return 403;
    }

    # Block download agenta
    if ($http_user_agent ~* LWP::Simple|wget|libwww-perl) {
        return 403;
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
        fastcgi_pass unix:/var/run/php5-fpm-{{ site_url }}.sock;
        fastcgi_index index.php;
        include fastcgi_params;

        fastcgi_cache_bypass $skip_cache;
        fastcgi_no_cache $skip_cache;
        fastcgi_cache {{ fpm_poolname }};
        fastcgi_cache_valid 60m;
    }

    location ~ /purge(/.*) {
        fastcgi_cache_purge {{ fpm_poolname }} "$scheme$request_method$host$1";
    }
}
