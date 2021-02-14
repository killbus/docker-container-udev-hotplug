#!/bin/bash

# dump system environment
env > /tmp/environmentfile

# Just an infinite loop to prevent container from exiting
while : ;
do
  echo 'Idling...'
  sleep 600
done
