#!/bin/bash

##### Arguments
COLOR="RED"

##### Apache2 Server Setup
sudo apt update
sudo apt install apache2 -y
sudo systemctl status apache2
