ARG ALPINE_VERSION=3.10

# Build Nginx
FROM alpine:$ALPINE_VERSION AS nginx

ENV NGINX_VERSION=1.16.1
ENV QUICHE_COMMIT=7eb57c4fc608932acc76c3ee2759c2e41e51d566

ARG NGINX_PGPKEY=520A9993A1C052F8
ARG NGINX_BUILD_CONFIG="\
        --user=nginx \
        --group=nginx \
        --sbin-path=/usr/sbin \
        --modules-path=/usr/lib/nginx/modules \
        --with-http_ssl_module \
        --with-http_gzip_static_module \
        --with-file-aio \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-http_realip_module \
        --with-http_stub_status_module \
        --without-http_autoindex_module \
        --without-http_browser_module \
        --without-http_geo_module \
        --without-http_memcached_module \
        --without-http_userid_module \
        --without-mail_pop3_module \
        --without-mail_imap_module \
        --without-mail_smtp_module \
        --without-http_split_clients_module \
        --without-http_uwsgi_module \
        --without-http_scgi_module \
        --without-http_upstream_ip_hash_module \
        --with-http_sub_module \
        --with-http_gunzip_module \
        --with-http_secure_link_module \
        --with-threads \
        --with-stream \
        --with-stream_ssl_module \
        --prefix=/etc/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --http-log-path=/var/log/nginx/access.log \
        --error-log-path=/var/log/nginx/error.log \
        --pid-path=/var/run/nginx.pid \
    "

RUN apk add --no-cache \
        apr-dev \
        apr-util-dev \
        build-base \
        ca-certificates \
        gd-dev \
        geoip-dev \
        git \
        gnupg \
        icu-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libxslt-dev \
        linux-headers \
        libressl-dev \
        pcre-dev \
        tar \
        curl \
        zlib-dev;

WORKDIR /usr/src

RUN curl -L -O https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    mkdir nginx && tar zxf nginx-${NGINX_VERSION}.tar.gz --strip-components=1 -C nginx

# replace some files
COPY src/nginx/src/http/ngx_http_header_filter_module.c /root/ngx_http_header_filter_module.c
COPY src/nginx/src/core/nginx.h /root/nginx.h
RUN rm nginx/src/http/ngx_http_header_filter_module.c && \
    rm nginx/src/core/nginx.h && \
    cp /root/ngx_http_header_filter_module.c nginx/src/http/ngx_http_header_filter_module.c && \
    cp /root/nginx.h nginx/src/core/nginx.h

RUN git clone -j`nproc` --recursive \
              https://github.com/vozlt/nginx-module-vts.git \
              nginx-module-vts

RUN git clone -j`nproc` --recursive \
              https://github.com/google/ngx_brotli.git \
              ngx_brotli

RUN git clone -j`nproc` --recursive \
              https://github.com/cloudflare/quiche.git \
              quiche

WORKDIR /usr/src/nginx

RUN ./configure ${NGINX_BUILD_CONFIG} \
        --add-module=/usr/src/nginx-module-vts \
        --add-module=/usr/src/ngx_brotli \
        --with-openssl=/usr/src/quiche/deps/boringssl \
        --with-quiche=/usr/src/quiche \
        --with-ld-opt="-Wl,-z,relro,--start-group -lapr-1 -laprutil-1 -licudata -licuuc -lpng -lturbojpeg -ljpeg" && \
    make install -j`nproc`

COPY config/conf.d /etc/nginx/conf.d
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY html /var/www/html

# Combine everything with minimal layers
FROM alpine:$ALPINE_VERSION
LABEL maintainer="Ibrohim Kholilul Islam <ibrohimislam@gmail.com>" \
      version.nginx="${NGINX_VERSION}"

COPY --from=nginx /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx /etc/nginx /etc/nginx
COPY --from=nginx /var/www/html/ /usr/share/nginx/html/

RUN apk --no-cache upgrade && \
    scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/local/bin/envsubst \
            | tr ',' '\n' \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
            | xargs apk add --no-cache \
    && \
    apk add --no-cache curl openssl tzdata

RUN addgroup -S nginx && \
    adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx && \
    mkdir -p /var/log/nginx && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

VOLUME ["/var/www"]
EXPOSE 80 443 443/udp

WORKDIR /root

COPY init.sh /init.sh
CMD ["/init.sh"]

