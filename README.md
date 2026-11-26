# Console — Admin Hub for the Axis Optic Apps

An Android app, and the Firebase backend behind it, for running my Axis Optic apps from my phone: feedback from every app in one inbox, push alerts when something happens, and user admin for each app.

## Overview

Console is my private developer tool. Every Axis app (Axis Team, Scorecards, Optimizer) sends its feedback and events to one Firebase project, **Axis Optic**, and Console is the app that reads it. The apps' own databases hold no feedback at all.

## Features

- **Apps.** One page per app with its icon, website and user count, and tabs for:
  - **Feedback:** that app's tickets. Reply, close or reopen.
  - **The app's own pages:** Axis Team → Stores.
  - **Users:** for apps with a `console.js` (Axis Team, Scorecards, Optimizer). Search and open a user to change their name, email, sign-in block, notification settings and premium beta, sign them out everywhere, or get a password reset link. Optimizer shares its project with Asset Track and Axis Journal, so it lists only accounts that have opened Optimizer, and name, email and sign-in changes apply to all three. Axis Team lists only real sign-in accounts (not team records without a login).
  - **Traffic:** visitors, page views, top pages (Google Analytics) and Cloud Functions calls and failures, once a Google account is connected.
  - **Alerts:** switch each push notification on or off per app (new feedback, replies, new user, new store, ...), with recent activity below.
- **All tickets.** The inbox button on Home lists feedback from every app.
- **Push notifications** with the icon of the app they're about.
- **Look:** black and white only (`lib/theme.dart`). Red is kept for destructive actions and errors.

## How it fits together

| What | Where |
| --- | --- |
| Tickets from every app | Axis Optic `tickets/{id}`. Apps send, list and answer them through the `feedback` function. |
| Developer logins | Axis Optic `developers/{uid}`, added by hand |
| Phones to notify | Axis Optic `console/devices` |
| Alert switches | Axis Optic `console/alerts` → `{ <appId>: { <alertKey>: false } }` (anything missing is on) |
| Activity feed | Axis Optic `console/activity` (last 150) |
| Other apps' users | Console → `consoleService` (Axis Optic) → that app's `consoleAdmin` |
| Other apps' alerts | the app's functions → `reportAppEvent` (Axis Optic) → your phone |
| Axis Team's Stores tab | read from Axis Team's project with a second sign-in: Team's `consoleAdmin` hands Console a short-lived token marked `developer`, which Team's database rules accept (no Team password involved) |

Calls between projects use Google-signed identity tokens from each project's Cloud Functions service account, so there are no shared secrets.

## Built with

- [Flutter](https://flutter.dev) (Dart) for Android
- Firebase: Authentication, Cloud Firestore, Cloud Messaging and Cloud Functions (Node.js)
- Google APIs (read-only): Firebase Management, Analytics Data and Cloud Monitoring

## Project structure

```
lib/
  main.dart             sign-in, push setup, home
  app_pages.dart        Apps page and each app's tabs
  ticket_pages.dart     tickets and conversations
  services.dart         the apps Console manages
  service_api.dart      alerts, activity and user admin calls
  team_firebase.dart    second connection to Axis Team (Stores tab)
  stores*.dart          Axis Team's Stores tab
  google_data.dart      Traffic tab (Google APIs)
functions/index.js      Axis Optic's Cloud Functions
firestore.rules         developers only
tool/add_app_icon.py    app icons for Console
tools/move_feedback.js  one-time move of the apps' old feedback into Axis Optic
```

## Adding an app

1. **Console:** add a `ConsoleService` to `kServices` in `lib/services.dart`.
2. **Axis Optic:** add the app's Firebase project to `APPS` in `functions/index.js` (id, name, service accounts).
3. **Feedback:** the app posts to `https://us-central1-axis-optic-ce4f2.cloudfunctions.net/feedback` with the user's sign-in token.
4. **Users tab (optional):** copy Scorecards' `functions/console.js` into the app's functions, change its APP section, set its `adminUrl` in `APPS`, and set `remoteUsers: true` in Console.
5. **Icon:** `python3 tool/add_app_icon.py <id> <the app's square icon>`.
6. **Deploy:** the app's functions, then Axis Optic's.

## Running locally

1. In the Firebase console for Axis Optic: Authentication → Sign-in method → turn on **Google**.
2. Run `setup_console.command` once. It registers Console's Android app in Axis Optic (with this Mac's signing key, which Google sign-in needs), downloads `google-services.json` and writes `lib/firebase_options.dart`.
3. Run it on your phone with `flutter run --release` and sign in with Google. The first time, it says the account isn't a developer and shows its id: add a document `developers/<that id>` in Axis Optic's Firestore. Then turn off new sign-ups (Authentication → Settings → User actions).

You sign in with your Google account, and the Traffic tab uses the same account.

## Google account (Traffic tab)

Console reads Google's APIs directly with the Google account you signed in with, read-only (`lib/google_data.dart`). One-time setup, all in Axis Optic:

1. Google sign-in on (see Running locally).
2. Turn on the **Google Analytics Data API**, **Cloud Monitoring API** and **Firebase Management API** for the project in Google Cloud.
3. Each app's traffic needs Google Analytics on in its Firebase project (Project settings → Integrations).

The first time you connect, Google may warn that the app isn't verified (it's your own OAuth app): Advanced → continue. If it says the app is in testing, add your Google account as a test user (Google Auth Platform → Audience).

## Security

Axis Optic has no public users. Only logins with a `developers/{uid}` document can read or change its database, and the apps never touch it directly: their users go through the `feedback` function, which checks their sign-in and only shows them their own tickets. User admin for the other apps is checked on the server twice: `consoleService` only runs for developer logins, and each app's `consoleAdmin` only accepts calls from Axis Optic's service account. The same path gives Console its Axis Team sign-in, so there is no Team password on the phone.

## Deployment

```bash
firebase deploy --only functions,firestore
```

## How it was built

This project was built with AI-assisted development. I designed the app and directed the work, and I used **Claude** (Anthropic) in **Claude Code** to write and iterate on the code. Each release is tagged, and the [changelog](CHANGELOG.md) lists what changed in each one.

## Status

**Current version: 1.0.0.** My own developer tool, used on my phone and not published to an app store. See the [changelog](CHANGELOG.md) for version history.

## License

The source code is available under the [MIT License](LICENSE). The Axis Optic name and logos are not covered by the license.
