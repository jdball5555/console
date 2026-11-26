// One-time move of all feedback and Console data into Axis Optic.
//
//   From Axis Team (project-attendance-app):
//     users/*/feedback/*         every app's tickets   -> tickets/{same id}
//     dev/notification_prefs     alert switches        -> console/alerts
//     dev/activity               activity feed         -> console/activity
//     dev/devices                old Optic phones      (deleted only: Console
//                                registers its phone again when you sign in)
//     notifications (type "feedback")  old queued pushes (deleted only)
//   From Scorecards (scorecards-app):
//     feedback/*                 local copies; the ones that never reached the
//                                inbox (sentToOptic false) become tickets
//
// Uses your Firebase CLI sign-in (`firebase login`), or gcloud's if you have
// it. No packages needed. Run it from the console folder:
//
//   node tools/move_feedback.js            dry run: shows what it would do
//   node tools/move_feedback.js --copy     copies into Axis Optic (safe to re-run)
//   node tools/move_feedback.js --delete   deletes the old copies, but only
//                                          ones already in Axis Optic
//
// Copied tickets are marked `migrated: true`, so Axis Optic doesn't send a
// push for each one.

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execSync } = require("child_process");

const HUB = "axis-optic-ce4f2";
const TEAM = "project-attendance-app";
const SCORECARDS = "scorecards-app";

// Old ticket owner ids were "<prefix>_<uid>" for the other apps.
const PREFIXES = {
  scorecards: { project: SCORECARDS, service: "scorecards", app: "Scorecards" },
  optimizer: { project: "project-axis-app", service: "optimizer", app: "Optimizer" },
};

const mode = process.argv.includes("--delete") ? "delete" : process.argv.includes("--copy") ? "copy" : "dry";

// ----------------------------------------------------------------- sign-in

// The Firebase CLI's own OAuth client (public, from firebase-tools).
const FIREBASE_CLI_CLIENT = {
  id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
  secret: "j9iVZfS8kkCEFUPaAeJV0sAi",
};

async function accessToken() {
  try {
    const t = execSync("gcloud auth print-access-token", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    if (t) return t;
  } catch (_) {}
  const file = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
  let refresh = "";
  try {
    refresh = JSON.parse(fs.readFileSync(file, "utf8")).tokens.refresh_token;
  } catch (_) {}
  if (!refresh) throw new Error("Not signed in. Run `firebase login` first.");
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refresh,
      client_id: FIREBASE_CLI_CLIENT.id,
      client_secret: FIREBASE_CLI_CLIENT.secret,
    }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error(`Couldn't use your Firebase CLI sign-in: ${JSON.stringify(j)}. Run \`firebase login --reauth\`.`);
  return j.access_token;
}

let TOKEN = "";
async function api(url, { method = "GET", body, project } = {}) {
  const headers = { Authorization: `Bearer ${TOKEN}` };
  if (body) headers["Content-Type"] = "application/json";
  if (project) headers["x-goog-user-project"] = project;
  const r = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  if (r.status === 404 && method === "GET") return null;
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`${method} ${url}: HTTP ${r.status} ${JSON.stringify(j.error || j)}`);
  return j;
}

// ----------------------------------------------------------------- Firestore (REST)

const base = (p) => `projects/${p}/databases/(default)/documents`;
const fsUrl = (p, rest = "") => `https://firestore.googleapis.com/v1/${base(p)}${rest}`;

async function runQuery(project, structuredQuery) {
  const res = await api(fsUrl(project, ":runQuery"), { method: "POST", body: { structuredQuery } });
  return res.filter((r) => r.document).map((r) => r.document);
}

async function listCollection(project, collection) {
  const out = [];
  let pageToken = "";
  do {
    const q = new URLSearchParams({ pageSize: "300", ...(pageToken ? { pageToken } : {}) });
    const res = await api(fsUrl(project, `/${collection}?${q}`));
    out.push(...((res && res.documents) || []));
    pageToken = (res && res.nextPageToken) || "";
  } while (pageToken);
  return out;
}

