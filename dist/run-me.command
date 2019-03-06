#!/bin/bash

# 1.  Get fully qualified path for current directory and `cd`
#     into it to establish known working directory
# 2.  Create directories?...
# 3.  Verify that the bundled `java` command works
# 4.  Export JAVA_HOME as the bundled jre folder
# 5.  Test port 8153 + 8154 are free
# 5a. Exit with error about used ports
# 5b.   - Instruct user to configure alternate ports?
# 6.  Start go-server
# 7.  Poll https port until open
# 7a.   - `cat < /dev/null > /dev/tcp/localhost/8153`
# 8.  When https port open, start go-agent.. look into how to verify agent succeeds
# 9.  Launch browser to http://localhost:8153 or print instructions

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "This script is not meant to be sourced! Please run it normally." >&2
  return 1
fi

function die {
  echo $@ >&2
  exit 1
}

# Tests a port on localhost; returns success on successful connection
function try_connect {
  local port="$1"

  if (bash -c "cat < /dev/null > '/dev/tcp/localhost/$port'" 2> /dev/null); then
    return 0 # successfully connected to this port; process listening
  fi

  return 1 # no process listening, connection refused
}

function start_server {
  local config_dir="$SERVER_DIR/config"
  local log_dir="$SERVER_DIR/logs"
  local tmp_dir="$SERVER_DIR/tmp"
  local stdout_log="$log_dir/stdout.log"
  local start_flags=("-server" "-Dcruise.config.dir=$config_dir" "-Dcruise.config.file=$config_dir/cruise-config.xml" "-Xmx1024m" "-Dgocd.redirect.stdout.to.file=$stdout_log" "-Djava.io.tmpdir=$tmp_dir")

  mkdir -p "$config_dir" "$log_dir" "$tmp_dir"

  cd "$SERVER_DIR"
  nohup "$JAVACMD" -jar "$PKG_DIR/go-server/go.jar" "${start_flags[@]}" >"$stdout_log" 2>&1 &
  SERVER_PID=$!
  echo $SERVER_PID > "$SERVER_PID_FILE"
  cd "$WORK_DIR"
}

function start_agent {
  local log_dir="$AGENT_DIR/logs"
  local tmp_dir="$AGENT_DIR/tmp"
  local stdout_log="$log_dir/stdout.log"
  local start_flags=("-Dgocd.agent.log.dir=$log_dir" "-Xmx256m" "-Dgocd.redirect.stdout.to.file=$stdout_log" "-Djava.io.tmpdir=$tmp_dir")

  mkdir -p "${log_dir}" "${tmp_dir}"
  cd "$AGENT_DIR"
  nohup "$JAVACMD" "${start_flags[@]}" -jar "$PKG_DIR/go-agent/agent-bootstrapper.jar" "-serverUrl" "https://localhost:8154/go"  > "$stdout_log" 2>&1 &
  AGENT_PID=$!
  echo $AGENT_PID > "$AGENT_PID_FILE"
  cd "$WORK_DIR"
}

function stop {
  local pid="$1"
  local pidfile="$2"
  local appname=$(basename "$pidfile")

  if (test -n "$pid" && ps -p "$pid" > /dev/null 2>&1); then
    if !(kill "$pid"); then
      echo "Got error when trying to stop the GoCD trial ${appname%.pid}, PID: $pid"
    fi
  fi

  if [ -f "$pidfile" ]; then
    rm -f "$pidfile"
  fi
}

function stop_server {
  stop "$SERVER_PID" "$SERVER_PID_FILE"
}

function stop_agent {
  stop "$AGENT_PID" "$AGENT_PID_FILE"
}

function command_exists {
  which $1 > /dev/null 2>&1
}


function wait_until_port_attached {
  local port="${1:-8154}"
  echo -n "Waiting for port $port"
  while !(try_connect $port); do
    echo -n "."
    sleep 1
  done
  echo ""
  echo "Listening on port $port"
}

function open_browser {
  local port="8153"

  if !(try_connect $port); then
    die "Expected port $port to be listening"
  fi

  local url="http://localhost:$port"

  case "$(uname -s)" in
    Darwin)
      open "$url"
      ;;
    Linux*)
      if (command_exists xdg-open); then
        xdg-open "$url"
      elif (command_exists kde-open); then
        kde-open "$url"
      elif (command_exists gnome-open); then
        gnome-open "$url"
      elif (command_exists python); then
        python -m webbrowser "$url"
      else
        echo "Open your browser to ${url}"
      fi
      ;;
    *)
      echo "Open your browser to ${url}"
      ;;
  esac
}

function cleanup {
  echo ""
  echo "Stopping GoCD trial server and agent..."
  stop_server
  stop_agent
  echo "Done."
}

function wait_for_interrupt {
  echo ""
  echo ""
  echo "GoCD Trial is ready at http://localhost:8153"
  echo "Press Ctrl-C to exit the trial."

  while true; do
    sleep 86400
    echo "Are you still trialing GoCD? Don't forget to press Ctrl-C to exit the trial"
  done
}

trap 'exit 1' HUP INT TERM
trap cleanup EXIT

set -e # this setting needs to come after the `return 1` above or else it exits the shell!

WORK_DIR=$(cd `dirname $0` && pwd)

cd "$WORK_DIR" # from this point on, we can safely use relative paths.

export PKG_DIR="$WORK_DIR/packages"
export JAVA_HOME="$PKG_DIR/jre"

JAVACMD="$JAVA_HOME/bin/java"

if !("$JAVACMD" -version 2> /dev/null); then
  die "The $JAVACMD command failed to run! This JRE might not be compatible with your system."
fi

SERVER_DIR="$WORK_DIR/data/server"
AGENT_DIR="$WORK_DIR/data/agent"
SERVER_PID_FILE="$SERVER_DIR/server.pid"
AGENT_PID_FILE="$AGENT_DIR/agent.pid"
SERVER_PID=""
AGENT_PID=""

mkdir -p "$SERVER_DIR" "$AGENT_DIR"

# Test that ports 8153 & 8154 are free
if (try_connect 8153 || try_connect 8154); then
  die "Both 8153 and 8154 must be free to run this trial."
fi

start_server

wait_until_port_attached 8154

start_agent

open_browser

wait_for_interrupt