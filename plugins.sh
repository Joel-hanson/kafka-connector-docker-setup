#!/bin/usr/env bash

set -eo pipefail

KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
KAFKA_CONNECT_PLUGINS_DIR=${KAFKA_CONNECT_PLUGINS_DIR:-/opt/kafka/plugins}

# Copy the necessary connector JARs
cp "$KAFKA_HOME"/libs/connect-file-*.jar "$KAFKA_CONNECT_PLUGINS_DIR"
cp "$KAFKA_HOME"/libs/kafka-clients-*.jar "$KAFKA_CONNECT_PLUGINS_DIR"
cp "$KAFKA_HOME"/libs/connect-api-*.jar "$KAFKA_CONNECT_PLUGINS_DIR"
cp "$KAFKA_HOME"/libs/connect-transforms-*.jar "$KAFKA_CONNECT_PLUGINS_DIR"

echo "Kafka File Source and Sink connectors have been set up in $KAFKA_CONNECT_PLUGINS_DIR"

# List the installed connector JARs
echo "Installed connector JARs:"
ls -1 "$KAFKA_CONNECT_PLUGINS_DIR"

echo "Done!"
