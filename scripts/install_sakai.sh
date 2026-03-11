#!/bin/bash

# ==============================================================================
# Sakai 23 Automated Installer - "The Magic Script"
# ==============================================================================
# This script automates the installation of Sakai LMS 23 on a fresh Ubuntu 20.04/22.04 LTS system.
# It handles:
#   - System Updates & Prerequisites
#   - Java 11 Installation
#   - MySQL 8.0 Installation & Configuration
#   - Maven 3.9 Installation
#   - Tomcat 9 Installation & Optimization
#   - Sakai Source Cloning, Configuration, Build & Deployment
#   - Systemd Service Creation
#
# Usage: sudo ./install_sakai.sh
# ==============================================================================

set -e # Exit on error
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo -e "${RED}[ERROR]${NC} Command \"${last_command}\" failed with exit code $?."' ERR

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration Variables ---
SAKAI_DB_USER="sakaiuser"
SAKAI_DB_PASS="sakaipassword" # CHANGE THIS FOR PRODUCTION!
SAKAI_DB_NAME="sakaidatabase"
TOMCAT_VERSION="9.0.85" # Check https://tomcat.apache.org/download-90.cgi for latest
MAVEN_VERSION="3.9.6"   # Check https://maven.apache.org/download.cgi for latest
SAKAI_VERSION="23.x"    # Git branch to clone

INSTALL_DIR="/opt"
TOMCAT_HOME="$INSTALL_DIR/tomcat"
MAVEN_HOME="$INSTALL_DIR/maven"
SAKAI_SRC_DIR="$INSTALL_DIR/sakai-source"

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# --- 1. Root Check ---
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. User 'sudo ./install_sakai.sh'"
fi

log "Starting Sakai 23 Installation..."

# --- 2. System Update & Prerequisites ---
log "Updating system packages..."
apt-get update -y && apt-get upgrade -y
apt-get install -y git curl wget unzip tar
success "System updated."

# --- 3. Java 11 Installation ---
log "Installing Java 11 (OpenJDK)..."
apt-get install -y openjdk-11-jdk
# Verify Java version
JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
if [[ "$JAVA_VER" == "11"* ]]; then
    success "Java 11 installed: $JAVA_VER"
else
    error "Java 11 installation failed or incorrect version found: $JAVA_VER"
fi

# Set JAVA_HOME persistently
echo "JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk-amd64\"" >> /etc/environment
source /etc/environment

# --- 4. MySQL Setup ---
log "Installing MySQL Server..."

install_mysql() {
    # Attempt install
    if apt-get install -y mysql-server; then
        return 0
    else
        return 1
    fi
}

fix_mysql_issues() {
    warn "MySQL installation encountered issues. Attempting to fix..."
    
    # Check for FROZEN state
    if [ -f /etc/mysql/FROZEN ]; then
        warn "Detected /etc/mysql/FROZEN. Removing lock file..."
        rm -f /etc/mysql/FROZEN
    fi

    # Basic Fixes
    dpkg --configure -a || true
    apt-get install --fix-broken -y || true
    
    # Try to start
    if systemctl restart mysql; then
        success "MySQL service recovered via basic fixes."
        return 0
    fi

    # DRACONIAN FIX: Purge and Reinstall
    # If we are here, standard fixes failed. Since this is a "Magic" installer for a fresh setup,
    # we will attempt to PURGE the broken mysql install and start over.
    warn "Basic recovery failed. Initiating deep recovery (Purge & Reinstall)..."
    warn "Backing up existing mysql data to /var/lib/mysql_backup_$(date +%s)"
    mv /var/lib/mysql "/var/lib/mysql_backup_$(date +%s)" || true
    
    apt-get remove --purge -y mysql-server mysql-client mysql-common
    apt-get autoremove -y
    apt-get autoclean
    
    # Reinstall
    log "Re-installing MySQL Server..."
    apt-get install -y mysql-server
    
    if systemctl is-active --quiet mysql; then
        success "MySQL service recovered via purge & reinstall."
        return 0
    else
        error "Deep recovery failed. Dumping logs:\n$(journalctl -xeu mysql.service --no-pager | tail -n 20)"
    fi
}

