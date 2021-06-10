#!/bin/bash
TARGET_HOST=$1
CONSUL_HOST=$2
ACTION={$3:-"deploy-agent"}
TRENTO_BIN=${TRENTO_BIN:-"trento"}
CONSUL_BIN=${CONSUL_BIN:-"consul"}
TRENTO_PATH=${TRENTO_PATH:-"./srv/trento/"}
CONSUL_PATH=${CONSUL_PATH:-"./srv/consul/"}
EXAMPLES_PATH=${EXAMPLES_PATH:-"$TRENTO_PATH/examples"}
CONSUL_DATA_DIR=${CONSUL_DATA_DIR:-"consul-agent-data"}
TARGET_USER=${TARGET_USER:-"root"}

TRENTO_LOG=${TRENTO_LOG:"-/dev/null"}
CONSUL_LOG=${CONSUL_LOG"-/dev/null"}
SKIP_KNOWN_HOSTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"


if test "$TARGET_USER" != "root" ; then
    USE_SUDO="sudo"
fi

# Abort when any command in the script fails
set -e

# Abort if no input params
if [ $# -lt 2 ] ; then
    echo "Usage: ./deploy.sh <target-server-ip> <consul-ip> [deploy-agent*|deploy-web]"
    exit 1
fi

stop_process () {
    echo "Checking if process $2 is running in $1..."
    while ssh ${SKIP_KNOWN_HOSTS} "$TARGET_USER@${1}" pgrep -x "$2" > /dev/null
    do
        echo "Attempting to stop $2 process on $1..."
        ssh ${SKIP_KNOWN_HOSTS} "$TARGET_USER@${1}" "$USE_SUDO killall $2"
        sleep 2
    done
}

# Stop old processes
stop_process "$TARGET_HOST" "trento"
stop_process "$TARGET_HOST" "consul"

# Create directory structure if it doesn't exist
ssh  ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" mkdir -p "$TRENTO_PATH" || true
ssh  ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" mkdir -p "$CONSUL_PATH/consul.d" || true

# Upload new binaries & examples
rsync -av --rsh="ssh ${SKIP_KNOWN_HOSTS}" ./$TRENTO_BIN "$TARGET_USER@$TARGET_HOST:$TRENTO_PATH"
rsync -av --rsh="ssh ${SKIP_KNOWN_HOSTS}" ./$CONSUL_BIN "$TARGET_USER@$TARGET_HOST:$CONSUL_PATH"
rsync -av --rsh="ssh ${SKIP_KNOWN_HOSTS}" ./examples "$TARGET_USER@$TARGET_HOST:/$EXAMPLES_PATH"

# Give them execution permission
ssh  ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" chmod +x "$TRENTO_PATH/$TRENTO_BIN"
ssh  ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" chmod +x "$CONSUL_PATH/$CONSUL_BIN"

# Start 'em
if [ "$ACTION" = "deploy-agent" ] ; then
	ssh -t ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" -f "nohup $CONSUL_PATH/$CONSUL_BIN agent -bind=$TARGET_HOST -data-dir=$CONSUL_DATA_DIR -config-dir=$CONSUL_PATH/consul.d -retry-join=$CONSUL_HOST -ui > ${CONSUL_LOG} 2>&1"
        ssh -t ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" -f "nohup $USE_SUDO $TRENTO_PATH/$TRENTO_BIN agent start --consul-config-dir=$CONSUL_PATH/consul.d $EXAMPLES_PATH/azure-rules.yaml > ${TRENTO_LOG} 2>&1"
elif [ "$ACTION" = "deploy-web" ] ; then
	ssh -t ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" -f "nohup $CONSUL_PATH/$CONSUL_BIN agent -server -bootstrap-expect=1 -bind=$TARGET_HOST -data-dir=$CONSUL_DATA_DIR -ui > ${CONSUL_LOG} 2>&1"
	ssh -t ${SKIP_KNOWN_HOSTS} "$TARGET_USER@$TARGET_HOST" -f "nohup $TRENTO_PATH/$TRENTO_BIN web serve > ${TRENTO_LOG} 2>&1"
fi
