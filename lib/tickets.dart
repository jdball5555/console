// Feedback tickets from the Axis apps.
//
// Firestore: users/{uid}/feedback/{ticketId}
//   type: "Bug" | "Improvement"
//   message, submitted_by (uid), store_id, timestamp
//   submitter_name, submitter_email, store_name     (newer tickets)
//   status: "Open"      waiting on a developer
//           "Closed"    a developer closed it; waiting for the sender
//           "Resolved"  the sender agreed it's done
//   replies: [ { from: "developer" | "user", name, text, at } ]
//   closed_at, updated_at, reopened_count

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const kRed = Color(0xFFFF4C52);
const kBlue = Color(0xFF4C8DFF);
const kGreen = Color(0xFF4CC38A);
const kAmber = Color(0xFFF5B83D);

class Reply {
  const Reply({required this.fromDeveloper, required this.name, required this.text, this.at});
  final bool fromDeveloper;
  final String name;
  final String text;
  final DateTime? at;

  static Reply fromJson(Map j) => Reply(
    fromDeveloper: j['from'] == 'developer',
    name: j['name'] as String? ?? '',
    text: j['text'] as String? ?? '',
    at: (j['at'] as Timestamp?)?.toDate(),
  );
}

class Ticket {
  Ticket(this.doc);
  final DocumentSnapshot<Map<String, dynamic>> doc;

  Map<String, dynamic> get _d => doc.data() ?? const {};
  DocumentReference<Map<String, dynamic>> get ref => doc.reference;
  String get id => doc.id;

  /// The uid of the person who sent it (the users/{uid} parent).
  String get userId => _d['submitted_by'] as String? ?? doc.reference.parent.parent?.id ?? '';

  bool get isBug => (_d['type'] as String? ?? '') == 'Bug';
  Color get color => isBug ? kRed : kBlue;
  IconData get icon => isBug ? Icons.bug_report_rounded : Icons.lightbulb_rounded;
  String get typeLabel => isBug ? 'Bug' : 'Improvement';

  /// What app or website this feedback is for (defaults to "Axis Team").
  String get app => _d['app'] as String? ?? _d['app_name'] as String? ?? 'Axis Team';

  /// Where on the website/app it is located (e.g. "Schedule", "Shift Board", "Settings").
  String get location => (_d['location'] as String? ?? _d['page'] as String? ?? '').trim();
  bool get hasLocation => location.isNotEmpty;

  String get message => _d['message'] as String? ?? '';
  String get status => _d['status'] as String? ?? 'Open';
  bool get isOpen => status == 'Open';
  bool get isClosed => status == 'Closed';
  bool get isResolved => status == 'Resolved';
  int get reopenedCount => (_d['reopened_count'] as num?)?.toInt() ?? 0;

  String? get submitterName => _d['submitter_name'] as String?;
  String? get submitterEmail => _d['submitter_email'] as String?;
  String? get storeName => _d['store_name'] as String?;
  String get storeId => _d['store_id'] as String? ?? '';

  DateTime? get created => (_d['timestamp'] as Timestamp?)?.toDate();
  DateTime? get updated => (_d['updated_at'] as Timestamp?)?.toDate() ?? created;

  List<Reply> get replies => [
    for (final r in (_d['replies'] as List? ?? const []))
      if (r is Map) Reply.fromJson(r),
  ];

  /// The sender wrote last (needs an answer).
  bool get waitingOnMe {
    final r = replies;
    return isOpen && (r.isEmpty || !r.last.fromDeveloper);
  }
}

/// Comparator for ticket lists:
/// 1. All bugs should be above all improvements.
/// 2. Oldest tickets at the top, newer tickets at the bottom (ascending creation time).
int compareTickets(Ticket a, Ticket b) {
  // All bugs should be above all improvements
  if (a.isBug != b.isBug) {
    return a.isBug ? -1 : 1;
  }
  // Oldest first (ascending timestamp)
  final aTime = a.created ?? a.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.created ?? b.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
  final cmp = aTime.compareTo(bTime);
  if (cmp != 0) return cmp;
  return a.id.compareTo(b.id);
}

/// Every ticket from every Axis Team login.
Stream<List<Ticket>> allTickets() => FirebaseFirestore.instance
    .collectionGroup('feedback')
    .snapshots()
    .map((s) => [for (final d in s.docs) Ticket(d)]..sort(compareTickets));

/// Name / email of a sender from their login (for older tickets).
Future<Map<String, dynamic>?> senderProfile(String uid) async {
  if (uid.isEmpty) return null;
  try {
    final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return d.data();
  } catch (_) {
    return null;
  }
}

class TicketWrites {
  static Map<String, dynamic> _reply(String text, String name) => {
    'from': 'developer',
    'name': name,
    'text': text,
    'at': Timestamp.now(),
  };

  static Future<void> reply(Ticket t, String text, String name) => t.ref.update({
    'replies': FieldValue.arrayUnion([_reply(text, name)]),
    'updated_at': FieldValue.serverTimestamp(),
    'last_reply_from': 'developer',
  });

  /// Closes it (with an optional note the sender sees).
  static Future<void> close(Ticket t, String note, String name) => t.ref.update({
    'status': 'Closed',
    'closed_at': FieldValue.serverTimestamp(),
    'updated_at': FieldValue.serverTimestamp(),
    'last_reply_from': 'developer',
    if (note.trim().isNotEmpty) 'replies': FieldValue.arrayUnion([_reply(note.trim(), name)]),
  });

  static Future<void> reopen(Ticket t) => t.ref.update({
    'status': 'Open',
    'updated_at': FieldValue.serverTimestamp(),
  });
}

String timeAgo(DateTime? d) {
  if (d == null) return 'just now';
  final s = DateTime.now().difference(d);
  if (s.inMinutes < 1) return 'just now';
  if (s.inMinutes < 60) return '${s.inMinutes}m ago';
  if (s.inHours < 24) return '${s.inHours}h ago';
  if (s.inDays < 7) return '${s.inDays}d ago';
  return '${d.month}/${d.day}/${d.year}';
}