const getDoc = (project, docPath) => api(fsUrl(project, `/${docPath}`));

async function commit(project, writes) {
  for (let i = 0; i < writes.length; i += 400) {
    await api(fsUrl(project, ":commit"), { method: "POST", body: { writes: writes.slice(i, i + 400) } });
  }
}

async function existing(project, names) {
  const found = new Set();
  for (let i = 0; i < names.length; i += 100) {
    const res = await api(fsUrl(project, ":batchGet"), { method: "POST", body: { documents: names.slice(i, i + 100) } });
    for (const r of res) if (r.found) found.add(r.found.name);
  }
  return found;
}

const idOf = (name) => name.split("/").pop();
const str = (v) => ({ stringValue: String(v == null ? "" : v) });
const get = (fields, k) => {
  const v = (fields || {})[k];
  if (!v) return undefined;
  return v.stringValue ?? v.booleanValue ?? v.integerValue ?? v.timestampValue;
};

// ----------------------------------------------------------------- Axis Team sign-in ids

/** Axis Team's ticket owner id is its users/{id} doc; tickets need the sign-in uid. */
const uidCache = new Map();
async function lookup(body) {
  const res = await api(`https://identitytoolkit.googleapis.com/v1/projects/${TEAM}/accounts:lookup`, {
    method: "POST",
    body,
    project: TEAM,
  });
  return (res && res.users) || [];
}
async function teamSignInUid(ownerId, email) {
  if (uidCache.has(ownerId)) return uidCache.get(ownerId);
  let uid = ownerId;
  if (!(await lookup({ localId: [ownerId] })).length) {
    let mail = email;
    if (!mail) mail = get((await getDoc(TEAM, `users/${ownerId}`) || {}).fields, "email");
    if (mail) {
      const users = await lookup({ email: [String(mail).toLowerCase()] });
      if (users.length) uid = users[0].localId;
    }
  }
  uidCache.set(ownerId, uid);
  return uid;
}

// ----------------------------------------------------------------- what moves

async function teamTickets() {
  const docs = await runQuery(TEAM, { from: [{ collectionId: "feedback", allDescendants: true }] });
  const out = [];
  for (const doc of docs) {
    const parts = doc.name.split("/"); // .../documents/users/{owner}/feedback/{id}
    const owner = parts[parts.length - 3];
    const f = doc.fields || {};
    const prefix = Object.keys(PREFIXES).find((p) => owner.startsWith(`${p}_`));
    let extra;
    if (prefix) {
      const info = PREFIXES[prefix];
      const uid = get(f, "source_uid") || owner.slice(prefix.length + 1);
      extra = {
        service: str(info.service),
        app: str(get(f, "app") || info.app),
        source_project: str(get(f, "source_project") || info.project),
        source_uid: str(uid),
        submitted_by: str(uid),
      };
    } else {
      const uid = await teamSignInUid(owner, get(f, "submitter_email"));
      extra = {
        service: str("axis_team"),
        app: str(get(f, "app") || "Axis Team"),
        source_project: str(TEAM),
        source_uid: str(uid),
        submitted_by: str(uid),
      };
    }
    out.push({ oldName: doc.name, id: idOf(doc.name), fields: { ...f, ...extra, migrated: { booleanValue: true } } });
  }
  return out;
}

