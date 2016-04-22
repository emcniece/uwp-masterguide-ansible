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


    # Hide sensitive files
    location ~* \.(engine|inc|info|install|make|module|profile|test|po|sh|.*sql|theme|tpl(\.php)?|xtmpl)$|^(\..*|Entries.*|Repository|Root|Tag|Template)$|\.php_
    {
        return 444;
    }

    # Prevent CGI scripts
    location ~* \.(pl|cgi|py|sh|lua)\$ {
        return 444;
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
