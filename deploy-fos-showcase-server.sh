#!/bin/sh

aws s3 cp ./docker-compose.yml s3://fos-showcase-server/docker-compose.yml --region eu-central-1

aws ssm send-command \
    --instance-ids "i-0288c9bac585c0cf3" \
    --document-name "AWS-RunShellScript" \
    --parameters commands='
    sudo apt-get install -y awscli && \
    aws s3 cp s3://fos-showcase-server/docker-compose.yml docker-compose.yml' \
    --comment "Download docker-compose.yml from S3" \
    --region "eu-central-1"

aws ssm send-command \
    --instance-ids "i-0288c9bac585c0cf3" \
    --document-name "AWS-RunShellScript" \
    --parameters commands='
    sudo docker-compose pull app && \
    sudo docker-compose up -d app' \
    --comment "Updating foscompsvcs/fos-showcase-server:latest container" \
    --region "eu-central-1"
