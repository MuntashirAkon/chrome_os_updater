#!/bin/bash
# 2019 (c) Muntashir Al-Islam. All rights reserved.

# Echo to stderr
function echo_stderr {
  >&2 echo "$@"
}

# Print debug info in the stdout
function debug {
    if [ $CROS_DEBUG ]; then
        echo "DEBUG: $@"
    fi
}


# Print environment variables
function print_env {
    if [ $CROS_DEBUG ]; then
      ( set -o posix ; set )
    fi
    return 0
}
