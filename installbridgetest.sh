#!/bin/bash
set -e

read -p "Enter your RPC_NODE_IP: " RPC_NODE_IP

cd $HOME
rm -rf celestia-node
git clone https://github.com/celestiaorg/celestia-node
cd celestia-node
git checkout tags/v0.28.5-mocha
make build
sudo make install
make cel-key

celestia bridge init --core.ip $RPC_NODE_IP --p2p.network mocha
$HOME/celestia-node/cel-key list --node.type bridge --keyring-backend test --p2p.network mocha

sudo tee /etc/systemd/system/celestia-bridge.service > /dev/null <<EOF
[Unit]
Description=Celestia Bridge Node
After=network-online.target

[Service]
User=$USER
ExecStart=$(which celestia) bridge start \
--p2p.network mocha --archival \
--metrics.tls=true --metrics --metrics.endpoint otel.mocha.celestia.observer
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable celestia-bridge
sudo systemctl restart celestia-bridge

echo "Setup complete. Monitor logs with: sudo journalctl -u celestia-bridge -f"
