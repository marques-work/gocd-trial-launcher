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

set -e # this setting needs to come after the `return 1` above or else it exits the shell!

WORK_DIR=$(cd `dirname $0` && pwd)

cd "$WORK_DIR" # from this point on, we can safely use relative paths.

export JAVA_HOME="$WORK_DIR/jre"

if !("$JAVA_HOME/bin/java" -version 2> /dev/null); then
  die "The $JAVA_HOME/bin/java command failed to run! This JRE might not be compatible with your system."
fi

# Test that ports 8153 & 8154 are free
if (try_connect 8153 || try_connect 8154); then
  die "Both 8153 and 8154 must be free to run this trial."
fi
