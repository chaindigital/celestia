#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip -y

sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.24.6.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
eval $(echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh)
eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile)
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile
go version

cd $HOME
rm -rf celestia-app
git clone https://github.com/celestiaorg/celestia-app.git
cd celestia-app
git checkout v6.4.10-mocha
make install

celestia-appd config chain-id mocha-4
celestia-appd config keyring-backend file
celestia-appd config node tcp://localhost:26657

celestia-appd init Node --chain-id mocha-4

wget -O $HOME/.celestia-app/config/genesis.json https://testnets.chaindigital.io/celestia/genesis.json
wget -O $HOME/.celestia-app/config/addrbook.json https://testnets.chaindigital.io/celestia/addrbook.json

SEEDS="5d0bf034d6e6a8b5ee31a2f42f753f1107b3a00e@celestia-testnet-seed.itrocket.net:11656"
PEERS="daf2cecee2bd7f1b3bf94839f993f807c6b15fbf@celestia-testnet-peer.itrocket.net:11656,d6c13af818704c64a42f77d74ab6ab6dc4e164dd@65.108.74.218:40656,cee58e7a8724fea3022be98898d7346d12a0ef80@164.152.162.119:36656,aea85cf7e03258e9b02cdd8854f64857e9046d73@89.187.156.100:26698,5f22818fcf0d8cab31a490ae038b4f06a5632685@95.217.225.107:26656,49e0ad1852417267c60c63c2a86ea9e84c47c0ca@13.213.66.56:26656,5c2a752c9b1952dbed075c56c600c3a79b58c395@195.3.221.9:27206,f05e6a065b772dda4c7c0cbed40894a8c43416c7@170.64.159.104:26656,f9e950870eccdb40e2386896d7b6a7687a103c99@88.99.219.120:43656,8badeed7f48eefd5d43af7eb7662f2b578304a27@138.201.63.38:26686,e1b058e5cfa2b836ddaa496b10911da62dcf182e@164.152.161.199:36656,15eb02dd78fe034a9bb35ab325290004ddf67c9a@138.201.122.61:36656,a831cf42d79aded9d25efd71b1a6629311c2f644@95.217.120.205:11656,878e4d1b5300754f5797c23f03e8f95259ed9192@5.9.115.9:21656,8f282e0237ec45dd0a959bd3e2872f088133a58a@31.7.196.17:26656,3b5cfaef16c0affb426c9dd159cd3da6049159c2@217.160.102.31:26656,edafdf47c443344fb940a32ab9d2067c482e59df@84.32.71.47:26656,24f79d2f249d491daae85fdc774203c47b2fbcab@91.191.213.10:26656,66ff3e802fe41b193c9ab367637c71b1be7e2e7b@65.109.49.115:11656"
sed -i -e "/^\[p2p\]/,/^\[/{s/^[[:space:]]*seeds *=.*/seeds = \"$SEEDS\"/}" \
       -e "/^\[p2p\]/,/^\[/{s/^[[:space:]]*persistent_peers *=.*/persistent_peers = \"$PEERS\"/}" $HOME/.celestia-app/config/config.toml

sed -i -e "s|^target_height_duration *=.*|timeout_commit = \"11s\"|" $HOME/.celestia-app/config/config.toml

sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.002utia\"|" $HOME/.celestia-app/config/app.toml

sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"50\"/" $HOME/.celestia-app/config/app.toml

sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.celestia-app/config/config.toml
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.celestia-app/config/config.toml

sudo modprobe tcp_bbr
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

celestia-appd tendermint unsafe-reset-all --home $HOME/.celestia-app 

sudo tee /etc/systemd/system/celestia-appd.service > /dev/null <<EOF
[Unit]
Description=celestia
After=network-online.target

[Service]
User=$USER
ExecStart=$(which celestia-appd) start --home $HOME/.celestia-app/
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cd $HOME
rm -rf ~/.celestia-app/data
mkdir -p ~/.celestia-app/data
curl -L https://testnets.chaindigital.io/celestia/snap_celestia.tar.lz4 | lz4 -c -d - | tar -x -C $HOME/.celestia-app

sudo systemctl daemon-reload
sudo systemctl enable celestia-appd
sudo systemctl restart celestia-appd && sudo journalctl -u celestia-appd -f
