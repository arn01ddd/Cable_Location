#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
runtime="$1"
resources="$2"
if [[ ! -x "$runtime/bin/python" ]]; then
    python=""
    for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        if [[ -x "$candidate" ]] && "$candidate" -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
            python="$candidate"
            break
        fi
    done
    [[ -n "$python" ]] || { print "Python 3.10 or newer is required. Install Python from python.org and reopen the app."; exit 1; }
    print "Creating the app's private Python environment…"
    mkdir -p -- "${runtime:h}"
    "$python" -m venv "$runtime"
fi
if ! "$runtime/bin/python" -c 'from importlib.metadata import version; assert version("pymobiledevice3") == "11.40.2"' 2>/dev/null; then
    print "Installing iPhone support. First setup needs internet access…"
    "$runtime/bin/python" -m pip install -r "$resources/backend/requirements.txt"
fi
print "iPhone support is ready."
