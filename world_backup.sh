#!/bin/bash

# Script to zip and upload a directory to S3 or download and unzip from S3
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
    echo "Example: $0 upload world_backup.zip"
    echo "         $0 download world_backup.zip"
    exit 1
fi

OPERATION=$1
FILENAME=$2
WORLD_DIR="/opt/minecraft/world"
S3_BUCKET=$(aws ssm get-parameter --name "/minecraft/s3_bucket" --query "Parameter.Value" --output text 2>/dev/null || echo "")

# If S3_BUCKET wasn't found in Parameter Store, try to get it from the environment
if [ -z "$S3_BUCKET" ]; then
    if [ -z "$MINECRAFT_S3_BUCKET" ]; then
        S3_BUCKET="berbbobs-minecraft-assets"
    else
        S3_BUCKET=$MINECRAFT_S3_BUCKET
    fi
fi

# Function to upload directory to S3
upload_to_s3() {
    echo "Starting backup process..."
    
    # Check if world directory exists
    if [ ! -d "$WORLD_DIR" ]; then
        echo "Error: World directory $WORLD_DIR does not exist."
        exit 1
    fi
    
    # Create temporary directory for zip operation
    TEMP_DIR=$(mktemp -d)
    
    echo "Zipping world directory..."
    # Using relative paths inside the zip file
    cd $(dirname "$WORLD_DIR")
    zip -r "$TEMP_DIR/$FILENAME" $(basename "$WORLD_DIR")
    
    echo "Uploading zip file to S3..."
    aws s3 cp "$TEMP_DIR/$FILENAME.zip" "s3://$S3_BUCKET/worlds/$FILENAME.zip"

    # Cleanup
    rm -rf "$TEMP_DIR"

    echo "Backup completed successfully! File uploaded to s3://$S3_BUCKET/worlds/$FILENAME"
}

# Function to download directory from S3
download_from_s3() {
    echo "Starting restore process..."

    # Create temporary directory for download
    TEMP_DIR=$(mktemp -d)

    echo "Downloading zip file from S3..."
    aws s3 cp "s3://$S3_BUCKET/$FILENAME.zip" "$TEMP_DIR/$FILENAME.zip"

    # Check if world directory exists, create if not
    if [ ! -d "$WORLD_DIR" ]; then
        mkdir -p "$WORLD_DIR"
    else
        echo "Warning: World directory already exists. Contents will be replaced."
        # Backup existing directory just in case
        BACKUP_DIR="$WORLD_DIR.bak.$(date +%Y%m%d%H%M%S)"
        echo "Creating backup of existing world at $BACKUP_DIR"
        cp -r "$WORLD_DIR" "$BACKUP_DIR"

        # Clean world directory
        rm -rf "$WORLD_DIR"/*
    fi

    echo "Extracting zip file..."
    unzip -o "$TEMP_DIR/$FILENAME.zip" -d $(dirname "$WORLD_DIR")
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    echo "Restore completed successfully!"
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

exit 0r