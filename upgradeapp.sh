#!/bin/bash
cd $HOME 
rm -rf celestia-app 
git clone https://github.com/celestiaorg/celestia-app.git 
cd celestia-app/ 
APP_VERSION=v4.0.3-mocha
git checkout tags/$APP_VERSION -b $APP_VERSION 
make install
sed -i -e "s%^proxy_app *=.*%proxy_app = \"tcp://127.0.0.1:36658\"%" $HOME/.celestia-app/config/config.toml
sudo systemctl restart celestia-appd && sudo journalctl -u celestia-appd -f
