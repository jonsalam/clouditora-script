#!/bin/bash

source ../script-helper.sh
./install-docker.sh

assert_docker_container nginx

mkdir -p /data/app/nginx/{www,conf,logs}
cp nginx/index.html  /data/app/nginx/www
cp nginx/favicon.ico /data/app/nginx/www
cp nginx/index.conf  /data/app/nginx/conf

docker rm -f mynginx
docker build -t mynginx ./nginx

docker run -d \
  --net=host \
  -v /data/app/nginx/www:/usr/share/nginx/html:ro \
  -v /data/app/nginx/conf:/etc/nginx/conf.d:ro \
  -v /data/app/nginx/logs:/var/log/nginx \
  -v /etc/localtime:/etc/localtime:ro \
  --restart=always \
  --name nginx \
  mynginx
