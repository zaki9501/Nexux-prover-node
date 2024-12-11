#!/bin/bash

# Displaying logo
curl -s https://raw.githubusercontent.com/zaki9501/piki-nodes/refs/heads/main/logo.sh
sleep 5

BOLD=$(tput bold)
NORMAL=$(tput sgr0) # sgr0 resets all attributes
PINK=$(tput setaf 5) # setaf 5 is magenta/pink on most terminals
GREEN=$(tput setaf 2) # setaf 2 is green
RESET=$(tput sgr0)

show() {
    local message=$1
    local type=$2
    local color style emoji timestamp

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$type" in
        "error")
            color=$PINK
            style=$BOLD
            emoji="❌"
            ;;
        "progress")
            color=$PINK
            style=$BOLD
            emoji="⏳"
            ;;
        *)
            color=$GREEN
            style=$BOLD
            emoji="✅"
            ;;
    esac

    echo -e "[${timestamp}] ${color}${style}${emoji} $message${RESET}"
}

SERVICE_NAME="nexus"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Ensure the script runs in an interactive shell
export NONINTERACTIVE=0

# Function to install a package if not installed
install_package() {
    if ! dpkg -l | grep -qw "$1"; then
        show "Installing $1..." "progress"
        if ! sudo apt install -y "$1"; then
            show "Failed to install $1." "error"
            exit 1
        fi
    else
        show "$1 is already installed."
    fi
}

# Install Rust
show "Installing Rust..." "progress"
if ! source <(wget -qO- https://raw.githubusercontent.com/zaki9501/piki-nodes/refs/heads/main/rust.sh); then
    show "Failed to install Rust." "error"
    exit 1
fi

# Update package list
show "Updating package list..." "progress"
if ! sudo apt update; then
    show "Failed to update package list." "error"
    exit 1
fi

# Ensure Git is installed
install_package git

# Remove existing repository if present
if [ -d "$HOME/network-api" ]; then
    show "Removing existing network-api directory..." "progress"
    rm -rf "$HOME/network-api"
fi

# Clone the Nexus-XYZ repository
show "Cloning Nexus-XYZ network API repository..." "progress"
if ! git clone https://github.com/nexus-xyz/network-api.git "$HOME/network-api"; then
    show "Failed to clone the repository." "error"
    exit 1
fi

# Navigate to CLI directory
cd "$HOME/network-api/clients/cli" || exit 1

# Install dependencies
show "Installing required dependencies..." "progress"
DEPENDENCIES=(wget build-essential pkg-config libssl-dev unzip)
for PACKAGE in "${DEPENDENCIES[@]}"; do
    install_package "$PACKAGE"
done

# Install Protobuf
PROTOC_VERSION="21.5"
PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"
wget "$PROTOC_URL" -q -O protoc.zip
unzip -o protoc.zip -d protoc
sudo mv protoc/bin/protoc /usr/local/bin/
sudo mv protoc/include/* /usr/local/include/ 2>/dev/null || show "Skipping conflicting include files." "progress"
rm -rf protoc protoc.zip

# Stop and disable service if already running
if systemctl is-active --quiet "$SERVICE_NAME.service"; then
    show "$SERVICE_NAME.service is currently running. Stopping and disabling it..." "progress"
    sudo systemctl stop "$SERVICE_NAME.service"
    sudo systemctl disable "$SERVICE_NAME.service"
else
    show "$SERVICE_NAME.service is not running."
fi

# Create systemd service file
show "Creating systemd service..." "progress"
sudo bash -c "cat > $SERVICE_FILE << 'EOF'
[Unit]
Description=Nexus XYZ Prover Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/network-api/clients/cli
Environment=NONINTERACTIVE=1
ExecStart=$HOME/.cargo/bin/cargo run --release --bin prover -- beta.orchestrator.nexus.xyz
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# Reload systemd and start the service
show "Reloading systemd and starting the service..." "progress"
sudo systemctl daemon-reload
sudo systemctl start "$SERVICE_NAME.service"
sudo systemctl enable "$SERVICE_NAME.service"

# Prompt for Prover ID
PROVER_ID=""

while [[ ! $PROVER_ID =~ ^[A-Za-z0-9]{20,}$ ]]; do
    if [[ -n "$PROVER_ID" ]]; then
        show "Invalid Prover ID. Please enter a valid ID." "error"
    fi

    # Use /dev/tty for reading input directly from the terminal
    echo -ne "Enter Prover ID (must be 26 characters): " > /dev/tty
    read PROVER_ID < /dev/tty
    echo "DEBUG: Entered Prover ID: $PROVER_ID" > /dev/tty
done

# Update the Prover ID in the .nexus/prover-id file
if [ -f "$HOME/.nexus/prover-id" ]; then
    show "Updating Prover ID in .nexus/prover-id..." "progress"
    echo "$PROVER_ID" > "$HOME/.nexus/prover-id"
    show "Prover ID updated successfully."
else
    show "Prover ID file not found." "error"
    exit 1
fi

# Restart the Nexus service
show "Restarting the Nexus service..." "progress"
sudo systemctl restart "$SERVICE_NAME.service"

# Completion message
show "Nexus Prover installation and service setup complete!"
show "You can check Nexus Prover logs using: journalctl -u $SERVICE_NAME.service -fn 50"
