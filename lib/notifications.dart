// Optic's phone notifications.
//
// Axis Team's functions send developer pushes as data messages (title, body,
// color, service, ...) so Optic draws them itself: the Optic mark as the small
// icon, and the app the alert is about (assets/apps/<service>.png) on the
// right. Older pushes with a `notification` block are still shown by Android.

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

const _channelId = 'optic_feedback_channel';
const _channelName = 'Optic alerts';
const _smallIcon = '@drawable/ic_notification';

/// Sets up local notifications. [onTap] gets the push's data when one of
/// Optic's notifications is tapped while Optic is running.
Future<void> initNotifications({void Function(Map<String, dynamic> data)? onTap}) async {
  await _plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings(_smallIcon)),
    onDidReceiveNotificationResponse: (r) {
      final data = _decode(r.payload);
      if (data != null) onTap?.call(data);
    },
  );
  _ready = true;
}

/// The data of the Optic notification that launched the app, if any.
Future<Map<String, dynamic>?> launchNotificationData() async {
  final details = await _plugin.getNotificationAppLaunchDetails();
  if (details == null || !details.didNotificationLaunchApp) return null;
  return _decode(details.notificationResponse?.payload);
}

/// Title and body of a push, from either kind of message.
(String, String) pushText(RemoteMessage m) => (
  m.notification?.title ?? m.data['title'] as String? ?? '',
  m.notification?.body ?? m.data['body'] as String? ?? '',
);

/// Shows a data push as a notification (Android already shows ones with a
/// `notification` block).
Future<void> showPush(RemoteMessage m) async {
  if (m.notification != null || defaultTargetPlatform != TargetPlatform.android) return;
  final (title, body) = pushText(m);
  if (title.isEmpty && body.isEmpty) return;
  if (!_ready) await initNotifications();

  final service = serviceById(m.data['service'] as String?);
  AndroidBitmap<Object>? largeIcon;
  if (service != null) {
    try {
      final bytes = await rootBundle.load(service.iconAsset);
      largeIcon = ByteArrayAndroidBitmap(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('No icon for ${service.id}: $e');
    }
  }

  await _plugin.show(
    id: (m.messageId ?? '${DateTime.now().microsecondsSinceEpoch}').hashCode & 0x7fffffff,
    title: title,
    body: body,
    payload: jsonEncode(m.data),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Feedback and app alerts from the Axis apps.',
        importance: Importance.max,
        priority: Priority.high,
        icon: _smallIcon,
        largeIcon: largeIcon,
        color: _color(m.data['color'] as String?),
        styleInformation: BigTextStyleInformation(body),
      ),
    ),
  );
}

Color? _color(String? hex) {
  final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

Map<String, dynamic>? _decode(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final d = jsonDecode(payload);
    return d is Map ? Map<String, dynamic>.from(d) : null;
  } catch (_) {
    return null;
  }
}
