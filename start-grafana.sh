#!/bin/bash

# Get AWS credentials for the 'new' profile
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile new)
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile new)

# Start Grafana
docker-compose up -d 