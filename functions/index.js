// Axis Optic (axis-optic-ce4f2): the server behind Console.
//
// Every Axis app sends its feedback here, reports its events here, and is
// managed from here. Nothing about feedback is stored in the apps' own
// Firebase projects.
//
//   feedback         an app's signed-in user sends, lists, replies to,
//                    resolves or reopens their own tickets
//   onTicketWritten  new tickets, user replies and reopens -> developer phones
//   reportAppEvent   an app's server reports an event (new user, ...)
//   consoleService   Console -> an app's admin endpoint (users, settings)
//   sendTestPush     Console's "test notification" button
//
// Firestore (see ../firestore.rules):
//   developers/{uid}   developer logins (added by hand)
//   tickets/{id}       { service, app, type, location, message, status,
//                        replies: [{ from: "developer"|"user", name, text, at }],
//                        reopened_count, last_reply_from, submitter_name,
//                        submitter_email, submitted_by, store_id, store_name,
//                        source_project, source_uid, platform, app_version,
//                        timestamp, updated_at, closed_at, resolved_at }
//   console/devices    { tokens: [...] }               saved by Console
//   console/alerts     { <appId>: { <alertKey>: false } }  missing = on
//   console/activity   { events: [...] }  newest last, capped at 150
//
// Calls between projects use Google-signed identity tokens from each
// project's Cloud Functions service account, so there are no shared secrets.
//
// Deploy: firebase deploy --only functions,firestore (from the console folder)

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions, logger } = require("firebase-functions/v2");
const { initializeApp: initAdminApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { OAuth2Client } = require("google-auth-library");

initAdminApp();
setGlobalOptions({ region: "us-central1", maxInstances: 2 });

const db = getFirestore();
const oidc = new OAuth2Client();

const PROJECT_ID = "axis-optic-ce4f2";
const REPORT_EVENT_URL = `https://us-central1-${PROJECT_ID}.cloudfunctions.net/reportAppEvent`;

// ---------------------------------------------------------------------------
// The Axis apps, by Firebase project id.
//   id               Console's id for the app (lib/services.dart in Console)
//   name             name shown in Console (tickets' `app` field)
//   adminUrl         the app's Console admin endpoint (users, settings);
//                    called by consoleService. Leave out if it has none.
//   serviceAccounts  that project's Cloud Functions accounts, trusted to POST
//                    events to reportAppEvent
// Adding an app: add it here, give it a console.js (copy Scorecards'
// functions/console.js), and add it to kServices in Console.
// ---------------------------------------------------------------------------
const APPS = {
  "project-attendance-app": {
    id: "axis_team",
    name: "Axis Team",
    adminUrl: "https://us-central1-project-attendance-app.cloudfunctions.net/consoleAdmin",
    serviceAccounts: [
      "project-attendance-app@appspot.gserviceaccount.com",
      "282213766426-compute@developer.gserviceaccount.com",
    ],
  },
  "scorecards-app": {
    id: "scorecards",
    name: "Scorecards",
    adminUrl: "https://us-central1-scorecards-app.cloudfunctions.net/consoleAdmin",
    serviceAccounts: [
      "scorecards-app@appspot.gserviceaccount.com",
      "589112385745-compute@developer.gserviceaccount.com",
    ],
  },
  // Optimizer shares project-axis-app (and its service accounts) with Asset
  // Track and Axis Journal. Only Optimizer talks to Axis Optic from there
  // today; if another of them joins, this entry needs splitting by more than
  // project and service account.
  "project-axis-app": {
    id: "optimizer",
    name: "Optimizer",
    adminUrl: "https://us-central1-project-axis-app.cloudfunctions.net/optimizerConsoleAdmin",
    serviceAccounts: [
      "project-axis-app@appspot.gserviceaccount.com",
      "290026173104-compute@developer.gserviceaccount.com",
    ],
  },
};

// Tokens that will never work again (app uninstalled, signed out, ...).
const DEAD_TOKEN = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

const tickets = db.collection("tickets");
const devicesRef = db.collection("console").doc("devices");
const alertsRef = db.collection("console").doc("alerts");
const activityRef = db.collection("console").doc("activity");

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

function bearer(req) {
  return String(req.get("Authorization") || "").replace(/^Bearer\s+/i, "");
}

const str = (v, max) => String(v == null ? "" : v).trim().slice(0, max);

// ---------------------------------------------------------------------------
// Developers
// ---------------------------------------------------------------------------

/** Whether this sign-in (an Axis Optic login) is a developer. */
async function isDeveloper(auth) {
  if (!auth || !auth.uid) return false;
  const doc = await db.collection("developers").doc(auth.uid).get();
  return doc.exists;
}

async function requireDeveloper(request) {
  if (!(await isDeveloper(request.auth))) {
    throw new HttpsError("permission-denied", "Only Console developer logins can do that.");
  }
}

/** Console's id for an app, from the name on its tickets ("Axis Team" -> axis_team). */
function serviceIdForApp(appName) {
  const name = String(appName || "").trim().toLowerCase();
  for (const info of Object.values(APPS)) {
    if (info.name.toLowerCase() === name) return info.id;
  }
  return name.replace(/[^a-z0-9]+/g, "_") || "unknown";
}

// ---------------------------------------------------------------------------
// Pushes to the developers' phones (Console)
// ---------------------------------------------------------------------------

/**
 * A data message so Console draws it: the Axis Optic mark as the small icon
 * and the icon of the app it's about (`data.service`) on the right. See
 * Console's lib/notifications.dart.
 */
function consolePush(tokens, { title, body, color, data }) {
  const strData = {};
  for (const [k, v] of Object.entries(data || {})) strData[k] = String(v == null ? "" : v);
  return {
    tokens,
    data: {
      ...strData,
      title: String(title || "Console").slice(0, 120),
      body: String(body || "").slice(0, 300),
      color: String(color || ""),
    },
    android: { priority: "high" },
  };
}

/** Sends to every developer phone and drops tokens that no longer work. */
async function pushToDevelopers(message) {
  const devices = await devicesRef.get();
  const tokens = [...new Set((devices.get("tokens") || []).filter((t) => typeof t === "string" && t))];
  if (!tokens.length) return { status: "no_device", successCount: 0, failureCount: 0 };
  const res = await getMessaging().sendEachForMulticast(consolePush(tokens, message));
  const dead = [];
  res.responses.forEach((r, i) => {
    if (!r.success && DEAD_TOKEN.has(r.error && r.error.code)) dead.push(tokens[i]);
  });
  if (dead.length) await devicesRef.update({ tokens: FieldValue.arrayRemove(...dead) });
  return {
    status: res.successCount > 0 ? "sent" : "failed",
    successCount: res.successCount,
    failureCount: res.failureCount,
  };
}

/** Whether the developers want this alert (Console → app → Alerts). On unless switched off. */
async function developersWant(serviceId, alertKey) {
  try {
    const prefs = await alertsRef.get();
    const forApp = (prefs.exists && prefs.get(serviceId)) || {};
    return forApp[alertKey] !== false;
  } catch (e) {
    logger.warn("Could not read console/alerts; sending anyway", e);
    return true;
  }
}

/** Adds an entry to the activity feed Console shows for each app. */
async function logActivity(serviceId, alertKey, title, body, data) {
  const entry = {
    id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    service: serviceId,
    event: alertKey,
    title: String(title || "").slice(0, 120),
    body: String(body || "").slice(0, 300),
    data: data || {},
    at: Timestamp.now(),
  };
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(activityRef);
    const events = (snap.exists && Array.isArray(snap.get("events")) ? snap.get("events") : []).concat(entry);
    tx.set(activityRef, { events: events.slice(-150), updated_at: FieldValue.serverTimestamp() }, { merge: true });
  });
}

