#!/bin/bash
sudo systemctl stop celestia-bridge
cd $HOME
rm -rf celestia-node
git clone https://github.com/celestiaorg/celestia-node.git
cd celestia-node
git checkout tags/v0.26.4 
make build 
sudo make install 
make cel-key
celestia bridge config-update
sudo systemctl restart celestia-bridge && sudo journalctl -u celestia-bridge -f
