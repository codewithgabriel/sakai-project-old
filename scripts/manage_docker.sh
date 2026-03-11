#!/bin/bash

# Sakai Docker Management Script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Command Discovery & Auto-Install ---
function install_docker() {
    echo -e "${BLUE}[INFO]${NC} Docker not found. Starting automatic installation on Ubuntu..."
    
    # Update package index and install prerequisites
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources
    echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    
    # Install Docker and Compose plugin
    echo -e "${BLUE}[INFO]${NC} Installing Docker Engine and Docker Compose V2..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group if possible
    sudo usermod -aG docker $USER
    
    echo -e "${GREEN}[SUCCESS]${NC} Docker and Docker Compose installed successfully."
    echo -e "${BLUE}[TIP]${NC} You might need to log out and back in for group changes to take effect."
    
    DOCKER_COMPOSE="docker compose"
}

# Detect if we should use 'docker compose' (V2) or 'docker-compose' (V1)
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose --version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
else
    # Try to install if not found
    install_docker
fi
echo -e "${BLUE}[INFO]${NC} Using: $DOCKER_COMPOSE"

function show_help() {
    echo "Usage: ./manage_docker.sh [command]"
    echo ""
    echo "Commands:"
    echo "  build   Build the Sakai Docker image and start services"
    echo "  start   Start existing Sakai and DB containers"
    echo "  stop    Stop services"
    echo "  logs    Watch the Sakai application logs"
    echo "  status  Check the status of Docker services"
    echo "  clean   Remove containers, networks, and VOLUMES (Warning: data loss!)"
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

case "$1" in
    build)
        echo -e "${BLUE}[INFO]${NC} Building and starting Sakai services..."
        $DOCKER_COMPOSE up -d --build
        echo -e "${GREEN}[SUCCESS]${NC} Build initiated. Run './manage_docker.sh logs' to monitor startup."
        ;;
    start)
        echo -e "${BLUE}[INFO]${NC} Starting Sakai services..."
        $DOCKER_COMPOSE up -d
        echo -e "${GREEN}[SUCCESS]${NC} Services started."
        ;;
    stop)
        echo -e "${BLUE}[INFO]${NC} Stopping Sakai services..."
        $DOCKER_COMPOSE stop
        echo -e "${GREEN}[SUCCESS]${NC} Services stopped."
        ;;
    logs)
        $DOCKER_COMPOSE logs -f sakai
        ;;
    status)
        $DOCKER_COMPOSE ps
        ;;
    clean)
        echo -e "${RED}[WARNING]${NC} This will delete ALL your Sakai data (database & files)!"
        read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $DOCKER_COMPOSE down -v
            echo -e "${GREEN}[SUCCESS]${NC} Cleaned all Docker resources and volumes."
        else
            echo -e "${BLUE}[INFO]${NC} Operation cancelled."
        fi
        ;;
    *)
        show_help
        ;;
esac
