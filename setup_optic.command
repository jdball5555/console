#!/bin/zsh -l
# One-time setup for the Optic app: creates the Android project files and
# registers Optic with Firebase (project-attendance-app). Log: setup_output.txt
cd "$(dirname "$0")"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="$PATH:$HOME/development/flutter/bin:$HOME/flutter/bin:$HOME/dev/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin"
exec > >(tee setup_output.txt) 2>&1
if command -v firebase >/dev/null 2>&1; then fb() { firebase "$@"; }; else fb() { npx --yes firebase-tools@latest "$@"; }; fi

PKG=com.axisoptic.optic
PROJECT=project-attendance-app

if [ ! -d android ]; then
  echo "Creating the Android project…"
  flutter create --org com.axisoptic --project-name optic --platforms android . || { echo "SETUP EXIT: 1"; exit 1; }
  rm -rf test
fi

find_app() {
  fb apps:list ANDROID --project $PROJECT --json 2>/dev/null | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try { const r=(JSON.parse(s).result)||[]; const a=r.find(x=>x.packageName===process.argv[1]); console.log(a?a.appId:""); }
      catch(e){ console.log(""); }
    });' $PKG
}

if [ ! -f android/app/google-services.json ]; then
  echo "Registering Optic with Firebase…"
  APPID=$(find_app)
  if [ -z "$APPID" ]; then
    fb apps:create ANDROID "Optic" --package-name $PKG --project $PROJECT
    APPID=$(find_app)
  fi
  echo "Firebase app: $APPID"
  [ -n "$APPID" ] && fb apps:sdkconfig ANDROID "$APPID" --project $PROJECT -o android/app/google-services.json
fi

flutter pub get
echo "SETUP EXIT: 0"
echo "Done. You can close this window."
