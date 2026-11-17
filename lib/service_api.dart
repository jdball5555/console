// Data for the app pages: alert switches, the activity feed, and user admin
// for apps in other Firebase projects (through Axis Team's opticService).
//
// Firestore (Axis Team project):
//   dev/notification_prefs  { <serviceId>: { <alertKey>: bool } }  (missing = on)
//   dev/activity            { events: [ {id, service, event, title, body, data, at} ] }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

final _prefsRef = FirebaseFirestore.instance.collection('dev').doc('notification_prefs');
final _activityRef = FirebaseFirestore.instance.collection('dev').doc('activity');

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

/// This app's alert switches. Anything not saved yet counts as on.
Stream<Map<String, bool>> alertPrefs(String serviceId) => _prefsRef.snapshots().map((s) {
  final raw = s.data()?[serviceId];
  return {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is bool) e.key.toString(): e.value as bool,
  };
});

Future<void> setAlert(String serviceId, String key, bool on) => _prefsRef.set({
  serviceId: {key: on},
  'updated_at': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

class ActivityEvent {
  ActivityEvent(Map m)
    : id = '${m['id'] ?? ''}',
      service = '${m['service'] ?? ''}',
      event = '${m['event'] ?? ''}',
      title = '${m['title'] ?? ''}',
      body = '${m['body'] ?? ''}',
      data = {
        if (m['data'] is Map)
          for (final e in (m['data'] as Map).entries) '${e.key}': '${e.value}',
      },
      at = (m['at'] as Timestamp?)?.toDate();
  final String id, service, event, title, body;
  final Map<String, String> data;
  final DateTime? at;
}

/// Newest first.
Stream<List<ActivityEvent>> activity(String serviceId) => _activityRef.snapshots().map((s) {
  final raw = s.data()?['events'];
  final list = <ActivityEvent>[
    if (raw is List)
      for (final m in raw)
        if (m is Map && m['service'] == serviceId) ActivityEvent(m),
  ];
  return list.reversed.toList();
});

// ---------------------------------------------------------------------------
// Remote user admin (apps with optic.js)
// ---------------------------------------------------------------------------

class ServiceException implements Exception {
  const ServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _call(String serviceId, String action, [Map<String, dynamic> args = const {}]) async {
  try {
    final res = await FirebaseFunctions.instance
        .httpsCallable('opticService', options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
        .call<Object?>({'service': serviceId, 'action': action, ...args});
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  } on FirebaseFunctionsException catch (e) {
    if (e.code == 'not-found' && (e.message ?? '').contains('opticService')) {
      throw const ServiceException('The Optic hub isn\'t deployed yet (opticService).');
    }
    throw ServiceException(e.message ?? e.code);
  } catch (e) {
    throw ServiceException('$e');
  }
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

class ServiceUser {
  ServiceUser(Map m)
    : uid = '${m['uid'] ?? ''}',
      name = '${m['name'] ?? ''}',
      email = '${m['email'] ?? ''}',
      created = _date(m['created']),
      lastActive = _date(m['lastActive']),
      disabled = m['disabled'] == true,
      tags = [for (final t in (m['tags'] as List? ?? const [])) '$t'];
  final String uid, name, email;
  final DateTime? created, lastActive;
  final bool disabled;
  final List<String> tags;

  String get displayName => name.isNotEmpty ? name : (email.isNotEmpty ? email : 'No name');
  bool matches(String q) =>
      q.isEmpty || name.toLowerCase().contains(q) || email.toLowerCase().contains(q) || uid.toLowerCase() == q;
}

/// A setting on a user's page: `bool` (switch), `text` (editable) or `info`.
class SettingField {
  SettingField(Map m)
    : key = m['key'] as String?,
      type = '${m['type'] ?? 'info'}',
      label = '${m['label'] ?? ''}',
      value = m['value'],
      hint = m['hint'] as String?,
      format = m['format'] as String?,
      danger = m['danger'] == true,
      copy = m['copy'] == true;
  final String? key;
  final String type, label;
  final Object? value;
  final String? hint, format;
  final bool danger, copy;

  bool get editable => key != null && (type == 'bool' || type == 'text');
}

class SettingSection {
  SettingSection(Map m)
    : title = '${m['title'] ?? ''}',
      note = m['note'] as String?,
      fields = [for (final f in (m['fields'] as List? ?? const [])) if (f is Map) SettingField(f)];
  final String title;
  final String? note;
  final List<SettingField> fields;
}

class UserAction {
  UserAction(Map m)
    : id = '${m['id']}',
      label = '${m['label'] ?? m['id']}',
      icon = m['icon'] as String?,
      confirm = m['confirm'] as String?,
      danger = m['danger'] == true;
  final String id, label;
  final String? icon, confirm;
  final bool danger;
}

class UserDetail {
  UserDetail(Map<String, dynamic> m)
    : user = ServiceUser(m['user'] as Map? ?? const {}),
      sections = [for (final s in (m['sections'] as List? ?? const [])) if (s is Map) SettingSection(s)],
      actions = [for (final a in (m['actions'] as List? ?? const [])) if (a is Map) UserAction(a)];
  final ServiceUser user;
  final List<SettingSection> sections;
  final List<UserAction> actions;
}

class ServiceStat {
  ServiceStat(Map m) : label = '${m['label'] ?? ''}', value = m['value'];
  final String label;
  final Object? value;
}

class ServiceAdmin {
  const ServiceAdmin(this.serviceId);
  final String serviceId;

  Future<List<ServiceStat>> summary() async {
    final r = await _call(serviceId, 'summary');
    return [for (final s in (r['stats'] as List? ?? const [])) if (s is Map) ServiceStat(s)];
  }

  Future<List<ServiceUser>> users() async {
    final r = await _call(serviceId, 'listUsers');
    return [for (final u in (r['users'] as List? ?? const [])) if (u is Map) ServiceUser(u)];
  }

  Future<UserDetail> user(String uid) async => UserDetail(await _call(serviceId, 'getUser', {'uid': uid}));

  Future<void> update(String uid, Map<String, Object?> changes) =>
      _call(serviceId, 'updateUser', {'uid': uid, 'changes': changes});

  /// Returns `{message, copy?}`.
  Future<Map<String, dynamic>> action(String uid, String id) => _call(serviceId, 'userAction', {'uid': uid, 'id': id});
}
