#!/bin/bash

# Wrapper script to monitor firmware update and write status updates
# Takes firmware file path as argument

FIRMWARE_FILE=$1
STATUS_FILE="/home/root/.ne/update_status"

write_status() {
    local status=$1
    local message=$2
    local timestamp=$(date +%s)
    
    mkdir -p $(dirname "$STATUS_FILE")
    cat > "$STATUS_FILE" <<EOF
{
  "status": "$status",
  "message": "$message",
  "timestamp": $timestamp
}
EOF
}

if [ -z "$FIRMWARE_FILE" ]; then
    echo "Error: Firmware file not provided"
    write_status "error" "Firmware file not provided"
    exit 1
fi

if [ ! -f "$FIRMWARE_FILE" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_FILE"
    write_status "error" "Firmware file not found"
    exit 1
fi

echo "Starting firmware update wrapper for: $FIRMWARE_FILE"
write_status "extracting" "Extracting firmware archive..."

# Run the actual update script and capture output
WORKDIR="/home/root/autowork"
PUBKEY="/usr/share/usb_autorun/public.pem"

# Extract CPIO
echo "Validating CPIO..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

cpio -idmv --no-absolute-filenames -D "$WORKDIR" < "$FIRMWARE_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to extract CPIO"
    write_status "error" "Failed to extract firmware archive"
    exit 1
fi

echo "CPIO extracted successfully"

# Verify signature
echo "Verifying firmware signature..."
write_status "verifying" "Verifying firmware signature..."

openssl dgst -sha256 -verify "$PUBKEY" -signature "$WORKDIR/sign" "$WORKDIR/data.tar.gz" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Signature verification failed"
    write_status "error" "Firmware signature verification failed"
    exit 1
fi

echo "Signature verified"

# Extract tar
echo "Extracting firmware data..."
tar -zxf "$WORKDIR/data.tar.gz" -C "$WORKDIR" 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to extract firmware data"
    write_status "error" "Failed to extract firmware data"
    exit 1
fi

echo "Firmware data extracted"

# Run the installation script
echo "Starting firmware installation..."
write_status "installing" "Installing firmware..."

if [ -f "$WORKDIR/script.sh" ]; then
    chmod +x "$WORKDIR/script.sh"
    "$WORKDIR/script.sh" "$WORKDIR/result" 2>&1
    if [ $? -eq 0 ]; then
        echo "Firmware installation completed successfully"
        write_status "rebooting" "Rebooting device..."
        
        # Cleanup
        rm -rf "$WORKDIR"
        
        # Schedule reboot
        sleep 3
        reboot
        exit 0
    else
        echo "Error: Firmware installation script failed"
        write_status "error" "Firmware installation failed"
        exit 1
    fi
else
    echo "Error: Installation script not found"
    write_status "error" "Installation script not found in firmware"
    exit 1
fi
