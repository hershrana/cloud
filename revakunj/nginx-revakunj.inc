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
        client_max_body_size 56m;   # photos are sent as base64 inside the JSON body
        proxy_read_timeout 180s;    # an AI model call can take up to 120s
        proxy_send_timeout 180s;
    }
    # Admin AI routes (nemotron chat and friends): image/PDF attachments make the JSON
    # body large, and the upstream model can take minutes. Longer prefix than
    # /kids/api/ above, so it wins for every sub-route.
    location /kids/api/admin/ai/ {
        proxy_pass http://KIDS_HOST:5900/api/admin/ai/;
        client_max_body_size 56m;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Origin "";
        proxy_read_timeout 180s;
        proxy_send_timeout 180s;
    }
    # Every /solar/api/ route goes to the solar backend; nginx turns none away, so the backend
    # decides. Same limits as /kids/api/: solar serves the AI routes too (photos as base64 in the
    # JSON body), and a refresh from the car or an AI call can run well past 30s.
    location /solar/api/ {
        proxy_pass http://SOLAR_HOST:5901/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # SPA and API are same-origin behind nginx; the backend CORS allowlist only
        # knows localhost, so don't forward Origin (empty value = header omitted).
        proxy_set_header Origin "";
        client_max_body_size 56m;   # photos are sent as base64 inside the JSON body
        proxy_read_timeout 180s;    # an AI model call can take up to 120s
        proxy_send_timeout 180s;
    }
    # Passkey (WebAuthn) endpoints of the kids-money backend, reached without the /kids
    # prefix: the Solar app signs in against the main backend at /api. Still needed with
    # the /api/ block below: jira's /api/auth is a longer prefix and would otherwise win.
    location /api/auth/passkey/ {
        proxy_pass http://KIDS_HOST:5900/api/auth/passkey/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Origin "";
        proxy_read_timeout 30s;
    }
    # Main kids-money backend, also published at /api/ for the solar frontend. Jira and
    # todo own longer prefixes (/api/jira, /api/auth, /api/tasks, ...) in
    # rp-app-locations.inc; nginx picks the longest prefix, so those still win.
    location /api/ {
        proxy_pass http://KIDS_HOST:5900/api/;
        client_max_body_size 56m;   # photos are sent as base64 inside the JSON body
        proxy_read_timeout 180s;    # an AI model call can take up to 120s
        proxy_send_timeout 180s;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Origin "";
    }
    location /api/account/passkeys {
        proxy_pass http://KIDS_HOST:5900;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Origin "";
        proxy_read_timeout 30s;
    }
    location /learning/ {
        alias /var/www/learning/;
        try_files $uri $uri/ /learning/index.html;
    }
    location /learning/api/ {
        proxy_pass http://LEARNING_HOST:5902/api/;
        # Admins upload course HTML files up to 10 MB
        client_max_body_size 12m;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # Same-origin SPA; don't forward Origin (see the kids/solar blocks)
        proxy_set_header Origin "";
        proxy_read_timeout 60s;
    }