/** Logs an app event and, if that alert is on in Console, pushes it. */
async function notifyDevelopers(serviceId, alertKey, { title, body, data = {}, color = "#FF4C52" }) {
  try {
    await logActivity(serviceId, alertKey, title, body, data);
  } catch (e) {
    logger.warn("Could not log activity", e);
  }
  if (!(await developersWant(serviceId, alertKey))) {
    logger.info(`Alert skipped: ${serviceId}.${alertKey} is off in Console`);
    return "muted";
  }
  const r = await pushToDevelopers({
    title,
    body,
    color,
    data: { ...data, type: "app_event", service: serviceId, event: alertKey },
  });
  logger.info(`Alert ${serviceId}.${alertKey}: ${r.successCount} sent, ${r.failureCount} failed`);
  return r.status;
}

// ---------------------------------------------------------------------------
// Feedback: the apps' users and their own tickets
// ---------------------------------------------------------------------------
//
// POST https://us-central1-axis-optic-ce4f2.cloudfunctions.net/feedback
//   Authorization: Bearer <the user's Firebase ID token from their app>
//   { action: "submit", type: "Bug"|"Improvement", location, message,
//     submitter_name?, platform?, app_version?, store_id?, store_name?,
//     extra?: { up to 10 short app-specific details } }
//   { action: "list" }                     -> { tickets: [...] }
//   { action: "reply", id, text, name? }   their ticket must be Open
//   { action: "resolve", id }              their ticket must be Closed
//   { action: "reopen", id, text?, name? } their ticket must be Closed
//
// The app is whichever project issued the sign-in token (its `aud`), and it
// must be in APPS. Times come back as milliseconds since 1970.

