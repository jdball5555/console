#!/bin/zsh -l
# Checks Console, Axis Team, Scorecards and Optimizer for code problems
# (flutter analyze) and Axis Optic's functions for syntax errors.
# Log: check_output.txt
cd "$(dirname "$0")"
export PATH="$PATH:$HOME/flutter/bin:$HOME/development/flutter/bin:$HOME/dev/flutter/bin:/opt/homebrew/bin:/usr/local/bin"
exec > >(tee check_output.txt) 2>&1
echo "== Console =="; flutter pub get >/dev/null; flutter analyze; echo "CONSOLE EXIT: $?"
echo "== Axis Optic functions =="; node --check functions/index.js; echo "FUNCTIONS EXIT: $?"
for app in team team-public scorecards optimizer; do
  echo "== $app =="; (cd ../$app && flutter pub get >/dev/null && flutter analyze lib); echo "${app:u} EXIT: $?"
done
echo "Done. You can close this window."
