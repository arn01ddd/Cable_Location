#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
runtime="$1"
resources="$2"
check='from importlib.metadata import version; assert version("pymobiledevice3") == "11.40.2"'
if [[ "$runtime" == "$resources/python" ]]; then
    # Self-contained build. The user already approved opening the app, so clear the download
    # quarantine flag from its embedded Python too; otherwise macOS may block that helper.
    xattr -dr com.apple.quarantine "${resources:h:h}" 2>/dev/null || true
    "$runtime/bin/python" -I -c "$check" 2>/dev/null ||
        { print "The app's built-in iPhone support is damaged. Download Cable Location again."; exit 1; }
    print "iPhone support is ready."
    exit 0
fi
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
if ! "$runtime/bin/python" -c "$check" 2>/dev/null; then
    print "Installing iPhone support. First setup needs internet access…"
    "$runtime/bin/python" -m pip install -r "$resources/backend/requirements.txt"
fi
print "iPhone support is ready."