const externalAuth = {};
function authFor(projectId) {
  if (!externalAuth[projectId]) {
    // Only the project id is needed to verify that project's ID tokens.
    externalAuth[projectId] = getAuth(initAdminApp({ projectId }, `app-${projectId}`));
  }
  return externalAuth[projectId];
}

/** The app and user behind an app sign-in token. */
async function appUser(req) {
  const token = bearer(req);
  if (!token) throw httpError(401, "Missing sign-in token");
  let projectId = "";
  try {
    const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
    projectId = String(payload.aud || "");
  } catch (_) {
    throw httpError(401, "Bad sign-in token");
  }
  const app = APPS[projectId];
  if (!app) throw httpError(403, "Unknown app");
  try {
    const user = await authFor(projectId).verifyIdToken(token);
    return { app, projectId, user };
  } catch (e) {
    logger.warn("feedback: token rejected", e.code || e.message);
    throw httpError(401, "Sign-in expired. Please sign in again.");
  }
}

function myTickets(projectId, uid) {
  return tickets.where("source_project", "==", projectId).where("source_uid", "==", uid).get();
}

async function ownedTicket(projectId, uid, id) {
  const ref = tickets.doc(str(id, 100) || "-");
  const snap = await ref.get();
  if (!snap.exists || snap.get("source_project") !== projectId || snap.get("source_uid") !== uid) {
    throw httpError(404, "Ticket not found");
  }
  return snap;
}

const millis = (t) => (t && typeof t.toMillis === "function" ? t.toMillis() : null);

/** A ticket as the sender sees it. */
function forSender(snap) {
  const d = snap.data() || {};
  return {
    id: snap.id,
    type: d.type === "Bug" ? "Bug" : "Improvement",
    app: d.app || "",
    location: d.location || "",
    message: d.message || "",
    status: d.status || "Open",
    reopened_count: d.reopened_count || 0,
    store_id: d.store_id || "",
    replies: (Array.isArray(d.replies) ? d.replies : []).map((r) => ({
      from: r.from === "developer" ? "developer" : "user",
      name: r.from === "developer" ? "Developer" : r.name || "",
      text: r.text || "",
      at: millis(r.at),
    })),
    timestamp: millis(d.timestamp),
    updated_at: millis(d.updated_at),
  };
}

/** Up to 10 short app-specific details (e.g. Scorecards' game requests). */
function smallExtra(extra) {
  const out = {};
  if (!extra || typeof extra !== "object" || Array.isArray(extra)) return out;
  for (const [k, v] of Object.entries(extra).slice(0, 10)) {
    const key = String(k).replace(/[^a-zA-Z0-9_]/g, "").slice(0, 40);
    if (!key) continue;
    if (typeof v === "boolean" || typeof v === "number") out[key] = v;
    else if (v != null) out[key] = String(v).slice(0, 200);
  }
  return out;
}

function userReply(text, name) {
  return { from: "user", name, text, at: Timestamp.now() };
}

