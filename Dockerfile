# Stage 1: Build Sakai
FROM maven:3.9-eclipse-temurin-11 AS builder

# Configuration
ENV SAKAI_VERSION=23.x
ENV TOMCAT_HOME=/opt/tomcat

# Install git
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Create a mock tomcat structure for deployment
RUN mkdir -p ${TOMCAT_HOME}/lib ${TOMCAT_HOME}/webapps ${TOMCAT_HOME}/sakai

# Clone Sakai source
WORKDIR /src
RUN git clone -b ${SAKAI_VERSION} --depth 1 https://github.com/sakaiproject/sakai.git .

# Build and Deploy to the mock tomcat directory
# We skip tests to speed up the build
RUN mvn clean install sakai:deploy \
    -Dmaven.tomcat.home=${TOMCAT_HOME} \
    -Dsakai.home=${TOMCAT_HOME}/sakai \
    -Dmaven.test.skip=true \
    -Djava.awt.headless=true

# Stage 2: Runtime Environment
FROM tomcat:9.0-jdk11-openjdk-slim

ENV TOMCAT_HOME=/usr/local/tomcat
ENV SAKAI_HOME=${TOMCAT_HOME}/sakai

# Install MySQL Connector and gettext (for envsubst)
RUN apt-get update && apt-get install -y wget gettext-base && \
    wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar -P ${TOMCAT_HOME}/lib/ && \
    apt-get purge -y --auto-remove wget && rm -rf /var/lib/apt/lists/*

# Copy built artifacts from builder
COPY --from=builder /opt/tomcat/ ${TOMCAT_HOME}/

# Configure Tomcat (UTF-8 and optimization)
RUN sed -i 's/Connector port="8080"/Connector port="8080" URIEncoding="UTF-8"/g' ${TOMCAT_HOME}/conf/server.xml && \
    sed -i '/<Context>/a \    <JarScanner>\n        <JarScanFilter defaultPluggabilityScan="false" />\n    </JarScanner>' ${TOMCAT_HOME}/conf/context.xml

# Setup setenv.sh
RUN echo 'export JAVA_OPTS="-Xms2g -Xmx2g -Djava.awt.headless=true -Dhttp.agent=Sakai -Dorg.apache.jasper.compiler.Parser.STRICT_QUOTE_ESCAPING=false -Duser.timezone=US/Eastern -Dsakai.cookieName=SAKAI2SESSIONID -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=8089 -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED --add-exports=java.base/sun.nio.ch=ALL-UNNAMED --add-exports=java.management/com.sun.jmx.mbeanserver=ALL-UNNAMED --add-exports=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED --add-exports=java.base/sun.reflect.generics.reflectiveObjects=ALL-UNNAMED --add-opens=jdk.management/com.sun.management.internal=ALL-UNNAMED --illegal-access=permit"' > ${TOMCAT_HOME}/bin/setenv.sh && \
    chmod +x ${TOMCAT_HOME}/bin/setenv.sh

# Setup Sakai Properties Template and Entrypoint
COPY sakai.properties.template ${SAKAI_HOME}/sakai.properties.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose Sakai port
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
