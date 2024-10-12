#!/usr/bin/env bash

# set -eo pipefail

KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
KAFKA_CONNECT_PLUGINS_DIR=${KAFKA_CONNECT_PLUGINS_DIR:-/opt/kafka/plugins}
KAFKA_DATA=${KAFKA_DATA:-/var/lib/kafka/data}

# Default values
SENSITIVE_PROPERTIES=${SENSITIVE_PROPERTIES:-"CONNECT_SASL_JAAS_CONFIG,CONNECT_CONSUMER_SASL_JAAS_CONFIG,CONNECT_PRODUCER_SASL_JAAS_CONFIG,CONNECT_SSL_KEYSTORE_PASSWORD,CONNECT_PRODUCER_SSL_KEYSTORE_PASSWORD,CONNECT_SSL_TRUSTSTORE_PASSWORD,CONNECT_PRODUCER_SSL_TRUSTSTORE_PASSWORD,CONNECT_SSL_KEY_PASSWORD,CONNECT_PRODUCER_SSL_KEY_PASSWORD,CONNECT_CONSUMER_SSL_TRUSTSTORE_PASSWORD,CONNECT_CONSUMER_SSL_KEYSTORE_PASSWORD,CONNECT_CONSUMER_SSL_KEY_PASSWORD"}
BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-$(env | grep .*PORT_9092_TCP= | sed -e 's|.*tcp://||' | uniq | paste -sd ,)}
BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-0.0.0.0:9092}
HOST_NAME=${HOST_NAME:-$(ip addr | grep 'BROADCAST' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')}

# Set default environment variables
declare -A defaults=(
    ["REST_PORT"]="8083"
    ["REST_HOST_NAME"]="$HOST_NAME"
    ["ADVERTISED_PORT"]="8083"
    ["ADVERTISED_HOST_NAME"]="$HOST_NAME"
    ["GROUP_ID"]="1"
    ["OFFSET_FLUSH_INTERVAL_MS"]="60000"
    ["OFFSET_FLUSH_TIMEOUT_MS"]="5000"
    ["SHUTDOWN_TIMEOUT"]="10000"
    ["KEY_CONVERTER"]="org.apache.kafka.connect.json.JsonConverter"
    ["VALUE_CONVERTER"]="org.apache.kafka.connect.json.JsonConverter"
    ["ENABLE_APICURIO_CONVERTERS"]="false"
    ["ENABLE_JOLOKIA"]="false"
    ["ENABLE_OTEL"]="false"
)

# Set environment variables with defaults
for key in "${!defaults[@]}"; do
    if [[ -z "${!key}" ]]; then
        export "$key"="${defaults[$key]}"
    fi
done

# Export CONNECT_ variables
export CONNECT_REST_ADVERTISED_PORT=$ADVERTISED_PORT
export CONNECT_REST_ADVERTISED_HOST_NAME=$ADVERTISED_HOST_NAME
export CONNECT_REST_PORT=$REST_PORT
export CONNECT_REST_HOST_NAME=$REST_HOST_NAME
export CONNECT_BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS
export CONNECT_GROUP_ID=$GROUP_ID
export CONNECT_CONFIG_STORAGE_TOPIC=$CONFIG_STORAGE_TOPIC
export CONNECT_OFFSET_STORAGE_TOPIC=$OFFSET_STORAGE_TOPIC
[[ -n "$STATUS_STORAGE_TOPIC" ]] && export CONNECT_STATUS_STORAGE_TOPIC=$STATUS_STORAGE_TOPIC
export CONNECT_KEY_CONVERTER=$KEY_CONVERTER
export CONNECT_VALUE_CONVERTER=$VALUE_CONVERTER
export CONNECT_TASK_SHUTDOWN_GRACEFUL_TIMEOUT_MS=$SHUTDOWN_TIMEOUT
export CONNECT_OFFSET_FLUSH_INTERVAL_MS=$OFFSET_FLUSH_INTERVAL_MS
export CONNECT_OFFSET_FLUSH_TIMEOUT_MS=$OFFSET_FLUSH_TIMEOUT_MS
[[ -n "$HEAP_OPTS" ]] && export KAFKA_HEAP_OPTS=$HEAP_OPTS

# Unset variables
unset HOST_NAME REST_PORT REST_HOST_NAME ADVERTISED_PORT ADVERTISED_HOST_NAME GROUP_ID OFFSET_FLUSH_INTERVAL_MS OFFSET_FLUSH_TIMEOUT_MS SHUTDOWN_TIMEOUT KEY_CONVERTER VALUE_CONVERTER HEAP_OPTS

# Set up the classpath with plugins
CONNECT_PLUGIN_PATH=${CONNECT_PLUGIN_PATH:-$KAFKA_CONNECT_PLUGINS_DIR}
echo "Plugins are loaded from $CONNECT_PLUGIN_PATH"

# Create log directory
mkdir -p "${KAFKA_DATA}/${KAFKA_BROKER_ID}"

configure_log4j() {
    if [[ -n "$CONNECT_LOG4J_LOGGERS" ]]; then
        sed -i -r -e "s|^(log4j.rootLogger)=.*|\1=${CONNECT_LOG4J_LOGGERS}|g" "$KAFKA_HOME/config/log4j.properties"
        unset CONNECT_LOG4J_LOGGERS
    fi
    env | grep '^CONNECT_LOG4J' | while read -r VAR; do
        env_var=$(echo "$VAR" | sed -r "s/([^=]*)=.*/\1/g")
        prop_name=$(echo "$VAR" | sed -r "s/^CONNECT_([^=]*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .)
        prop_value=$(echo "$VAR" | sed -r "s/^CONNECT_[^=]*=(.*)/\1/g")
        if grep -Eq "(^|^#)$prop_name=" "$KAFKA_HOME/config/log4j.properties"; then
            sed -r -i "s@(^|^#)($prop_name)=(.*)@\2=${prop_value}@g" "$KAFKA_HOME/config/log4j.properties"
        else
            echo "$prop_name=${prop_value}" >>"$KAFKA_HOME/config/log4j.properties"
        fi
        if [[ "$SENSITIVE_PROPERTIES" = *"$env_var"* ]]; then
            echo "--- Setting logging property from $env_var: $prop_name=[hidden]"
        else
            echo "--- Setting logging property from $env_var: $prop_name=${prop_value}"
        fi
        unset "$env_var"
    done
    [[ -n "$LOG_LEVEL" ]] && sed -i -r -e "s|=INFO, stdout|=$LOG_LEVEL, stdout|g" -e "s|^(log4j.appender.stdout.threshold)=.*|\1=${LOG_LEVEL}|g" "$KAFKA_HOME/config/log4j.properties"
    export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:$KAFKA_HOME/config/log4j.properties"
}

process_connect_properties() {
    env | grep '^CONNECT_' | while read -r VAR; do
        env_var=$(echo "$VAR" | sed -r "s/([^=]*)=.*/\1/g")
        prop_name=$(echo "$VAR" | sed -r "s/^CONNECT_([^=]*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .)
        prop_value=$(echo "$VAR" | sed -r "s/^CONNECT_[^=]*=(.*)/\1/g")
        if grep -Eq "(^|^#)$prop_name=" "$KAFKA_HOME/config/connect-distributed.properties"; then
            sed -r -i "s@(^|^#)($prop_name)=(.*)@\2=${prop_value}@g" "$KAFKA_HOME/config/connect-distributed.properties"
        else
            echo "$prop_name=${prop_value}" >>"$KAFKA_HOME/config/connect-distributed.properties"
        fi
        if [[ "$SENSITIVE_PROPERTIES" = *"$env_var"* ]]; then
            echo "--- Setting property from $env_var: $prop_name=[hidden]"
        else
            echo "--- Setting property from $env_var: $prop_name=${prop_value}"
        fi
    done
}

start_kafka_connect() {
    echo "Using BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS"
    echo "Using the following environment variables:"
    echo "      GROUP_ID=$CONNECT_GROUP_ID"
    echo "      CONFIG_STORAGE_TOPIC=$CONNECT_CONFIG_STORAGE_TOPIC"
    echo "      OFFSET_STORAGE_TOPIC=$CONNECT_OFFSET_STORAGE_TOPIC"
    [[ -n "$CONNECT_STATUS_STORAGE_TOPIC" ]] && echo "      STATUS_STORAGE_TOPIC=$CONNECT_STATUS_STORAGE_TOPIC"
    echo "      BOOTSTRAP_SERVERS=$CONNECT_BOOTSTRAP_SERVERS"
    echo "      REST_HOST_NAME=$CONNECT_REST_HOST_NAME"
    echo "      REST_PORT=$CONNECT_REST_PORT"
    echo "      ADVERTISED_HOST_NAME=$CONNECT_REST_ADVERTISED_HOST_NAME"
    echo "      ADVERTISED_PORT=$CONNECT_REST_ADVERTISED_PORT"
    echo "      KEY_CONVERTER=$CONNECT_KEY_CONVERTER"
    echo "      VALUE_CONVERTER=$CONNECT_VALUE_CONVERTER"
    echo "      OFFSET_FLUSH_INTERVAL_MS=$CONNECT_OFFSET_FLUSH_INTERVAL_MS"
    echo "      OFFSET_FLUSH_TIMEOUT_MS=$CONNECT_OFFSET_FLUSH_TIMEOUT_MS"
    echo "      SHUTDOWN_TIMEOUT=$CONNECT_TASK_SHUTDOWN_GRACEFUL_TIMEOUT_MS"

    configure_log4j
    process_connect_properties

    exec "$KAFKA_HOME/bin/connect-distributed.sh" "$KAFKA_HOME/config/connect-distributed.properties"
}

case $1 in
start)
    if [[ -z "$CONNECT_BOOTSTRAP_SERVERS" || -z "$CONNECT_GROUP_ID" || -z "$CONNECT_CONFIG_STORAGE_TOPIC" || -z "$CONNECT_OFFSET_STORAGE_TOPIC" ]]; then
        echo "ERROR: BOOTSTRAP_SERVERS, GROUP_ID, CONFIG_STORAGE_TOPIC, and OFFSET_STORAGE_TOPIC must be set."
        exit 1
    fi
    [[ -z "$CONNECT_STATUS_STORAGE_TOPIC" ]] && echo "WARNING: It is recommended to specify the STATUS_STORAGE_TOPIC variable."
    start_kafka_connect
    ;;
*)
    exec "$@"
    ;;
esac
