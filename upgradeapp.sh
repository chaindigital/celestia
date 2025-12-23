#!/bin/bash
cd $HOME 
rm -rf celestia-app 
git clone https://github.com/celestiaorg/celestia-app.git 
cd celestia-app/ 
APP_VERSION=v6.4.4-mocha
git checkout tags/$APP_VERSION -b $APP_VERSION 
make install
celestia-appd update-config
sudo systemctl restart celestia-appd && sudo journalctl -u celestia-appd -f
