# Changelog

All notable changes to this project are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org): **major** for redesigns, **minor** for new features, **patch** for fixes.

## [1.0.0] — 2026-11-25

### Added
- Its own Firebase project, Axis Optic (`axis-optic-ce4f2`): every app's feedback, the developer list, push devices, alert switches and the activity feed live there, and no app's own database holds any feedback
- The `feedback` function: the apps send, list, answer, close and reopen their users' tickets through it, and each user only ever sees their own
- `reportAppEvent`, `consoleService` and `sendTestPush` functions: the apps report new users and stores, Console reaches each app's admin function, and a test push confirms the phone is set up
- Users tab for Axis Team, listing only real sign-in accounts
- Sign in with Google; only accounts with a `developers/{uid}` document get in

### Changed
- Renamed from Optic to Console (package `com.axisoptic.console`, alert channel `console_alerts`)
- Axis Team's Stores tab signs in to Team with a short-lived developer token from Team's `consoleAdmin`, instead of a Team account and password
- The apps' `optic.js` admin functions are now `console.js`, and calls between projects use Google-signed identity tokens, with no shared secrets
- Black-and-white look (`lib/theme.dart`), with red kept for destructive actions and errors

### Security
- Axis Optic's database is open to developer logins only (`firestore.rules`)

## [0.1.0] — 2026-11-17

### Added
- First saved version of Optic, the Android admin hub for the Axis apps: feedback inbox, push alerts, per-app user admin, traffic and Axis Team's Stores tab