const userActions = {
  async submit({ app, projectId, user, body }) {
    const message = str(body.message, 4000);
    if (!message) throw httpError(400, "Message is required");

    // Light flood protection: one ticket per person every 15 seconds.
    const mine = await myTickets(projectId, user.uid);
    const last = Math.max(0, ...mine.docs.map((d) => millis(d.get("timestamp")) || 0));
    if (Date.now() - last < 15000) throw httpError(429, "Please wait a moment before sending more feedback.");

    const doc = await tickets.add({
      service: app.id,
      app: app.name,
      type: body.type === "Bug" ? "Bug" : "Improvement",
      location: str(body.location, 120),
      message,
      status: "Open",
      replies: [],
      reopened_count: 0,
      submitted_by: user.uid,
      submitter_name: str(body.submitter_name || user.name, 80) || null,
      submitter_email: user.email || null,
      store_id: str(body.store_id, 100) || "all",
      store_name: str(body.store_name, 120) || null,
      source_project: projectId,
      source_uid: user.uid,
      platform: str(body.platform, 20),
      app_version: str(body.app_version, 20),
      extra: smallExtra(body.extra),
      timestamp: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });
    logger.info(`Feedback from ${app.name}: tickets/${doc.id}`);
    return { id: doc.id };
  },

  async list({ projectId, user }) {
    const mine = await myTickets(projectId, user.uid);
    return { tickets: mine.docs.map(forSender) };
  },

  async reply({ projectId, user, body }) {
    const text = str(body.text, 4000);
    if (!text) throw httpError(400, "Reply is empty");
    const snap = await ownedTicket(projectId, user.uid, body.id);
    if ((snap.get("status") || "Open") !== "Open") throw httpError(409, "This ticket isn't open.");
    const name = str(body.name, 80) || snap.get("submitter_name") || "";
    await snap.ref.update({
      replies: FieldValue.arrayUnion(userReply(text, name)),
      last_reply_from: "user",
      updated_at: FieldValue.serverTimestamp(),
    });
    return { ok: true };
  },

  async resolve({ projectId, user, body }) {
    const snap = await ownedTicket(projectId, user.uid, body.id);
    if (snap.get("status") !== "Closed") throw httpError(409, "Only a closed ticket can be marked done.");
    await snap.ref.update({
      status: "Resolved",
      resolved_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });
    return { ok: true };
  },

  async reopen({ projectId, user, body }) {
    const snap = await ownedTicket(projectId, user.uid, body.id);
    if (snap.get("status") !== "Closed") throw httpError(409, "Only a closed ticket can be reopened.");
    const text = str(body.text, 4000);
    const name = str(body.name, 80) || snap.get("submitter_name") || "";
    await snap.ref.update({
      status: "Open",
      reopened_count: FieldValue.increment(1),
      last_reply_from: "user",
      ...(text ? { replies: FieldValue.arrayUnion(userReply(text, name)) } : {}),
      updated_at: FieldValue.serverTimestamp(),
    });
    return { ok: true };
  },
};

exports.feedback = onRequest({ cors: true, maxInstances: 5 }, async (req, res) => {
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
  try {
    const caller = await appUser(req);
    const body = req.body || {};
    const action = String(body.action || "submit");
    const handler = Object.prototype.hasOwnProperty.call(userActions, action) && userActions[action];
    if (!handler) throw httpError(400, `Unknown action "${action}"`);
    return res.status(200).json(await handler({ ...caller, body }));
  } catch (e) {
    if (e.status) return res.status(e.status).json({ error: e.message });
    logger.error("feedback failed", e);
    return res.status(500).json({ error: "Something went wrong. Please try again." });
  }
});

// New tickets, user replies and reopens -> developer phones.
exports.onTicketWritten = onDocumentWritten({ document: "tickets/{ticketId}", maxInstances: 1 }, async (event) => {
  if (!event.data || !event.data.after.exists) return;

  const before = event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.data();
  const isNew = !before;
  // Tickets copied over from the old setup (tools/move_feedback.js) aren't news.
  if (isNew && after.migrated) return;
  const isBug = after.type === "Bug";
  const name = after.submitter_name || "Someone";
  const app = after.app || "Axis Team";
  const location = (after.location || "").trim();
  const locPrefix = location ? `[${app} • ${location}] ` : `[${app}] `;

  let title = "";
  let body = "";
  if (isNew) {
    title = isBug ? `🔴 Bug from ${name}` : `🔵 Improvement from ${name}`;
    body = (locPrefix + String(after.message || "")).slice(0, 300);
  } else {
    const repliesBefore = Array.isArray(before.replies) ? before.replies.length : 0;
    const repliesAfter = Array.isArray(after.replies) ? after.replies.length : 0;
    const reopenedBefore = Number(before.reopened_count || 0);
    const reopenedAfter = Number(after.reopened_count || 0);
    if (reopenedAfter > reopenedBefore) {
      title = `↩️ ${name} reopened a ticket`;
      body = (locPrefix + String(after.message || "")).slice(0, 300);
    } else if (after.last_reply_from === "user" && repliesAfter > repliesBefore) {
      const lastReply = after.replies[repliesAfter - 1];
      title = `💬 ${lastReply.name || name} replied`;
      body = String(lastReply.text || "").slice(0, 300);
    } else {
      return;
    }
  }

  // Per-app switches in Console (App → Alerts): new tickets vs. replies/reopens.
  const serviceId = after.service || serviceIdForApp(app);
  const alertKey = isNew ? "new_feedback" : "feedback_replies";
  if (!(await developersWant(serviceId, alertKey))) {
    logger.info(`Feedback push skipped: ${serviceId}.${alertKey} is off in Console`);
    return;
  }

  const r = await pushToDevelopers({
    title,
    body,
    color: isBug ? "#FF4C52" : "#4C8DFF",
    data: {
      type: "feedback",
      service: serviceId,
      ticket_type: isBug ? "Bug" : "Improvement",
      ticket_path: `tickets/${event.params.ticketId}`,
      app,
      location,
    },
  });
  logger.info(`Feedback push: ${title} (${r.successCount} succeeded, ${r.failureCount} failed)`);
});

