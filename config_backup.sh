#!/bin/bash

# Script to zip and upload configuration files to S3 or download and unzip from S3
# Parameters:
#   $1 - Operation: 'upload' or 'download'
#   $2 - Filename: Name of the zip file to upload or download

# Error handling
set -e

# Check if aws CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if parameters are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <upload|download> <filename>"
    echo "Example: $0 upload config_backup.zip"
    echo "         $0 download config_backup.zip"
    exit 1
fi

OPERATION=$1
FILENAME=$2
CONFIG_DIR="/var/minecraft"
CONFIG_FILES=("server.properties" "whitelist.json" "banned-ips.json" "banned-players.json" "ops.json")
S3_BUCKET=$(aws ssm get-parameter --name "/minecraft/s3_bucket" --query "Parameter.Value" --output text 2>/dev/null || echo "")

# If S3_BUCKET wasn't found in Parameter Store, try to get it from the environment
if [ -z "$S3_BUCKET" ]; then
    if [ -z "$MINECRAFT_S3_BUCKET" ]; then
      S3_BUCKET="berbbobs-minecraft-assets"
    else
        S3_BUCKET=$MINECRAFT_S3_BUCKET
    fi
fi

# Function to upload configuration files to S3
upload_to_s3() {
    echo "Starting configuration backup process..."
    
    # Check if config directory exists
    if [ ! -d "$CONFIG_DIR" ]; then
        echo "Error: Config directory $CONFIG_DIR does not exist."
        exit 1
    fi
    
    # Create temporary directory for zip operation
    TEMP_DIR=$(mktemp -d)
    TEMP_CONFIG_DIR="$TEMP_DIR/config"
    mkdir -p "$TEMP_CONFIG_DIR"
    
    # Copy config files to temp directory
    echo "Copying configuration files..."
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$CONFIG_DIR/$file" ]; then
            cp "$CONFIG_DIR/$file" "$TEMP_CONFIG_DIR/"
        else
            echo "Warning: $file not found in $CONFIG_DIR, skipping"
        fi
    done
    
    echo "Zipping configuration files..."
    cd "$TEMP_DIR"
    zip -r "$FILENAME" config
    
    echo "Uploading zip file to S3..."
    aws s3 cp "$TEMP_DIR/$FILENAME.zip" "s3://$S3_BUCKET/configs/$FILENAME.zip"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    echo "Configuration backup completed successfully! File uploaded to s3://$S3_BUCKET/configs/$FILENAME"
}

# Function to download configuration files from S3
download_from_s3() {
    echo "Starting configuration restore process..."
    
    # Create temporary directory for download
    TEMP_DIR=$(mktemp -d)
    
    echo "Downloading zip file from S3..."
    aws s3 cp "s3://$S3_BUCKET/configs/$FILENAME.zip" "$TEMP_DIR/$FILENAME.zip"
    
    # Check if config directory exists, create if not
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    else
        echo "Warning: Configuration files may exist. They will be backed up and replaced."
        # Backup existing config files just in case
        BACKUP_DIR="$CONFIG_DIR/config_backup_$(date +%Y%m%d%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        for file in "${CONFIG_FILES[@]}"; do
            if [ -f "$CONFIG_DIR/$file" ]; then
                echo "Backing up $file to $BACKUP_DIR"
                cp "$CONFIG_DIR/$file" "$BACKUP_DIR/"
            fi
        done
    fi
    
    echo "Extracting zip file..."
    unzip -o "$TEMP_DIR/$FILENAME.zip" -d "$TEMP_DIR"
    
    # Move extracted config files to minecraft directory
    for file in "${CONFIG_FILES[@]}"; do
        if [ -f "$TEMP_DIR/config/$file" ]; then
            echo "Restoring $file"
            cp "$TEMP_DIR/config/$file" "$CONFIG_DIR/"
        fi
    done
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    echo "Configuration restore completed successfully!"
}

# Main execution
case "$OPERATION" in
    upload)
        upload_to_s3
        ;;
    download)
        download_from_s3
        ;;
    *)
        echo "Error: Invalid operation. Use 'upload' or 'download'."
        exit 1
        ;;
esac

exit 0