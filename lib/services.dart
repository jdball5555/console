// The Axis apps Optic manages, and what each one's page shows.
//
// Adding an app:
//   1. Add an OpticService below. `name` must match the `app` field on its
//      feedback tickets.
//   2. Server side (only for apps in their own Firebase project): add it to
//      EXTERNAL_APPS in axis-team/functions/index.js and give the app an
//      optic.js (copy scorecards_app/functions/optic.js). Then set
//      `remoteUsers: true` here and its Users tab works with no more Optic code.
//   3. Alerts: list the alert keys its server sends (reportAppEvent's
//      `event`). Feedback alerts come for free.
//   4. Firebase project: set `projectId` for its Traffic tab.
//   5. Icon: `python3 tool/add_app_icon.py <id> <the app's square icon>`.
//      It's used in Optic and on the right of that app's notifications.

import 'package:flutter/material.dart';

import 'stores_page.dart';
import 'tickets.dart';

/// A switch on an app's Alerts tab. `key` is what the server checks in
/// dev/notification_prefs/{serviceId}.{key}.
class ServiceAlert {
  const ServiceAlert(this.key, this.label, this.description, this.icon);
  final String key;
  final String label;
  final String description;
  final IconData icon;
}

const kFeedbackAlerts = [
  ServiceAlert('new_feedback', 'New feedback', 'A bug or improvement is sent in.', Icons.confirmation_number_rounded),
  ServiceAlert('feedback_replies', 'Replies & reopens', 'Someone answers or reopens a ticket.', Icons.forum_rounded),
];

/// An extra tab with the app's own page (e.g. Axis Team's Stores).
class ServiceTab {
  const ServiceTab(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function(BuildContext context, String developerName) builder;
}

class OpticService {
  const OpticService({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.color,
    this.projectId,
    this.alerts = const [],
    this.tabs = const [],
    this.remoteUsers = false,
  });

  /// Stable id used by the server (alerts, activity, admin). Never change it.
  final String id;

  /// Display name; also the `app` field on its feedback tickets.
  final String name;
  final String tagline;

  /// Shown only if the app has no icon file yet (see [iconAsset]).
  final IconData icon;
  final Color color;

  /// Its Firebase project: gives it a Traffic tab (Google Analytics and
  /// function stats, once a Google account is connected in Optic).
  final String? projectId;

  /// The app's rounded icon, made with tool/add_app_icon.py.
  String get iconAsset => 'assets/apps/$id.png';

  /// App-specific alerts (feedback alerts are added automatically).
  final List<ServiceAlert> alerts;

  /// App-specific tabs, shown after Feedback.
  final List<ServiceTab> tabs;

  /// Has a Users tab backed by the app's Optic admin endpoint (optic.js).
  final bool remoteUsers;

  List<ServiceAlert> get allAlerts => [...kFeedbackAlerts, ...alerts];
}

final kServices = <OpticService>[
  OpticService(
    id: 'axis_team',
    name: 'Axis Team',
    tagline: 'team.axisoptic.com',
    icon: Icons.groups_rounded,
    projectId: 'project-attendance-app',
    color: kRed,
    alerts: const [
      ServiceAlert('new_user', 'New login', 'An Axis Team login is created.', Icons.person_add_alt_1_rounded),
      ServiceAlert('new_store', 'New store', 'A store is added.', Icons.add_business_rounded),
    ],
    tabs: [
      ServiceTab(
        'Stores',
        Icons.storefront_rounded,
        (context, dev) => StoresPage(developerName: dev, embedded: true),
      ),
    ],
  ),
  const OpticService(
    id: 'scorecards',
    name: 'Scorecards',
    tagline: 'App + website',
    icon: Icons.style_rounded,
    projectId: 'scorecards-app',
    color: Color(0xFF9B7BEA),
    remoteUsers: true,
    alerts: [
      ServiceAlert('new_user', 'New user', 'Someone creates a Scorecards account.', Icons.person_add_alt_1_rounded),
    ],
  ),
  // Shares project-axis-app with Asset Track and Axis Journal; its Users tab
  // lists only the accounts that have opened Optimizer.
  const OpticService(
    id: 'optimizer',
    name: 'Optimizer',
    tagline: 'optimizer.axisoptic.com',
    icon: Icons.bolt_rounded,
    projectId: 'project-axis-app',
    color: Color(0xFF4D6BFF),
    remoteUsers: true,
    alerts: [
      ServiceAlert('new_user', 'New user', 'Someone opens Optimizer for the first time.', Icons.person_add_alt_1_rounded),
    ],
  ),
];

/// An app's icon as a rounded square (falls back to its glyph if the icon
/// file is missing).
class AppIcon extends StatelessWidget {
  const AppIcon(this.service, {super.key, this.size = 40});
  final OpticService service;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.225),
      child: Image.asset(
        service.iconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: service.color.withValues(alpha: 0.16),
          child: Icon(service.icon, color: service.color, size: size * 0.55),
        ),
      ),
    );
  }
}

OpticService? serviceById(String? id) {
  for (final s in kServices) {
    if (s.id == id) return s;
  }
  return null;
}

/// The app a ticket belongs to (by its `app` name).
OpticService? serviceForApp(String appName) {
  final n = appName.trim().toLowerCase();
  for (final s in kServices) {
    if (s.name.toLowerCase() == n) return s;
  }
  return null;
}
