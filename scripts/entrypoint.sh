#!/bin/bash
set -e

# --- Configuration Defaults ---
export SAKAI_DB_HOST=${SAKAI_DB_HOST:-db}
export SAKAI_DB_PORT=${SAKAI_DB_PORT:-3306}
export SAKAI_DB_NAME=${SAKAI_DB_NAME:-sakaidatabase}
export SAKAI_DB_USER=${SAKAI_DB_USER:-sakaiuser}
export SAKAI_DB_PASS=${SAKAI_DB_PASS:-sakaipassword}

echo "Generating sakai.properties from environment variables..."
envsubst < ${SAKAI_HOME}/sakai.properties.template > ${SAKAI_HOME}/sakai.properties

echo "Starting Sakai on Tomcat..."
exec catalina.sh run
