#!/bin/bash

IMAGE_NAME="ndn-simulator"
docker build -q -t $IMAGE_NAME . > /dev/null
docker run --rm -v "$(pwd):/app" $IMAGE_NAME "$@"
