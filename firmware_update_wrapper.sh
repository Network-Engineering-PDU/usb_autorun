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
TIMEOUT=300  # 5 minute timeout for extraction

# Extract CPIO
echo "Validating CPIO..."
write_status "extracting" "Extracting firmware archive... (validating CPIO)"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# Use timeout to prevent hanging
if ! timeout $TIMEOUT cpio -idm --no-absolute-filenames -D "$WORKDIR" < "$FIRMWARE_FILE" 2>&1; then
    if [ $? -eq 124 ]; then
        echo "Error: CPIO extraction timed out (took more than 5 minutes)"
        write_status "error" "Extraction timed out - firmware file may be corrupted"
    else
        echo "Error: Failed to extract CPIO"
        write_status "error" "Failed to extract firmware archive"
    fi
    exit 1
fi

echo "CPIO extracted successfully"
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
write_status "extracting" "Extracting firmware data archive..."
if ! timeout $TIMEOUT tar -zxf "$WORKDIR/data.tar.gz" -C "$WORKDIR" 2>&1; then
    if [ $? -eq 124 ]; then
        echo "Error: TAR extraction timed out"
        write_status "error" "TAR extraction timed out - firmware file may be large or corrupted"
    else
        echo "Error: Failed to extract firmware data"
        write_status "error" "Failed to extract firmware data"
    fi
    exit 1
fi

echo "Firmware data extracted"

# Run the installation script
echo "Starting firmware installation..."
write_status "installing" "Running firmware installation script..."

if [ ! -f "$WORKDIR/script.sh" ]; then
    echo "Error: Installation script not found"
    write_status "error" "No installation script found in firmware archive"
    exit 1
fi

chmod +x "$WORKDIR/script.sh"
if ! timeout $TIMEOUT "$WORKDIR/script.sh" "$WORKDIR/result" 2>&1; then
    if [ $? -eq 124 ]; then
        echo "Error: Installation script timed out"
        write_status "error" "Installation took too long (timeout)"
    else
        echo "Error: Firmware installation script failed"
        write_status "error" "Firmware installation failed"
    fi
    exit 1
fi

echo "Firmware installation completed successfully"
write_status "rebooting" "Rebooting device..."

# Cleanup
rm -rf "$WORKDIR"

# Schedule reboot
sleep 3
reboot
exit 0
