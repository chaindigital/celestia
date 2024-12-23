#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make gcc -y

cd ~
! [ -x "$(command -v go)" ] && {
VER="1.22.5"
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

git clone https://github.com/celestiaorg/celestia-app && cd celestia-app
git checkout v3.2.0
make install

cd $HOME
git clone https://github.com/celestiaorg/networks

celestia-appd init ERN --chain-id celestia

wget -O $HOME/.celestia-app/config/genesis.json https://snapshots.kjnodes.com/celestia/genesis.json
wget -O $HOME/.celestia-app/config/addrbook.json https://snapshots.kjnodes.com/celestia/addrbook.json

sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.002utia\"/;" ~/.celestia-app/config/app.toml

EXTERNAL_ADDRESS=$(wget -qO- eth0.me)
sed -i.bak -e "s/^external_address = \"\"/external_address = \"$EXTERNAL_ADDRESS:26656\"/" $HOME/.celestia-app/config/config.toml

SSEEDS="400f3d9e30b69e78a7fb891f60d76fa3c73f0ecc@celestia.rpc.kjnodes.com:12059"
PEERS="5001de72be39622c9dc34f2117eccc3f3fca8a7a@34.91.84.93:26756,ff476823607d3c73da21662238083b10040d3ecc@65.108.44.124:26001,24a607a217cf12be29bae5b2e8151391bde2d8c8@65.108.12.253:15007,d7adf0cf48c95224c2440072b75b91fd55bfb83f@49.12.83.235:26656,fa759f8aad712dd59ec673e3fbb434e4c959e509@3.125.200.144:26656"
sed -i -e 's|^seeds *=.*|seeds = "'$SEEDS'"|; s|^persistent_peers *=.*|persistent_peers = "'$PEERS'"|' $HOME/.celestia-app/config/config.toml

pruning="nothing"
pruning_keep_recent="1000"
pruning_interval="10"
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.celestia-app/config/app.toml && \
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.celestia-app/config/app.toml && \
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.celestia-app/config/app.toml

sed -i -e "s|^recv_rate *=.*|recv_rate = 10485760|" -e "s|^send_rate *=.*|send_rate = 10485760|" -e "s|^ttl-num-blocks *=.*|ttl-num-blocks = 12|" $HOME/.celestia-app/config/config.toml
​
sudo modprobe tcp_bbr
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

cd $HOME
sudo apt install aria2 -y
rm -rf ~/.celestia-app/data
mkdir -p ~/.celestia-app/data
SNAP_NAME=$(curl -s https://snaps.qubelabs.io/celestia/ | \
    egrep -o ">celestia.*tar" | tr -d ">")
aria2c -x 16 -s 16 -o celestia-snap.tar "https://snaps.qubelabs.io/celestia/${SNAP_NAME}"
tar xf celestia-snap.tar -C ~/.celestia-app/data/

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
