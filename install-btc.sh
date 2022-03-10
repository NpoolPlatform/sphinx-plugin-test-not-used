#!/bin/bash

function info() {
  echo "  <I> -> $1 ~"
}

function usage() {
  echo "Usage:"
  echo "  $1 -[u:p:v:P:t:H:]"
  echo "    -u            Rpc user"
  echo "    -p            Rpc password"
  echo "    -v            BTC version"
  echo "    -P            Sphinx proxy addr"
  echo "    -t            Traefik ip"
  echo "    -H            Show this help"
  [ "xtrue" == "x$2" ] && exit 0
  return 0
}

while getopts 'u:p:v:P:t:' OPT; do
  case $OPT in
    u) RPC_USER=$OPTARG           ;;
    p) RPC_PASSWORD=$OPTARG       ;;
    v) BTC_VERSION=$OPTARG        ;;
    P) SPHINX_PROXY_ADDR=$OPTARG  ;;
    t) TRAEFIK_IP=$OPTARG         ;;
    *) usage $0                   ;;
  esac
done

LOG_FILE=/var/log/install-btc.log
echo > $LOG_FILE
info "RUN install btc" >> $LOG_FILE

function install_btc() {
  BTC_TAR=bitcoin-$BTC_VERSION-x86_64-linux-gnu.tar.gz
  info "download $BTC_TAR" >> $LOG_FILE
  curl -o /home/$BTC_TAR https://bitcoin.org/bin/bitcoin-core-$BTC_VERSION/$BTC_TAR >> $LOG_FILE 2>&1
  cd /home
  rm -rf bitcoin-$BTC_VERSION
  tar xf $BTC_TAR
  kill -9 `pgrep -f 'bitcoind'`
  sleep 5
  rm -rf /usr/local/bin/bitcoind /usr/local/bin/bitcoin-cli
  cp bitcoin-$BTC_VERSION/bin/bitcoind /usr/local/bin/
  cp bitcoin-$BTC_VERSION/bin/bitcoin-cli /usr/local/bin/
  bitcoind -regtest -addresstype=legacy -daemon -conf=/root/.bitcoin/bitcoin.conf -rpcuser=$RPC_USER -rpcpassword=$RPC_PASSWORD >> $LOG_FILE 2>&1
  sed -i 's/#rpcpassword=.*/rpcpassword='$RPC_PASSWORD'/g' /home/bitcoin.conf
  sed -i 's/#rpcuser=.*/rpcuser='$RPC_USER'/g' /home/bitcoin.conf
  echo "rpcwallet=my_wallet" >> /home/bitcoin.conf
  cp /home/bitcoin.conf /root/.bitcoin
}

function install_sphinx_plugin() {
  mkdir -p /etc/SphinxPlugin /opt/sphinx-plugin
  rm -rf /home/sphinx-plugin
  info "clone sphinx-plugin" >> $LOG_FILE
  git clone https://github.com/NpoolPlatform/sphinx-plugin.git /home/sphinx-plugin >> $LOG_FILE 2>&1
  cd /home/sphinx-plugin
  sed -i 's/sphinx_proxy_addr.*/sphinx_proxy_addr: "'$SPHINX_PROXY_ADDR'"/g' cmd/sphinx-plugin/SphinxPlugin.viper.yaml
  sed -i 's/ENV_COIN_API=/ENV_COIN_API=127.0.0.1:18443/g' systemd/sphinx-plugin.service
  sed -i '/ENV_COIN_API=/a\Environment="ENV_COIN_NET=test"' systemd/sphinx-plugin.service
  sed -i '/ENV_COIN_API=/a\Environment="ENV_COIN_TYPE=BTC"' systemd/sphinx-plugin.service
  cp cmd/sphinx-plugin/SphinxPlugin.viper.yaml /etc/SphinxPlugin
  cp systemd/sphinx-plugin.service /etc/systemd/system
  export GOPROXY=https://goproxy.cn
  info "make verify" >> $LOG_FILE
  make verify >> $LOG_FILE 2>&1
  rm -rf /opt/sphinx-plugin/sphinx-plugin
  cp output/linux/amd64/sphinx-plugin /opt/sphinx-plugin/
  echo "$TRAEFIK_IP sphinx.proxy.api.npool.top sphinx.proxy.api.xpool.top" >> /etc/hosts
}

install_btc

systemctl stop sphinx-plugin
install_sphinx_plugin
systemctl daemon-reload
systemctl start sphinx-plugin
systemctl enable sphinx-plugin

bitcoin-cli -regtest createwallet my_wallet
bitcoin-cli -regtest -generate 101
while true; do
  bitcoin-cli -regtest -generate 1
  sleep 300
done
