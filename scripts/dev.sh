#!/bin/bash
# ==============================================================================
# Sakai Development Workflow Script
# ==============================================================================
# This script helps you build, deploy, and manage Sakai from local source code.
#
# Usage: ./scripts/dev.sh <command> [options]
# ==============================================================================

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Configuration ---
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAKAI_SRC="${PROJECT_DIR}/sakai-source"
TOMCAT_HOME="/opt/tomcat"
MAVEN_HOME="/opt/maven"
SAKAI_HOME="${TOMCAT_HOME}/sakai"

# Versions (for install command)
TOMCAT_VERSION="9.0.85"
MAVEN_VERSION="3.9.6"

# Database (for install/clean-remove)
SAKAI_DB_USER="sakaiuser"
SAKAI_DB_PASS="sakaipassword"
SAKAI_DB_NAME="sakaidatabase"

# Ensure Maven is in PATH
export PATH="${MAVEN_HOME}/bin:${PATH}"
export MAVEN_OPTS="-Xms512m -Xmx1024m"

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Validate Environment ---
check_env() {
    [ -f "${SAKAI_SRC}/pom.xml" ] || error "Sakai source not found at ${SAKAI_SRC}. Run './scripts/dev.sh install' first."
    command -v mvn &>/dev/null || command -v "${MAVEN_HOME}/bin/mvn" &>/dev/null || error "Maven not found. Run './scripts/dev.sh install' first."
    command -v java &>/dev/null || error "Java not found. Run './scripts/dev.sh install' first."
}

# --- Commands ---

do_build_module() {
    local MODULE="$1"
    [ -z "$MODULE" ] && error "Usage: ./scripts/dev.sh build-module <module-name>\n\nExamples:\n  ./scripts/dev.sh build-module portal\n  ./scripts/dev.sh build-module login\n  ./scripts/dev.sh build-module site-manage\n\nAvailable top-level modules:\n$(ls -d ${SAKAI_SRC}/*/pom.xml 2>/dev/null | sed 's|.*/sakai-source/||;s|/pom.xml||' | sort | head -30)"

    local MODULE_DIR="${SAKAI_SRC}/${MODULE}"
    [ -d "$MODULE_DIR" ] || error "Module '${MODULE}' not found in ${SAKAI_SRC}/. Check the name."

    log "Building module: ${MODULE}"
    log "Stopping Sakai first to free memory..."
    do_stop 2>/dev/null || true

    cd "$MODULE_DIR"
    sudo --preserve-env=PATH,MAVEN_OPTS,JAVA_HOME mvn clean install sakai:deploy \
        ${MAVEN_ARGS} \
        -Dmaven.tomcat.home="${TOMCAT_HOME}" \
        -Dsakai.home="${SAKAI_HOME}" \
        -Dmaven.test.skip=true \
        -Djava.awt.headless=true

    success "Module '${MODULE}' built and deployed successfully!"
    log "Run './scripts/dev.sh start' to start Sakai and see your changes."
}

do_full_build() {
    warn "Full build requires ~6-8GB of disk space and 1-2GB of RAM."
    warn "This will take 30-60+ minutes depending on your system."
    log "Disk available: $(df -h / | tail -1 | awk '{print $4}')"
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }

    log "Stopping Sakai first..."
    do_stop 2>/dev/null || true

    cd "${SAKAI_SRC}"
    log "Starting full build..."
    sudo --preserve-env=PATH,MAVEN_OPTS,JAVA_HOME mvn clean install sakai:deploy \
        -Dmaven.tomcat.home="${TOMCAT_HOME}" \
        -Dsakai.home="${SAKAI_HOME}" \
        -Dmaven.test.skip=true \
        -Djava.awt.headless=true

    success "Full build and deploy complete!"
    log "Run './scripts/dev.sh start' to start Sakai."
}

do_start() {
    log "Starting Sakai..."

    # Ensure MySQL is running
    if ! systemctl is-active --quiet mysql; then
        warn "MySQL not running. Starting..."
        sudo systemctl start mysql
    fi

    sudo systemctl start sakai
    success "Sakai started. Monitoring logs..."
    log "Waiting for startup (5-10 min). Press Ctrl+C to stop monitoring."
    echo ""
    sudo tail -n 20 -f /opt/tomcat/logs/catalina.out 2>/dev/null || true
}

