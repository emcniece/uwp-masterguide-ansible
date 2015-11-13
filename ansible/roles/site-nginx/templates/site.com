fastcgi_cache_path {{ webroot }}/{{ site_url }}/cache levels=1:2 keys_zone={{ fpm_poolname }}:100m inactive=60m;

server {

    server_name {{ site_url }} www.{{ site_url }};

    access_log {{ webroot }}/{{ site_url }}/logs/access.log;
    error_log {{ webroot }}/{{ site_url }}/logs/error.log;

    root {{ webroot }}/{{ site_url }}/public/;
    index index.php;

    set $skip_cache 0;

    # POST requests and urls with a query string should always go to PHP
    if ($request_method = POST) {
        set $skip_cache 1;
    }
    if ($query_string != "") {
        set $skip_cache 1;
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