// ---------------------------------------------------------------------------
// App events (new user, new store, ...)
// ---------------------------------------------------------------------------

/** Which app a Google identity token belongs to (by service account). */
async function appForServiceToken(token, audience) {
  const ticket = await oidc.verifyIdToken({ idToken: token, audience });
  const p = ticket.getPayload() || {};
  const email = String(p.email || "").toLowerCase();
  if (!p.email_verified) throw new Error(`unverified service account ${email}`);
  const app = Object.values(APPS).find((a) => (a.serviceAccounts || []).includes(email));
  if (!app) throw new Error(`untrusted service account ${email || p.sub}`);
  return app;
}

// POST https://us-central1-axis-optic-ce4f2.cloudfunctions.net/reportAppEvent
//   Authorization: Bearer <Google identity token for this URL, from the app's
//                  Cloud Functions service account>
//   { event: "new_user", title, body, data?: { uid, ... }, color? }
exports.reportAppEvent = onRequest({}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
  const token = bearer(req);
  if (!token) return res.status(401).json({ error: "Missing token" });

  let app;
  try {
    app = await appForServiceToken(token, REPORT_EVENT_URL);
  } catch (e) {
    logger.warn("reportAppEvent: rejected", e.message);
    return res.status(403).json({ error: "Not allowed" });
  }

  const b = req.body || {};
  const alertKey = String(b.event || "").replace(/[^a-z0-9_]/gi, "").slice(0, 40);
  if (!alertKey) return res.status(400).json({ error: "event is required" });
  const data = {};
  if (b.data && typeof b.data === "object") {
    for (const [k, v] of Object.entries(b.data).slice(0, 20)) data[String(k).slice(0, 40)] = String(v).slice(0, 200);
  }
  const color = /^#[0-9a-f]{6}$/i.test(String(b.color || "")) ? b.color : "#7855C1";
  const result = await notifyDevelopers(app.id, alertKey, {
    title: String(b.title || `${app.name}: ${alertKey}`),
    body: String(b.body || ""),
    data,
    color,
  });
  return res.status(200).json({ ok: true, result });
});

// ---------------------------------------------------------------------------
// Console -> an app's admin endpoint
// ---------------------------------------------------------------------------

/** A Google identity token from this function's service account, for `audience`. */
async function googleIdentityToken(audience) {
  const url =
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity" +
    `?format=full&audience=${encodeURIComponent(audience)}`;
  const r = await fetch(url, { headers: { "Metadata-Flavor": "Google" } });
  if (!r.ok) throw new Error(`metadata identity token: HTTP ${r.status}`);
  return r.text();
}

// Callable: { service: "scorecards", action: "listUsers" | "getUser" |
//             "updateUser" | "userAction" | "summary", ... }
exports.consoleService = onCall({ timeoutSeconds: 60 }, async (request) => {
  await requireDeveloper(request);
  const data = request.data || {};
  const app = Object.values(APPS).find((a) => a.id === data.service);
  if (!app || !app.adminUrl) throw new HttpsError("not-found", `No admin endpoint for "${data.service}".`);

  let res;
  try {
    const token = await googleIdentityToken(app.adminUrl);
    res = await fetch(app.adminUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ ...data, by: request.auth.token.email || request.auth.uid }),
      signal: AbortSignal.timeout(45000),
    });
  } catch (e) {
    logger.error(`consoleService: ${app.name} unreachable`, e);
    throw new HttpsError("unavailable", `${app.name} couldn't be reached.`);
  }
  let json = {};
  try {
    json = await res.json();
  } catch (_) {}
  if (!res.ok) {
    logger.warn(`consoleService: ${app.name} said ${res.status}`, json);
    const code = res.status === 404 ? "not-found" : res.status === 400 ? "invalid-argument" : res.status === 403 ? "permission-denied" : "internal";
    throw new HttpsError(code, json.error || `${app.name} returned HTTP ${res.status}`);
  }
  return json;
});

// Console's "Send a test notification" button.
exports.sendTestPush = onCall({}, async (request) => {
  await requireDeveloper(request);
  const r = await pushToDevelopers({
    title: "Test notification from Console",
    body: "Push notification delivery confirmed on your phone.",
    color: "#FF4C52",
    data: { type: "test" },
  });
  if (r.status === "no_device") throw new HttpsError("failed-precondition", "No phone is registered for notifications yet.");
  return r;
});