async function scorecardsCopies() {
  const docs = await listCollection(SCORECARDS, "feedback");
  return docs.map((doc) => {
    const f = doc.fields || {};
    const uid = get(f, "uid");
    const lost = get(f, "sentToOptic") !== true && uid && uid !== "anonymous";
    const when = (f.timestamp && f.timestamp.timestampValue) || doc.createTime;
    const name = get(f, "displayName");
    const email = get(f, "email");
    const fields = lost
      ? {
          service: str("scorecards"),
          app: str("Scorecards"),
          type: str(get(f, "type") === "bug" ? "Bug" : "Improvement"),
          location: str(get(f, "location")),
          message: str(get(f, "text")),
          status: str("Open"),
          replies: { arrayValue: {} },
          reopened_count: { integerValue: "0" },
          submitted_by: str(uid),
          submitter_name: name && name !== "none" ? str(name) : { nullValue: null },
          submitter_email: email && email !== "none" ? str(email) : { nullValue: null },
          store_id: str("all"),
          source_project: str(SCORECARDS),
          source_uid: str(uid),
          platform: str(get(f, "platform")),
          app_version: str(String(get(f, "appVersion") || "").replace(/^v/, "")),
          timestamp: { timestampValue: when },
          updated_at: { timestampValue: when },
          migrated: { booleanValue: true },
        }
      : null;
    return { oldName: doc.name, id: `scorecards_${idOf(doc.name)}`, fields };
  });
}

// [old dev/ doc, new console/ doc or null to just delete it]
const DEV_DOCS = [
  ["devices", null],
  ["notification_prefs", "alerts"],
  ["activity", "activity"],
];

const hubName = (id) => `${base(HUB)}/tickets/${id}`;

async function main() {
  TOKEN = await accessToken();
  console.log(`Mode: ${mode}${mode === "dry" ? " (nothing is changed)" : ""}\n`);
  const fromTeam = await teamTickets();
  const fromScorecards = await scorecardsCopies();
  const lost = fromScorecards.filter((c) => c.fields);
  const oldPushes = await runQuery(TEAM, {
    from: [{ collectionId: "notifications" }],
    where: { fieldFilter: { field: { fieldPath: "type" }, op: "EQUAL", value: { stringValue: "feedback" } } },
  });
  const devDocs = {};
  for (const [from] of DEV_DOCS) devDocs[from] = await getDoc(TEAM, `dev/${from}`);

  console.log(`Axis Team tickets (all apps):      ${fromTeam.length}`);
  console.log(`Scorecards local copies:           ${fromScorecards.length} (${lost.length} never reached the inbox)`);
  console.log(`Axis Team queued feedback pushes:  ${oldPushes.length}`);
  for (const [from] of DEV_DOCS) console.log(`Axis Team dev/${from}: ${devDocs[from] ? "yes" : "no"}`);

  if (mode === "copy") {
    const writes = [...fromTeam, ...lost].map((t) => ({ update: { name: hubName(t.id), fields: t.fields } }));
    for (const [from, to] of DEV_DOCS) {
      if (to && devDocs[from]) writes.push({ update: { name: `${base(HUB)}/console/${to}`, fields: devDocs[from].fields || {} } });
    }
    await commit(HUB, writes);
    console.log(`\nCopied ${fromTeam.length + lost.length} tickets and the alert switches and activity to Axis Optic.`);
  }

  if (mode === "delete") {
    const inHub = await existing(HUB, [...fromTeam, ...lost].map((t) => hubName(t.id)));
    const teamDeletes = [];
    const scorecardsDeletes = [];
    let kept = 0;
    for (const t of fromTeam) {
      if (inHub.has(hubName(t.id))) teamDeletes.push({ delete: t.oldName });
      else kept++;
    }
    // Copies that reached the inbox are already in Axis Optic as Axis Team
    // tickets; the rest must have been copied first.
    for (const c of fromScorecards) {
      if (!c.fields || inHub.has(hubName(c.id))) scorecardsDeletes.push({ delete: c.oldName });
      else kept++;
    }
    for (const d of oldPushes) teamDeletes.push({ delete: d.name });
    for (const [from, to] of DEV_DOCS) {
      if (!devDocs[from]) continue;
      if (!to || (await getDoc(HUB, `console/${to}`))) teamDeletes.push({ delete: devDocs[from].name });
      else kept++;
    }
    await commit(TEAM, teamDeletes);
    await commit(SCORECARDS, scorecardsDeletes);
    console.log(`\nDeleted ${teamDeletes.length + scorecardsDeletes.length} old documents.${kept ? ` Kept ${kept} that aren't in Axis Optic yet (run --copy first).` : ""}`);
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
