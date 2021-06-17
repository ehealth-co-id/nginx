#!/bin/sh

/usr/sbin/nginx -g "daemon off;" &
echo $? > /run/nginx.pid

echo "generate dhparam..."
if [ ! -f /etc/nginx/ssl/dhparam.pem ]; then
  mkdir -p /etc/nginx/ssl
  openssl dhparam -out /etc/nginx/ssl/dhparam.pem 128
fi;

echo "starting nginx..."
/usr/sbin/nginx -g "daemon off;"
