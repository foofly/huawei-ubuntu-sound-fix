#!/bin/bash

echo "Stopping daemon..."
sudo systemctl stop huawei-soundcard-headphones-monitor.service
sudo systemctl disable huawei-soundcard-headphones-monitor.service

echo "Removing program..."
sudo rm -f /usr/local/bin/huawei-soundcard-headphones-monitor.sh
sudo rm -f /var/usrlocal/bin/huawei-soundcard-headphones-monitor.sh

echo "Removing service..."
sudo rm -f /etc/systemd/system/huawei-soundcard-headphones-monitor.service
sudo systemctl daemon-reload

echo "Uninstalled. Goodbye 😿"
