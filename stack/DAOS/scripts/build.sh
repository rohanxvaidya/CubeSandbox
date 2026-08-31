#!/bin/bash

WORK_PATH=/home/daos/
CODE_PATH=${WORK_PATH}/daos/
BUILD_PRE=${WORK_PATH}/pre

DAOS_DEPS_BUILD=yes
DAOS_KEEP_BUILD=yes # keep the build folder and result?
DAOS_TARGET_TYPE=debug  # release/debug
DEPS_JOBS=1

cd /home/daos/daos/
# select compiler to use
COMPILER=gcc
JOBS=$DEPS_JOBS
DAOS_BUILD_TYPE=$DAOS_TARGET_TYPE
DAOS_BUILD=$DAOS_DEPS_BUILD

# build prepareing.
[ "$DAOS_DEPS_BUILD" != "yes" ] || {                            \
        scons --build-deps=only --jobs $DEPS_JOBS PREFIX=/opt/daos  \
              TARGET_TYPE=$DAOS_TARGET_TYPE &&                      \
        ([ "$DAOS_KEEP_BUILD" != "no" ] || /bin/rm -rf build *.gz); \
    }

# Build DAOS
[ "$DAOS_BUILD" != "yes" ] || {                                        \
        scons --jobs $JOBS install PREFIX=/opt/daos COMPILER=$COMPILER     \
              BUILD_TYPE=$DAOS_BUILD_TYPE TARGET_TYPE=$DAOS_TARGET_TYPE && \
        ([ "$DAOS_KEEP_BUILD" != "no" ] || /bin/rm -rf build) &&           \
        go clean -cache &&                                                 \
        cp -r utils/config/examples /opt/daos;                             \
    }

# # build preparing.
# scons --jobs 1 PREFIX=/opt/daos BUILD_TYPE=debug TARGET_TYPE=debug --build-deps=only
# # build daos
# scons --jobs 1 install PREFIX=/opt/daos BUILD_TYPE=debug TARGET_TYPE=debug 
# scons --jobs 1 install PREFIX=/opt/daos BUILD_TYPE=debug TARGET_TYPE=debug --build-deps=yes
# scons --jobs 1 install PREFIX=/opt/daos BUILD_TYPE=release TARGET_TYPE=release --build-deps=yes --config=force


# Set environment variables
export PATH=/opt/daos/bin:$PATH
export FI_SOCKETS_MAX_CONN_RETRY=1

# Build java and hadoop bindings
cd /home/daos/daos/src/client/java

# DAOS_JAVA_BUILD=$DAOS_BUILD
DAOS_JAVA_BUILD=no

[ "$DAOS_JAVA_BUILD" != "yes" ] || {                                                      \
        mkdir /home/daos/.m2 &&                                                               \
        cp /home/daos/daos/utils/scripts/helpers/maven-settings.xml.in /home/daos/.m2/settings.xml &&      \
        export JAVA_HOME=$(daos-java/find_java_home.sh) && \
        mvn clean install -T 1C                                                               \
            -B -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn \
            -DskipITs -Dgpg.skip -Ddaos.install.path=/opt/daos;                               \
}
cd  ${WORK_PATH}

DAOS_KEEP_SRC=yes
# Remove local copy
[ "$DAOS_KEEP_SRC" != "no" ] || rm -rf /home/daos/daos /home/daos/pre
