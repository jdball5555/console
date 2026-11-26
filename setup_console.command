#!/bin/zsh -l
# One-time setup for Console: registers its Android app in Axis Optic
# (axis-optic-ce4f2), downloads android/app/google-services.json, writes
# lib/firebase_options.dart from it, and registers this Mac's debug signing
# key (needed for Google sign-in on the Traffic tab). Log: setup_output.txt
cd "$(dirname "$0")"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="$PATH:$HOME/development/flutter/bin:$HOME/flutter/bin:$HOME/dev/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin"
exec > >(tee setup_output.txt) 2>&1
if command -v firebase >/dev/null 2>&1; then fb() { firebase "$@"; }; else fb() { npx --yes firebase-tools@latest "$@"; }; fi

PKG=com.axisoptic.console
PROJECT=axis-optic-ce4f2
GS=android/app/google-services.json

find_app() {
  fb apps:list ANDROID --project $PROJECT --json 2>/dev/null | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try { const r=(JSON.parse(s).result)||[]; const a=r.find(x=>x.packageName===process.argv[1]); console.log(a?a.appId:""); }
      catch(e){ console.log(""); }
    });' $PKG
}

CURRENT=$(node -e 'try{const j=require("./'$GS'");const c=(j.client||[]).find(c=>c.client_info.android_client_info.package_name==="'$PKG'");console.log(c?j.project_info.project_id:"")}catch(e){console.log("")}')
APPID=$(find_app)
if [ -z "$APPID" ]; then
  echo "Registering Console with Firebase ($PROJECT)…"
  fb apps:create ANDROID "Console" --package-name $PKG --project $PROJECT
  APPID=$(find_app)
fi
[ -z "$APPID" ] && { echo "Couldn't find or create the Android app."; echo "SETUP EXIT: 1"; exit 1; }
echo "Firebase app: $APPID"

if [ "$CURRENT" != "$PROJECT" ]; then
  echo "Downloading google-services.json…"
  fb apps:sdkconfig ANDROID "$APPID" --project $PROJECT -o /tmp/console-google-services.json || { echo "SETUP EXIT: 1"; exit 1; }
  mv -f /tmp/console-google-services.json $GS
fi

echo "Writing lib/firebase_options.dart…"
node - "$GS" "$PKG" <<'JS'
const fs = require("fs");
const [gsPath, pkg] = process.argv.slice(2);
const j = JSON.parse(fs.readFileSync(gsPath, "utf8"));
const c = j.client.find((c) => c.client_info.android_client_info.package_name === pkg);
const p = j.project_info;
fs.writeFileSync("lib/firebase_options.dart", `// Axis Optic (${p.project_id}), Console's own Firebase project.
// setup_console.command rewrites this from android/app/google-services.json
// after registering Console's Android app there. Run it once.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Console is set up for Android only.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '${c.api_key[0].current_key}',
    appId: '${c.client_info.mobilesdk_app_id}',
    messagingSenderId: '${p.project_number}',
    projectId: '${p.project_id}',
    storageBucket: '${p.storage_bucket}',
  );
}
`);
console.log(`Project number: ${p.project_number}`);
JS

# This Mac's debug key (Console is signed with it, release builds too).
if [ -f ~/.android/debug.keystore ]; then
  for KIND in SHA1 SHA256; do
    SHA=$(keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android 2>/dev/null | awk -v k="$KIND:" '$1==k {print $2}')
    [ -n "$SHA" ] && fb apps:android:sha:create "$APPID" "$SHA" --project $PROJECT 2>/dev/null && echo "Registered $KIND $SHA"
  done
fi

flutter pub get
echo "SETUP EXIT: 0"
echo "Done. You can close this window."
