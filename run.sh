#!/bin/sh
set -eu
cd "$(dirname "$0")"
export HF_HOME="${HF_HOME:-$PWD/.cache/huggingface}"
if [ ! -x .venv/bin/jac ]; then
  python_bin="${PYTHON:-python3}"
  "$python_bin" -c 'import sys; assert sys.version_info >= (3,12), "Python 3.12+ is required. Set PYTHON=/path/to/python3.12"'
  "$python_bin" -m venv .venv
  .venv/bin/python -m pip install -r requirements.lock
fi
exec .venv/bin/jac run main.jac
