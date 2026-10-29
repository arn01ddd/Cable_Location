#!/bin/zsh
set -eu
cd -- "${0:A:h}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_CACHE_DIR=1

fail() {
  print -r -- "$1"
  read -r "?Press Return to close. " || true
  exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail "This launcher requires macOS."
if [[ ! -x .venv/bin/python ]]; then
  command -v python3 >/dev/null || fail "Install Python 3.10 or newer from python.org, then reopen this launcher."
  python3 -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null || fail "Python 3.10 or newer is required."
  print "Creating the private Python environment…"
  python3 -m venv .venv || fail "Could not create the environment. Check your Python installation."
fi
if ! .venv/bin/python -c 'from importlib.metadata import version; assert version("pymobiledevice3") == "11.40.2"' 2>/dev/null; then
  print "Installing iPhone support from PyPI. Internet is needed on first launch…"
  .venv/bin/python -m pip install -r requirements.txt || fail "Installation failed. Check your internet connection and reopen this launcher."
fi
.venv/bin/python cable_location.py "$@" || fail "Cable Location exited. See the message above."