# Try install, if fail, try to fix
set +e # Temporarily disable exit-on-error for this block
install_mysql
MYSQL_EXIT_CODE=$?
set -e # Re-enable exit-on-error

if [ $MYSQL_EXIT_CODE -ne 0 ]; then
    fix_mysql_issues
fi

# Double check service status before proceeding
if ! systemctl is-active --quiet mysql; then
    warn "MySQL service is not running. Attempting start..."
    systemctl start mysql || fix_mysql_issues
fi

log "Configuring Database..."

# Create Database and User
# Note: Using 'IF NOT EXISTS' to make it idempotent-ish
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${SAKAI_DB_NAME} DEFAULT CHARACTER SET utf8;"
mysql -u root -e "CREATE USER IF NOT EXISTS '${SAKAI_DB_USER}'@'localhost' IDENTIFIED BY '${SAKAI_DB_PASS}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${SAKAI_DB_NAME}.* TO '${SAKAI_DB_USER}'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

success "Database '${SAKAI_DB_NAME}' created and user '${SAKAI_DB_USER}' configured."

# --- 5. Maven Installation ---
log "Installing Maven $MAVEN_VERSION..."
if [ -d "$MAVEN_HOME" ]; then
    warn "Maven directory already exists at $MAVEN_HOME. Skipping download."
else
    cd /tmp
    wget "https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz"
    tar -xf "apache-maven-$MAVEN_VERSION-bin.tar.gz"
    mv "apache-maven-$MAVEN_VERSION" "$MAVEN_HOME"
    rm "apache-maven-$MAVEN_VERSION-bin.tar.gz"
fi

# Set MAVEN Environment Variables
echo "MAVEN_HOME=\"$MAVEN_HOME\"" > /etc/profile.d/maven.sh
echo "export MAVEN_OPTS='-Xms512m -Xmx1024m'" >> /etc/profile.d/maven.sh
echo "export PATH=\$PATH:$MAVEN_HOME/bin" >> /etc/profile.d/maven.sh
source /etc/profile.d/maven.sh

# Verify Maven
if mvn -v | grep -q "Apache Maven"; then
    success "Maven installed successfully."
else
    error "Maven installation failed."
fi

# --- 6. Tomcat 9 Installation ---
log "Installing Tomcat $TOMCAT_VERSION..."
if [ -d "$TOMCAT_HOME" ]; then
    warn "Tomcat directory already exists at $TOMCAT_HOME. Skipping download."
else
    cd /tmp
    wget "https://archive.apache.org/dist/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
    tar -xf "apache-tomcat-$TOMCAT_VERSION.tar.gz"
    mv "apache-tomcat-$TOMCAT_VERSION" "$TOMCAT_HOME"
    rm "apache-tomcat-$TOMCAT_VERSION.tar.gz"
fi

# Tomcat Configuration
log "Configuring Tomcat..."

# 6.1 setenv.sh setup
cat > "$TOMCAT_HOME/bin/setenv.sh" << 'EOF'
export JAVA_OPTS="-Xms2g -Xmx2g -Djava.awt.headless=true -Dhttp.agent=Sakai -Dorg.apache.jasper.compiler.Parser.STRICT_QUOTE_ESCAPING=false -Duser.timezone=US/Eastern -Dsakai.cookieName=SAKAI2SESSIONID -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=8089 -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED --add-exports=java.base/sun.nio.ch=ALL-UNNAMED --add-exports=java.management/com.sun.jmx.mbeanserver=ALL-UNNAMED --add-exports=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED --add-exports=java.base/sun.reflect.generics.reflectiveObjects=ALL-UNNAMED --add-opens=jdk.management/com.sun.management.internal=ALL-UNNAMED --illegal-access=permit"
EOF
chmod +x "$TOMCAT_HOME/bin/setenv.sh"

# 6.2 server.xml (UTF-8 Setup)
# Using sed to inject URIEncoding attribute if not present
if ! grep -q 'URIEncoding="UTF-8"' "$TOMCAT_HOME/conf/server.xml"; then
    sed -i 's/Connector port="8080"/Connector port="8080" URIEncoding="UTF-8"/g' "$TOMCAT_HOME/conf/server.xml"
