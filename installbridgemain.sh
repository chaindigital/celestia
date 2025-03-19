#!/bin/bash
git clone https://github.com/celestiaorg/celestia-node && cd celestia-node

git checkout tags/v0.21.9

make build
make install
make cel-key

mv $HOME/celestia-node/cel-key /usr/local/bin/ 
cel-key add bridge_wallet --keyring-backend test --node.type bridge --p2p.network celestia
cel-key list --node.type bridge --keyring-backend test --p2p.network celestia
celestia bridge init \
  --p2p.network celestia \
  --core.ip http://localhost \
  --core.port 9090 \
  --gateway \
  --gateway.addr 0.0.0.0 \
  --gateway.port 26659 \
  --rpc.addr 0.0.0.0 \
  --rpc.port 26658 \
  --keyring.accname bridge_wallet

sudo tee <<EOF >/dev/null /etc/systemd/system/celestia-bridge.service
[Unit]
Description=celestia-bridge Cosmos daemon
After=network-online.target
[Service]
User=$USER
ExecStart=$(which celestia) bridge start --archival \
  --p2p.network celestia \
  --gateway \
  --gateway.addr 0.0.0.0 \
  --gateway.port 26659 \
  --metrics.tls=false \
  --metrics \
  --metrics.endpoint=otel.mocha.celestia.observer
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable celestia-bridge
systemctl restart celestia-bridge && journalctl -u celestia-bridge -f -o cat
