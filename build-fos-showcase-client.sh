#!/bin/zsh

docker buildx build --platform linux/amd64 -t foscompsvcs/fos-showcase-client:latest -f Dockerfile-client .
docker push foscompsvcs/fos-showcase-client:latest