fi

# 6.3 context.xml (JarScanner Optimization)
if ! grep -q "JarScanFilter" "$TOMCAT_HOME/conf/context.xml"; then
    sed -i '/<Context>/a \    <JarScanner>\n        <JarScanFilter defaultPluggabilityScan="false" />\n    </JarScanner>' "$TOMCAT_HOME/conf/context.xml"
fi

# 6.4 Clean default webapps
rm -rf "$TOMCAT_HOME/webapps/*"

# 6.5 MySQL Connector
log "Downloading MySQL Connector..."
cd "$TOMCAT_HOME/lib"
wget "https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar"

success "Tomcat configured."

# --- 7. Sakai Configuration (sakai.properties) ---
log "Setting up Sakai properties..."
mkdir -p "$TOMCAT_HOME/sakai"
cat > "$TOMCAT_HOME/sakai/sakai.properties" << EOF
# Basic Settings
serverName=localhost
ui.service = Sakai
version.service = 23
test=true

# Database Settings
auto.ddl=true
username@javax.sql.BaseDataSource=${SAKAI_DB_USER}
password@javax.sql.BaseDataSource=${SAKAI_DB_PASS}
vendor@org.sakaiproject.db.api.SqlService=mysql
driverClassName@javax.sql.BaseDataSource=com.mysql.cj.jdbc.Driver
hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
url@javax.sql.BaseDataSource=jdbc:mysql://127.0.0.1:3306/${SAKAI_DB_NAME}?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true
validationQuery@javax.sql.BaseDataSource=
defaultTransactionIsolationString@javax.sql.BaseDataSource=TRANSACTION_READ_COMMITTED
EOF

success "Sakai properties created."

# --- 8. Sakai Build & Deploy ---
log "Cloning Sakai source code (Branch: $SAKAI_VERSION)..."
if [ -d "$SAKAI_SRC_DIR" ]; then
    warn "Sakai source directory exists. Pulling latest changes..."
    cd "$SAKAI_SRC_DIR"
    git pull
else
    git clone -b "$SAKAI_VERSION" https://github.com/sakaiproject/sakai.git "$SAKAI_SRC_DIR"
    cd "$SAKAI_SRC_DIR"
fi

log "Building Sakai (This will take a significant amount of time)..."
# Using -Dmaven.test.skip=true for speed and reliability in "magic" mode
mvn clean install sakai:deploy -Dmaven.tomcat.home="$TOMCAT_HOME" -Dsakai.home="$TOMCAT_HOME/sakai" -Dmaven.test.skip=true -Djava.awt.headless=true

success "Sakai built and deployed."

# --- 9. Systemd Service ---
log "Creating Systemd Service for Sakai..."
cat > /etc/systemd/system/sakai.service << EOF
[Unit]
Description=Sakai LMS
After=network.target

[Service]
Type=forking

Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
Environment=CATALINA_PID=$TOMCAT_HOME/temp/tomcat.pid
Environment=CATALINA_HOME=$TOMCAT_HOME
Environment=CATALINA_BASE=$TOMCAT_HOME

ExecStart=$TOMCAT_HOME/bin/startup.sh
ExecStop=$TOMCAT_HOME/bin/shutdown.sh

User=root
Group=root
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sakai
systemctl start sakai

success "Sakai service started automatically."

# --- 10. Final Output ---
echo ""
echo "=============================================================================="
echo -e "${GREEN}SAKAI INSTALLATION COMPLETE!${NC}"
echo "=============================================================================="
echo "Sakai is starting up. It may take a few minutes for the initial initialization."
echo "You can access Sakai at: http://localhost:8080/portal"
echo ""
echo "Database User: $SAKAI_DB_USER"
echo "Database Password: $SAKAI_DB_PASS"
echo "Tomcat Home: $TOMCAT_HOME"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} This script used a default insecure user/password for the DB."
echo "Running in production? Please secure your MySQL, change passwords, and update sakai.properties."
echo "=============================================================================="
