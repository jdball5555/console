# Optic

Axis Optic's developer app for your phone.

- **Tickets:** feedback from every Axis app (Axis Team, Scorecards, ...).
  Bugs show in red and improvements in blue. You can reply, close or reopen.
- **Apps:** one page per app, with tabs for:
  - **Feedback:** that app's tickets.
  - **The app's own pages:** Axis Team → Stores.
  - **Users:** for apps with their own optic.js (Scorecards, Optimizer).
    Search and open a user to change their name, email, sign-in block,
    notification settings and premium beta, sign them out everywhere, or get
    a password reset link. Optimizer shares its project with Asset Track and
    Axis Journal, so it lists only accounts that have opened Optimizer, and
    name, email and sign-in changes apply to all three.
  - **Traffic:** visitors, page views, top pages (Google Analytics) and
    Cloud Functions calls/failures, once a Google account is connected
    (Apps → the account button at the top). The same button lists every
    Firebase project that account can see.
  - **Alerts:** switch each push notification on or off for that app (new
    feedback, replies, new user, new store, ...). Recent activity is listed
    below the switches.

## How it fits together

Optic signs in to the Axis Team Firebase project (`project-attendance-app`).

| What | Where |
| --- | --- |
| Tickets | `users/{uid}/feedback/{ticketId}`, read with a collection-group query. Other apps send theirs through `submitAppFeedback`. |
| Phones to notify | `dev/devices.tokens` |
| Alert switches | `dev/notification_prefs` → `{ <appId>: { <alertKey>: false } }` (anything missing is on) |
| Activity feed | `dev/activity.events` (last 150) |
| Other apps' users | Optic → `opticService` (Axis Team) → that app's `opticAdmin` |
| Other apps' alerts | the app's functions → `reportAppEvent` (Axis Team) → your phone |

Calls between projects use Google-signed tokens from each project's Cloud
Functions service account, so there are no shared secrets to set up.

## Adding an app

1. **Optic:** add an `OpticService` to `kServices` in `lib/services.dart`.
   Its `name` must match the `app` field on its tickets.
2. **If the app has its own Firebase project:**
   - Add it to `EXTERNAL_APPS` in `axis-team/functions/index.js` (project id,
     id, name, admin URL, service accounts).
   - Copy `scorecards_app/functions/optic.js` into the app's functions.
     Change its APP section (user fields, settings, stats) and
     `Object.assign(exports, require("./optic"))` in its `index.js`.
   - Set `remoteUsers: true` in Optic. The Users tab then works with no other
     Optic code.
3. **Icon:** `python3 tool/add_app_icon.py <id> <the app's square icon>`.
   It writes `assets/apps/<id>.png` as a rounded square, used across Optic
   and on the right side of that app's notifications.
4. **Deploy:** the app's functions, then Axis Team's functions.

## Running

Only developer logins can use it: an email in `kDeveloperEmails`
(lib/main.dart), or `developer: true` on its `/users/{uid}` document. User
admin for other apps also checks the email on the server (`DEVELOPER_EMAILS`
in axis-team/functions/index.js).

Run it on your phone from VS Code (Run → Start Debugging) or
`flutter run --release`.

## Google account (Traffic and Firebase projects)

Optic reads Google's APIs directly with the developer's own Google account,
read-only (`lib/google_data.dart`): Firebase Management (projects, each one's
Analytics property), Analytics Data (traffic) and Cloud Monitoring (function
calls and failures). One-time setup, all in `project-attendance-app`:

1. Firebase console → Authentication → Sign-in method → add **Google**. This
   creates the web OAuth client Google sign-in needs on Android.
2. Re-download `android/app/google-services.json`
   (`firebase apps:sdkconfig ANDROID 1:282213766426:android:b75bdac2b6baaf3c4848a3 --project project-attendance-app -o android/app/google-services.json`)
   and rebuild. Optic's signing SHA-1/SHA-256 are already registered.
3. Turn on the **Google Analytics Data API**, **Cloud Monitoring API** and
   **Firebase Management API** for the project in Google Cloud.
4. Each app's traffic needs Google Analytics on in its Firebase project
   (Project settings → Integrations) and `firebase_analytics` in the app.

The first time you connect, Google may warn that the app isn't verified (it's
your own OAuth app): Advanced → continue. If it says the app is in testing,
add your Google account as a test user (Google Auth Platform → Audience).
