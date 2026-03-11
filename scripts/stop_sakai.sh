#!/bin/bash

# --- Colors for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Shutting down Sakai safely..."

# 1. Stop the service
sudo systemctl stop sakai

# 2. Wait for the process to actually exit
echo -ne "${BLUE}[INFO]${NC} Waiting for Tomcat process to exit..."
while pgrep -f "org.apache.catalina.startup.Bootstrap" > /dev/null; do
    echo -n "."
    sleep 2
done

echo ""
echo -e "${GREEN}[SUCCESS]${NC} Sakai has shut down successfully."
