    location /kids/ {
        alias /var/www/kids/;
        try_files $uri $uri/ /kids/index.html;
    }
    location /solar/ {
        alias /var/www/solar/;
        try_files $uri $uri/ /solar/index.html;
    }
    # Prefixed API paths avoid clashing with jira's /api/auth. The trailing "/"
    # on proxy_pass strips the /kids or /solar prefix.
    location /kids/api/ {
        proxy_pass http://KIDS_HOST:5900/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # SPA and API are same-origin behind nginx; the backend CORS allowlist only
        # knows localhost, so don't forward Origin (empty value = header omitted).
        proxy_set_header Origin "";
        proxy_read_timeout 30s;
    }
    location /solar/api/ {
        proxy_pass http://SOLAR_HOST:5901/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # SPA and API are same-origin behind nginx; the backend CORS allowlist only
        # knows localhost, so don't forward Origin (empty value = header omitted).
        proxy_set_header Origin "";
        proxy_read_timeout 30s;
    }
