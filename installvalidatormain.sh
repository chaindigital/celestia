#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make gcc -y

CELESTIA_PORT=26
echo "export WALLET="ERN" >> $HOME/.bash_profile
echo "export MONIKER="ERN" >> $HOME/.bash_profile
echo "export CHAIN_ID="celestia"" >> $HOME/.bash_profile
echo "export CELESTIA_PORT="${CELESTIA_PORT}"" >> $HOME/.bash_profile
source $HOME/.bash_profile

cd ~
! [ -x "$(command -v go)" ] && {
VER="1.24.6"
wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
rm "go$VER.linux-amd64.tar.gz"
[ ! -f ~/.bash_profile ] && touch ~/.bash_profile
echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
source ~/.bash_profile
}
[ ! -d ~/go/bin ] && mkdir -p ~/go/bin
go version

cd $HOME 
rm -rf celestia-app 
git clone https://github.com/celestiaorg/celestia-app.git 
cd celestia-app/ 
APP_VERSION=v5.0.11 
git checkout tags/$APP_VERSION -b $APP_VERSION 
make install
make configure-v3
make enable-bbr

cd $HOME
rm -rf networks
git clone https://github.com/celestiaorg/networks.git

celestia-appd config node tcp://localhost:${CELESTIA_PORT}657
celestia-appd config keyring-backend os
celestia-appd config chain-id $CHAIN_ID
celestia-appd init ERN --chain-id celestia

wget -O $HOME/.celestia-app/config/genesis.json https://snapshots.kjnodes.com/celestia/genesis.json
wget -O $HOME/.celestia-app/config/addrbook.json https://snapshots.kjnodes.com/celestia/addrbook.json

SEEDS="400f3d9e30b69e78a7fb891f60d76fa3c73f0ecc@celestia.rpc.kjnodes.com:12059"
PEERS="5001de72be39622c9dc34f2117eccc3f3fca8a7a@34.91.84.93:26756,ff476823607d3c73da21662238083b10040d3ecc@65.108.44.124:26001,24a607a217cf12be29bae5b2e8151391bde2d8c8@65.108.12.253:15007,d7adf0cf48c95224c2440072b75b91fd55bfb83f@49.12.83.235:26656,fa759f8aad712dd59ec673e3fbb434e4c959e509@3.125.200.144:26656"
sed -i -e 's|^seeds *=.*|seeds = "'$SEEDS'"|; s|^persistent_peers *=.*|persistent_peers = "'$PEERS'"|' $HOME/.celestia-app/config/config.toml


sed -i.bak -e "s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:${CELESTIA_PORT}317\"%;
s%^address = \":8080\"%address = \":${CELESTIA_PORT}080\"%;
s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:${CELESTIA_PORT}090\"%; 
s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:${CELESTIA_PORT}091\"%; 
s%^address = \"0.0.0.0:8545\"%address = \"0.0.0.0:${CELESTIA_PORT}545\"%; 
s%^ws-address = \"0.0.0.0:8546\"%ws-address = \"0.0.0.0:${CELESTIA_PORT}546\"%" $HOME/.celestia-app/config/app.toml

sed -i.bak -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${CELESTIA_PORT}658\"%; 
s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://0.0.0.0:${CELESTIA_PORT}657\"%; 
s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:${CELESTIA_PORT}060\"%;
s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${CELESTIA_PORT}656\"%;
s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):${CELESTIA_PORT}656\"%;
s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${CELESTIA_PORT}660\"%" $HOME/.celestia-app/config/config.toml

sed -i -e "s/^pruning *=.*/pruning = \"nothing\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"50\"/" $HOME/.celestia-app/config/app.toml

EXTERNAL_ADDRESS=$(wget -qO- eth0.me)
sed -i.bak -e "s/^external-address = \"\"/external-address = \"$EXTERNAL_ADDRESS:26656\"/" $HOME/.celestia-app/config/config.toml

sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.002utia\"/" $HOME/.celestia-app/config/app.toml
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.celestia-app/config/config.toml
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.celestia-app/config/config.toml

sed -i -e "s|^recv_rate *=.*|recv_rate = 10485760|" -e "s|^send_rate *=.*|send_rate = 10485760|" -e "s|^ttl-num-blocks *=.*|ttl-num-blocks = 12|" $HOME/.celestia-app/config/config.toml

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

sudo apt install lz4 -y

curl -L https://snapshots.kjnodes.com/celestia/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.celestia-app

sudo systemctl daemon-reload
sudo systemctl enable celestia-appd
sudo systemctl restart celestia-appd && sudo journalctl -u celestia-appd -f
