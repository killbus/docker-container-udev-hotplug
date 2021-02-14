#!/bin/bash

# dump system environment
env >/tmp/environmentfile

# Just an infinite loop to prevent container from exiting
balena-idle