do_stop() {
    log "Stopping Sakai..."
    sudo systemctl stop sakai 2>/dev/null || true

    # Wait for Tomcat process to exit
    local TRIES=0
    while pgrep -f "org.apache.catalina.startup.Bootstrap" > /dev/null 2>&1; do
        echo -n "."
        sleep 2
        TRIES=$((TRIES + 1))
        [ $TRIES -gt 30 ] && { warn "Force killing..."; sudo pkill -9 -f "org.apache.catalina.startup.Bootstrap" 2>/dev/null || true; break; }
    done
    echo ""
    success "Sakai stopped."
}

do_restart() {
    do_stop
    sleep 2
    do_start
}

do_logs() {
    sudo tail -n 100 -f /opt/tomcat/logs/catalina.out 2>/dev/null || error "Cannot read Tomcat logs."
}

do_status() {
    echo ""
    echo "=== Sakai Service ==="
    systemctl is-active sakai 2>/dev/null && echo -e "${GREEN}● Sakai: RUNNING${NC}" || echo -e "${RED}● Sakai: STOPPED${NC}"

    echo ""
    echo "=== MySQL Service ==="
    systemctl is-active mysql 2>/dev/null && echo -e "${GREEN}● MySQL: RUNNING${NC}" || echo -e "${RED}● MySQL: STOPPED${NC}"

    echo ""
    echo "=== System Resources ==="
    echo "Disk: $(df -h / | tail -1 | awk '{print $4 " free of " $2}')"
    echo "RAM:  $(free -h | awk '/^Mem:/{print $7 " available of " $2}')"

    echo ""
    echo "=== Sakai Source ==="
    [ -f "${SAKAI_SRC}/pom.xml" ] && echo -e "${GREEN}● Source: ${SAKAI_SRC}${NC}" || echo -e "${RED}● Source: NOT FOUND${NC}"
    echo ""
}

do_list_modules() {
    echo ""
    log "Available Sakai modules:"
    echo ""
    ls -d ${SAKAI_SRC}/*/pom.xml 2>/dev/null | sed 's|.*/sakai-source/||;s|/pom.xml||' | sort | column
    echo ""
}

do_properties() {
    log "Opening sakai.properties..."
    echo "Location: ${SAKAI_HOME}/sakai.properties"
    echo ""
    sudo cat "${SAKAI_HOME}/sakai.properties"
}

