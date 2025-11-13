#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make gcc -y

cd ~
rm -rf $HOME/go
sudo rm -rf /usr/local/go
cd $HOME
curl https://dl.google.com/go/go1.24.6.linux-amd64.tar.gz | sudo tar -C/usr/local -zxvf -
cat <<'EOF' >>$HOME/.profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
source $HOME/.profile
go version

git clone https://github.com/celestiaorg/celestia-app && cd celestia-app
git checkout v6.2.5-mocha
make install

cd $HOME
git clone https://github.com/celestiaorg/networks

celestia-appd init ERN --chain-id mocha-4

wget -O $HOME/.celestia-app/config/genesis.json https://testnets.chaindigital.io/celestia/genesis.json
wget -O $HOME/.celestia-app/config/addrbook.json https://testnets.chaindigital.io/celestia/addrbook.json

sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.002utia\"/;" ~/.celestia-app/config/app.toml

EXTERNAL_ADDRESS=$(wget -qO- eth0.me)
sed -i.bak -e "s/^external_address = \"\"/external_address = \"$EXTERNAL_ADDRESS:26656\"/" $HOME/.celestia-app/config/config.toml

SEEDS=""
PEERS="77f8a816610d521cecb4c62f834891e1a6257b09@65.108.207.143:26656"
sed -i -e 's|^seeds *=.*|seeds = "'$SEEDS'"|; s|^persistent_peers *=.*|persistent_peers = "'$PEERS'"|' $HOME/.celestia-app/config/config.toml

pruning="nothing"
pruning_keep_recent="1000"
pruning_interval="10"
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.celestia-app/config/app.toml && \
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.celestia-app/config/app.toml && \
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.celestia-app/config/app.toml

cd $HOME
sudo apt install lz4 -y
rm -rf ~/.celestia-app/data
mkdir -p ~/.celestia-app/data
curl -L https://celestia-snapshots.chaindigital.io/testnets/snap_archive_celestia.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.celestia-app/

sudo tee /etc/systemd/system/celestia-appd.service > /dev/null <<EOF
[Unit]
Description=celestia-appd
After=network-online.target

[Service]
User=$USER
ExecStart=$(which celestia-appd) start
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable celestia-appd

systemctl restart celestia-appd && journalctl -u celestia-appd -f -o cat
