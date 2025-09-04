#!/bin/bash
set -e

# === Terminal Colors ===
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
BLUE_LINE="\e[38;5;220m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"

# === Header Display ===
function show_header() {
    clear
    echo -e "\e[38;5;220m"
    echo "███████╗██╗         "
    echo "██╔════╝██║         "
    echo "█████╗  ██║         "
    echo "██╔══╝  ██║         "
    echo "███████║███████╗    "
    echo "╚══════╝╚══════╝    "
    echo -e "\e[0m"
    echo -e "🚀 \e[1;33mPaxi Docker Mod\e[0m - Powered by \e[1;33mHallosayael\e[0m 🚀"
    echo ""
}

# === Internet check ===
echo "🔍 Checking internet connection..."
if ! ping -c 1 -W 2 google.com &> /dev/null; then
  echo "❌ No internet connection. Please check your network and retry."
  exit 1
fi
echo "✅ Internet OK!"

### === Required parameters ===
REQUIRED_CPU=4
REQUIRED_RAM_GB=8
REQUIRED_DISK_GB=400

CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
DISK_SPACE=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')

# === Hardware checks ===
[[ "$CPU_CORES" -lt "$REQUIRED_CPU" ]] && echo "❌ Insufficient CPU cores ($CPU_CORES)" && exit 1
[[ "$TOTAL_MEM" -lt "$REQUIRED_RAM_GB" ]] && echo "❌ Insufficient RAM ($TOTAL_MEM GB)" && exit 1
[[ "$DISK_SPACE" -lt "$REQUIRED_DISK_GB" ]] && echo "❌ Insufficient Disk ($DISK_SPACE GB)" && exit 1

echo "✅ Hardware OK: ${CPU_CORES} cores, ${TOTAL_MEM}GB RAM, ${DISK_SPACE}GB disk"

### === Install dependencies ===
echo "🔍 Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    ca-certificates curl gnupg lsb-release git make unzip jq

### === Install Docker ===
if ! command -v docker &> /dev/null; then
  echo "🔧 Installing Docker..."
  sudo mkdir -p /etc/apt/keyrings
  curl --retry 3 -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker && sudo systemctl start docker
  sudo usermod -aG docker $USER
  echo "✅ Docker installed. Please re-login or run 'newgrp docker' to refresh permissions."
else
  echo "✅ Docker is already installed."
fi

### === Clone and build Paxi ===
PAXI_REPO="https://github.com/paxi-web3/paxi"
PAXI_TAG="latest-main"
if [ ! -d "paxi" ]; then
  git clone $PAXI_REPO
  cd paxi
else
  cd paxi
fi
git checkout $PAXI_TAG
make docker
cd ..

### === Node setup variables ===
CHAIN_ID="paxi-mainnet"
BINARY_NAME="./paxid"
PAXI_PATH="$HOME/paxid"
PAXI_DATA_PATH="$HOME/paxid/paxi"
DOCKER_IMAGE="paxi-node"
DOCKER_PAXI_DATA_PATH="/root/paxi"
RPC_URL="http://rpc.paxi.info"
SNAPSHOT_DOWNLOAD_HOST="http://snapshot.paxi.info"

mkdir -p "$PAXI_DATA_PATH"

# === Prompt user input ===
read -p "Node name: " NODE_MONIKER
[[ -z "$NODE_MONIKER" ]] && echo "❌ Node name cannot be empty." && exit 1
read -p "Wallet name (key name): " KEY_NAME
[[ -z "$KEY_NAME" ]] && echo "❌ Wallet name cannot be empty." && exit 1
read -p "Emergency contact email: " SECURITY_CONTACT
[[ -z "$SECURITY_CONTACT" ]] && echo "❌ Emergency contact cannot be empty." && exit 1
read -p "Website/contact link: " WEBSITE

# === Initialize node ===
if [ ! -f "$PAXI_DATA_PATH/config/genesis.json" ]; then
  docker run --rm -v $PAXI_DATA_PATH:$DOCKER_PAXI_DATA_PATH \
    $DOCKER_IMAGE \
    $BINARY_NAME init "$NODE_MONIKER" --chain-id $CHAIN_ID
  sudo chown -R $(whoami) $PAXI_PATH
fi

curl --retry 3 -s "$RPC_URL/genesis?" | jq -r .result.genesis > "$PAXI_DATA_PATH/config/genesis.json"

# === State sync setup ===
BLOCK_OFFSET=100
LATEST_HEIGHT=$(curl --retry 3 -s "$RPC_URL/block" | jq -r .result.block.header.height)
TRUST_HEIGHT=$(( ( (LATEST_HEIGHT - BLOCK_OFFSET) / BLOCK_OFFSET ) * BLOCK_OFFSET ))
TRUST_HASH=$(curl --retry 3 -s "$RPC_URL/block?height=$TRUST_HEIGHT" | jq -r .result.block_id.hash)

[[ ! "$LATEST_HEIGHT" =~ ^[0-9]+$ ]] && echo "❌ Failed to get trust height" && exit 1

# === WASM snapshot ===
WASM_SNAPSHOT_URL=$(curl --retry 3 -s "$SNAPSHOT_DOWNLOAD_HOST/utils/latest_wasm_snapshot" | jq -r .url)
if curl --retry 3 -f -o wasm_snapshot.zip "$WASM_SNAPSHOT_URL"; then
  mkdir -p "$PAXI_DATA_PATH/wasm/wasm/state/wasm"
  unzip -o wasm_snapshot.zip -d "$PAXI_DATA_PATH/wasm/wasm/state/wasm"
  rm wasm_snapshot.zip
  echo "✅ Wasm snapshot OK"
else
  echo "⚠️ Failed to download wasm snapshot, please get it manually."
fi

echo "✅ Node initialized successfully! Follow on-screen commands to start validator."