# === INSTALL ===
do_install() {
    echo ""
    echo "=============================================================================="
    echo -e "${BLUE}  Sakai 23 — Full Development Environment Installer${NC}"
    echo "=============================================================================="
    echo "This will install: Java 11, Maven, Tomcat 9, MySQL 8, and Sakai 23.x source."
    echo "Estimated time: 45-90 minutes (mostly build time)."
    echo "Estimated disk: ~10GB."
    echo ""

    # Root check
    if [[ $EUID -ne 0 ]]; then
        warn "This command requires root privileges. Re-running with sudo..."
        exec sudo --preserve-env=PATH,MAVEN_OPTS,JAVA_HOME "$0" install
    fi

    # ── Step 1: System Update & Prerequisites ──
    log "[1/8] Updating system packages..."
    apt-get update -y && apt-get upgrade -y
    apt-get install -y git curl wget unzip tar
    success "System updated."

    # ── Step 2: Java 11 ──
    log "[2/8] Installing Java 11 (OpenJDK)..."
    apt-get install -y openjdk-11-jdk
    JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    if [[ "$JAVA_VER" == "11"* ]]; then
        success "Java 11 installed: $JAVA_VER"
    else
        error "Java 11 installation failed. Found: $JAVA_VER"
    fi
    grep -q "JAVA_HOME" /etc/environment || echo 'JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"' >> /etc/environment

    # ── Step 3: MySQL ──
    log "[3/8] Installing MySQL Server..."
    if systemctl is-active --quiet mysql 2>/dev/null; then
        success "MySQL already running. Skipping install."
    else
        apt-get install -y mysql-server
        systemctl start mysql
        systemctl enable mysql
    fi

    log "Configuring Sakai database..."
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${SAKAI_DB_NAME} DEFAULT CHARACTER SET utf8;"
    mysql -u root -e "CREATE USER IF NOT EXISTS '${SAKAI_DB_USER}'@'localhost' IDENTIFIED BY '${SAKAI_DB_PASS}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${SAKAI_DB_NAME}.* TO '${SAKAI_DB_USER}'@'localhost';"
    mysql -u root -e "FLUSH PRIVILEGES;"
    success "Database '${SAKAI_DB_NAME}' ready."

    # ── Step 4: Maven ──
    log "[4/8] Installing Maven ${MAVEN_VERSION}..."
    if [ -d "${MAVEN_HOME}" ]; then
        success "Maven already installed at ${MAVEN_HOME}. Skipping."
    else
        cd /tmp
        wget -q "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
        tar -xf "apache-maven-${MAVEN_VERSION}-bin.tar.gz"
        mv "apache-maven-${MAVEN_VERSION}" "${MAVEN_HOME}"
        rm -f "apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    fi
    # Set Maven env
    cat > /etc/profile.d/maven.sh << MVNEOF
export MAVEN_HOME="${MAVEN_HOME}"
export MAVEN_OPTS="-Xms512m -Xmx1024m"
export PATH=\$PATH:${MAVEN_HOME}/bin
MVNEOF
    source /etc/profile.d/maven.sh 2>/dev/null || true
    success "Maven installed."

    # ── Step 5: Tomcat 9 ──
    log "[5/8] Installing Tomcat ${TOMCAT_VERSION}..."
    if [ -d "${TOMCAT_HOME}" ]; then
        success "Tomcat already installed at ${TOMCAT_HOME}. Skipping."
    else
        cd /tmp
        wget -q "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
        tar -xf "apache-tomcat-${TOMCAT_VERSION}.tar.gz"
        mv "apache-tomcat-${TOMCAT_VERSION}" "${TOMCAT_HOME}"
        rm -f "apache-tomcat-${TOMCAT_VERSION}.tar.gz"
    fi

    # Tomcat configuration
    log "Configuring Tomcat..."
    # setenv.sh
    cat > "${TOMCAT_HOME}/bin/setenv.sh" << 'SETENVEOF'
export JAVA_OPTS="-Xms2g -Xmx2g -Djava.awt.headless=true -Dhttp.agent=Sakai -Dorg.apache.jasper.compiler.Parser.STRICT_QUOTE_ESCAPING=false -Duser.timezone=US/Eastern -Dsakai.cookieName=SAKAI2SESSIONID -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=8089 -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED --add-exports=java.base/sun.nio.ch=ALL-UNNAMED --add-exports=java.management/com.sun.jmx.mbeanserver=ALL-UNNAMED --add-exports=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED --add-exports=java.base/sun.reflect.generics.reflectiveObjects=ALL-UNNAMED --add-opens=jdk.management/com.sun.management.internal=ALL-UNNAMED --illegal-access=permit"
SETENVEOF
    chmod +x "${TOMCAT_HOME}/bin/setenv.sh"

    # UTF-8 in server.xml
    grep -q 'URIEncoding="UTF-8"' "${TOMCAT_HOME}/conf/server.xml" || \
        sed -i 's/Connector port="8080"/Connector port="8080" URIEncoding="UTF-8"/g' "${TOMCAT_HOME}/conf/server.xml"

    # JarScanner optimization
    grep -q "JarScanFilter" "${TOMCAT_HOME}/conf/context.xml" || \
        sed -i '/<Context>/a \    <JarScanner>\n        <JarScanFilter defaultPluggabilityScan="false" />\n    </JarScanner>' "${TOMCAT_HOME}/conf/context.xml"

    # MySQL Connector
    if [ ! -f "${TOMCAT_HOME}/lib/mysql-connector-java-8.0.28.jar" ]; then
        log "Downloading MySQL Connector..."
        wget -q "https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar" -P "${TOMCAT_HOME}/lib/"
    fi
    success "Tomcat configured."

    # ── Step 6: Sakai Properties ──
    log "[6/8] Setting up sakai.properties..."
    mkdir -p "${SAKAI_HOME}"
    cat > "${SAKAI_HOME}/sakai.properties" << PROPEOF
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
PROPEOF
    success "sakai.properties created."

    # ── Step 7: Clone and Build Sakai ──
    log "[7/8] Cloning Sakai 23.x source code..."
    cd "${PROJECT_DIR}"
    if [ -d "${SAKAI_SRC}" ] && [ -f "${SAKAI_SRC}/pom.xml" ]; then
        success "Sakai source already exists. Skipping clone."
    else
        git clone https://github.com/codewithgabriel/sakai-23.x-standalone.git sakai-source
    fi

    log "Building Sakai (this will take 30-60+ minutes)..."
    cd "${SAKAI_SRC}"
    ${MAVEN_HOME}/bin/mvn clean install sakai:deploy \
        -Dmaven.tomcat.home="${TOMCAT_HOME}" \
        -Dsakai.home="${SAKAI_HOME}" \
        -Dmaven.test.skip=true \
        -Djava.awt.headless=true
    success "Sakai built and deployed."

    # ── Step 8: Systemd Service ──
    log "[8/8] Creating systemd service..."
    cat > /etc/systemd/system/sakai.service << SVCEOF
[Unit]
Description=Sakai LMS
After=network.target mysql.service

[Service]
Type=forking
Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
Environment=CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid
Environment=CATALINA_HOME=${TOMCAT_HOME}
Environment=CATALINA_BASE=${TOMCAT_HOME}
ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh
User=root
Group=root
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable sakai
    systemctl start sakai
    success "Sakai service created and started."

    # ── Done ──
    echo ""
    echo "=============================================================================="
    echo -e "${GREEN}  SAKAI INSTALLATION COMPLETE!${NC}"
    echo "=============================================================================="
    echo "Sakai is starting up. First startup takes 5-10 minutes."
    echo ""
    echo "  Portal:     http://localhost:8080/portal"
    echo "  Admin user: admin / admin"
    echo ""
    echo "  Monitor startup: ./scripts/dev.sh logs"
    echo "  Check status:    ./scripts/dev.sh status"
    echo ""
    echo -e "${YELLOW}  IMPORTANT: Change the default passwords for production!${NC}"
    echo "=============================================================================="
}

