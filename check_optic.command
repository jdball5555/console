#!/bin/zsh -l
# Checks the Optic app and the Axis Team app for code problems. Log: check_output.txt
cd "$(dirname "$0")"
export PATH="$PATH:$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin"
exec > >(tee check_output.txt) 2>&1
echo "== Optic =="; flutter analyze; echo "OPTIC EXIT: $?"
echo "== Axis Team =="; (cd ../axis-team && flutter analyze lib); echo "TEAM EXIT: $?"
echo "Done. You can close this window."
