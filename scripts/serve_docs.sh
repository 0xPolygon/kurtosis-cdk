#!/usr/bin/env bash
set -euo pipefail

virtualenv venv
# shellcheck source=/dev/null
source venv/bin/activate
pip3 install -r requirements.txt
cd ..
mkdocs serve --strict