# === CLEAN REMOVE ===
do_clean_remove() {
    echo ""
    echo -e "${RED}==============================================================================${NC}"
    echo -e "${RED}  Sakai — Complete Removal${NC}"
    echo -e "${RED}==============================================================================${NC}"
    echo ""
    echo "This will remove:"
    echo "  • Sakai systemd service"
    echo "  • Tomcat 9 (${TOMCAT_HOME})"
    echo "  • Maven (${MAVEN_HOME})"
    echo "  • Sakai source code (${SAKAI_SRC})"
    echo "  • Maven local cache (~/.m2/repository — root's copy)"
    echo ""
    echo -e "${YELLOW}Optional: MySQL and the sakaidatabase can also be removed.${NC}"
    echo ""
    read -p "Are you SURE you want to remove everything? (type 'yes' to confirm): " CONFIRM
    [ "$CONFIRM" = "yes" ] || { log "Cancelled."; exit 0; }

    if [[ $EUID -ne 0 ]]; then
        warn "This command requires root. Re-running with sudo..."
        exec sudo "$0" clean-remove
    fi

    # 1. Stop Sakai
    log "Stopping Sakai service..."
    systemctl stop sakai 2>/dev/null || true
    systemctl disable sakai 2>/dev/null || true
    rm -f /etc/systemd/system/sakai.service
    systemctl daemon-reload
    success "Sakai service removed."

    # 2. Kill any remaining Tomcat
    pkill -9 -f "org.apache.catalina.startup.Bootstrap" 2>/dev/null || true

    # 3. Remove Tomcat
    if [ -d "${TOMCAT_HOME}" ]; then
        log "Removing Tomcat..."
        rm -rf "${TOMCAT_HOME}"
        success "Tomcat removed."
    fi

    # 4. Remove Maven
    if [ -d "${MAVEN_HOME}" ]; then
        log "Removing Maven..."
        rm -rf "${MAVEN_HOME}"
        rm -f /etc/profile.d/maven.sh
        success "Maven removed."
    fi

    # 5. Remove Sakai source
    if [ -d "${SAKAI_SRC}" ]; then
        log "Removing Sakai source code..."
        rm -rf "${SAKAI_SRC}"
        success "Source removed."
    fi

    # 6. Clean root Maven cache
    if [ -d "/root/.m2/repository" ]; then
        log "Cleaning root Maven cache..."
        rm -rf /root/.m2/repository
        success "Maven cache cleaned."
    fi

    # 7. Optional: MySQL
    echo ""
    read -p "Also remove MySQL and the sakaidatabase? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Dropping sakaidatabase and user..."
        mysql -u root -e "DROP DATABASE IF EXISTS ${SAKAI_DB_NAME};" 2>/dev/null || true
        mysql -u root -e "DROP USER IF EXISTS '${SAKAI_DB_USER}'@'localhost';" 2>/dev/null || true
        
        read -p "Completely uninstall MySQL server? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            apt-get remove --purge -y mysql-server mysql-client mysql-common 2>/dev/null || true
            apt-get autoremove -y
            success "MySQL uninstalled."
        else
            success "MySQL kept, but Sakai database removed."
        fi
    fi

    echo ""
    echo "=============================================================================="
    echo -e "${GREEN}  Sakai has been completely removed from this system.${NC}"
    echo "=============================================================================="
    echo "  Your system is now Sakai-free."
    echo "  To reinstall: ./scripts/dev.sh install"
    echo "=============================================================================="
}

