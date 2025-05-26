#!/bin/zsh

docker buildx build --platform linux/amd64 -t foscompsvcs/fos-showcase-server:latest -f Dockerfile-server .
docker push foscompsvcs/fos-showcase-servert:latest

