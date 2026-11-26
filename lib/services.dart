// The Axis apps Console manages, and what each one's page shows.
//
// Adding an app:
//   1. Add a ConsoleService below. `name` must match APPS in
//      functions/index.js (it's the `app` field on its tickets).
//   2. Server side: add its Firebase project to APPS in functions/index.js.
//      For a Users tab, give the app a console.js (copy Scorecards'
//      functions/console.js), set its adminUrl in APPS, and set
//      `remoteUsers: true` here. No more Console code is needed.
//   3. Feedback: the app posts to Axis Optic's `feedback` function.
//   4. Alerts: list the alert keys its server sends (reportAppEvent's
//      `event`). Feedback alerts come for free.
//   5. Firebase project: set `projectId` for its Traffic tab.
//   6. Icon: `python3 tool/add_app_icon.py <id> <the app's square icon>`.
//      It's used in Console and on the right of that app's notifications.

import 'package:flutter/material.dart';

import 'stores_page.dart';
import 'theme.dart';

/// A switch on an app's Alerts tab. `key` is what the server checks in
/// console/alerts.{serviceId}.{key}.
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

class ConsoleService {
  const ConsoleService({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.color,
    this.website,
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

  /// Only used for the fallback icon and the app's own notifications; the
  /// Console UI itself is black and white.
  final Color color;

  /// Its website (no https://), shown under the name on the Apps page.
  final String? website;

  /// Its Firebase project: gives it a Traffic tab (Google Analytics and
  /// function stats, once a Google account is connected in Console).
  final String? projectId;

  /// The app's rounded icon, made with tool/add_app_icon.py.
  String get iconAsset => 'assets/apps/$id.png';

  /// App-specific alerts (feedback alerts are added automatically).
  final List<ServiceAlert> alerts;

  /// App-specific tabs, shown after Feedback.
  final List<ServiceTab> tabs;

  /// Has a Users tab backed by the app's Console admin endpoint (console.js).
  final bool remoteUsers;

  List<ServiceAlert> get allAlerts => [...kFeedbackAlerts, ...alerts];
}

final kServices = <ConsoleService>[
  ConsoleService(
    id: 'axis_team',
    name: 'Axis Team',
    tagline: 'team.axisoptic.com',
    website: 'team.axisoptic.com',
    icon: Icons.groups_rounded,
    projectId: 'project-attendance-app',
    color: Color(0xFFFF4C52),
    remoteUsers: true,
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
  const ConsoleService(
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
  const ConsoleService(
    id: 'optimizer',
    name: 'Optimizer',
    tagline: 'optimizer.axisoptic.com',
    website: 'optimizer.axisoptic.com',
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
  final ConsoleService service;
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
          color: kSurfaceHigh,
          child: Icon(service.icon, color: kText, size: size * 0.5),
        ),
      ),
    );
  }
}

ConsoleService? serviceById(String? id) {
  for (final s in kServices) {
    if (s.id == id) return s;
  }
  return null;
}

/// The app a ticket belongs to (by its `app` name).
ConsoleService? serviceForApp(String appName) {
  final n = appName.trim().toLowerCase();
  for (final s in kServices) {
    if (s.name.toLowerCase() == n) return s;
  }
  return null;
}