show_help() {
    echo ""
    echo "Sakai Development Workflow"
    echo "=========================="
    echo ""
    echo "Usage: ./scripts/dev.sh <command> [options]"
    echo ""
    echo "Setup Commands:"
    echo "  install               Install everything from scratch (Java, Maven, Tomcat, MySQL, Sakai)"
    echo "  clean-remove          Completely uninstall Sakai and all dependencies"
    echo ""
    echo "Build Commands:"
    echo "  build-module <name>   Build and deploy a single module (fast, ~2-5 min)"
    echo "  full-build            Build and deploy all of Sakai (slow, ~30-60 min)"
    echo ""
    echo "Server Commands:"
    echo "  start                 Start Sakai + monitor logs"
    echo "  stop                  Stop Sakai gracefully"
    echo "  restart               Stop and start Sakai"
    echo "  logs                  Tail Sakai logs"
    echo ""
    echo "Info Commands:"
    echo "  status                Show service status and system resources"
    echo "  list-modules          List all buildable Sakai modules"
    echo "  properties            Show current sakai.properties"
    echo ""
    echo "Examples:"
    echo "  ./scripts/dev.sh install                   # Fresh install on clean Ubuntu"
    echo "  ./scripts/dev.sh build-module portal       # Rebuild the portal module"
    echo "  ./scripts/dev.sh build-module login        # Rebuild the login page"
    echo "  ./scripts/dev.sh restart                   # Restart to pick up changes"
    echo "  ./scripts/dev.sh clean-remove              # Remove everything"
    echo ""
}

# --- Main ---
# Commands that DON'T need an existing Sakai environment
case "${1:-help}" in
    install)        do_install ;;
    clean-remove)   do_clean_remove ;;
    help|--help|-h) show_help ;;
esac

# Commands that DO need an existing Sakai environment
case "${1:-help}" in
    build-module)   check_env; do_build_module "$2" ;;
    full-build)     check_env; do_full_build ;;
    start)          do_start ;;
    stop)           do_stop ;;
    restart)        do_restart ;;
    logs)           do_logs ;;
    status)         do_status ;;
    list-modules)   check_env; do_list_modules ;;
    properties)     do_properties ;;
    install|clean-remove|help|--help|-h) ;; # already handled above
    *)              error "Unknown command: $1\n$(show_help)" ;;
esac
