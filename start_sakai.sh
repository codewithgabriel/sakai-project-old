#!/bin/bash

# --- Colors for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

LOG_FILE="/opt/tomcat/logs/catalina.out"

echo -e "${BLUE}[INFO]${NC} Starting Sakai..."

# 1. Check if MySQL is running
if ! systemctl is-active --quiet mysql; then
    echo -e "${YELLOW}[WARN]${NC} MySQL is not running. Starting it now..."
    sudo systemctl start mysql
fi

# 2. Start Sakai service
sudo systemctl start sakai

echo -e "${BLUE}[INFO]${NC} Sakai service started. Monitoring logs for completion..."
echo -e "${BLUE}[INFO]${NC} This usually takes 5-10 minutes. Press Ctrl+C to stop monitoring (Sakai will continue starting in background)."

# 3. Monitor logs for startup message
# We use sudo tail -n 0 -f to ensure we only see NEW logs
(sudo tail -n 0 -f "$LOG_FILE" &) | grep -q "Server startup in"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} Sakai has started successfully!"
    echo -e "${GREEN}[SUCCESS]${NC} Access it at: http://localhost:8080/portal"
    # Kill the background tail process
    sudo pkill -f "tail -f $LOG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Startup monitoring interrupted or failed."
fi
