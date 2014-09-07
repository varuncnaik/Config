#!/bin/bash

CFLAGS="-I$(xcrun --show-sdk-path)/usr/include"
pyenv install $1

