#!/bin/bash

apt update

apt install -y \
python3 \
python3-venv \
python3-pip \
git

mkdir -p /opt/beeny-agent

echo "Beeny Agent Installed"
