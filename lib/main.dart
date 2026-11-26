// Console: Axis Optic's developer app.
//
// Signs in to Axis Optic (tickets, alerts, user admin) with Google. Only
// accounts with a developers/{uid} doc there get in.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_pages.dart';
import 'firebase_options.dart';
import 'google_data.dart';
import 'notifications.dart';
import 'services.dart';
import 'team_firebase.dart';
import 'theme.dart';
import 'ticket_pages.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await showPush(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: kBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initTeamApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const ConsoleApp());
}

class ConsoleApp extends StatelessWidget {
  const ConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Console',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: buildConsoleTheme(),
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}

/// Signs in (Firebase remembers it), then checks it's a developer login.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data ?? FirebaseAuth.instance.currentUser;
        if (user == null) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return const SignInPage();
        }
        return FutureBuilder<bool>(
          key: ValueKey(user.uid),
          future: _isDeveloper(user),
          builder: (context, dev) {
            if (!dev.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (dev.data != true) return _NotDeveloper(email: user.email ?? user.uid, uid: user.uid);
            final name = (user.displayName?.isNotEmpty == true) ? user.displayName! : 'David';
            return PushSetup(
              developerName: name,
              child: ConsoleHomeScreen(developerName: name),
            );
          },
        );
      },
    );
  }

  /// A developer login has a developers/{uid} doc in Axis Optic (added by
  /// hand in the Firebase console).
  static Future<bool> _isDeveloper(User user) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('developers').doc(user.uid).get();
      if (!doc.exists) return false;
      // Axis Team's Stores tab needs Console signed in there too (no second
      // login: Axis Team hands Console a token). Its pages open after this.
      await connectTeam().timeout(const Duration(seconds: 15), onTimeout: () {});
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _NotDeveloper extends StatelessWidget {
  const _NotDeveloper({required this.email, required this.uid});
  final String email;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 36, color: kTextFaint),
              const SizedBox(height: 16),
              Text(
                '$email isn\'t a developer login.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextDim),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'To let it in, add developers/$uid in Axis Optic\'s Firestore.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextFaint, fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: GoogleData.instance.signOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home is the Apps page; every app's tickets are one tap away in its header.
class ConsoleHomeScreen extends StatelessWidget {
  const ConsoleHomeScreen({super.key, required this.developerName});
  final String developerName;

  @override
  Widget build(BuildContext context) => AppsPage(developerName: developerName);
}

/// Saves this phone for Console notifications and opens the ticket (or the app /
/// user an alert is about) when one is tapped.
class PushSetup extends StatefulWidget {
  const PushSetup({super.key, required this.child, this.developerName = 'Developer'});
  final Widget child;
  final String developerName;

  @override
  State<PushSetup> createState() => _PushSetupState();
}

class _PushSetupState extends State<PushSetup> {
  final _subs = <StreamSubscription>[];
  OverlayEntry? _bannerEntry;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  @override
  void dispose() {
    _bannerEntry?.remove();
    _bannerEntry = null;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _save(String token) => FirebaseFirestore.instance.collection('console').doc('devices').set({
    'tokens': FieldValue.arrayUnion([token]),
    'updated_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> _setUp() async {
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      await initNotifications(onTap: _openData);
      final token = await fm.getToken();
      if (token != null) await _save(token);
      _subs.add(fm.onTokenRefresh.listen(_save));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
      _subs.add(FirebaseMessaging.onMessage.listen(_inApp));
      final first = await fm.getInitialMessage();
      final launched = first?.data ?? await launchNotificationData();
      if (launched != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openData(launched));
      }
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
  }

  void _push(Widget page) {
    void navigate() => navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
    if (navigatorKey.currentState != null) {
      navigate();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    }
  }

  /// An app alert (new user, new store, ...): open that user, or the app.
  void _openAppEvent(Map<String, dynamic> data) {
    final service = serviceById(data['service'] as String?);
    if (service == null) return;
    final uid = data['uid'] as String? ?? '';
    if (service.remoteUsers && uid.isNotEmpty) {
      _push(ServiceUserPage(service: service, uid: uid));
    } else {
      final tab = data['event'] == 'new_store' ? 'Stores' : 'Alerts';
      _push(ServicePage(service: service, developerName: widget.developerName, initialTab: tab));
    }
  }

  Future<void> _open(RemoteMessage m) => _openData(m.data);

  /// Opens what a push is about (from its data).
  Future<void> _openData(Map<String, dynamic> data) async {
    if (data['type'] == 'app_event') return _openAppEvent(data);
    final path = data['ticket_path'];
    if (path is! String || path.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.doc(path).get();
      if (!doc.exists) return;
      void navigate() {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => TicketPage(ticketRef: doc.reference)),
        );
      }
      if (navigatorKey.currentState != null) {
        navigate();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
      }
    } catch (e) {
      debugPrint('Could not open ticket: $e');
    }
  }

  // In-app notification banner floating at the TOP of the screen.
  // Never blocks bottom action buttons.
  void _inApp(RemoteMessage m) {
    HapticFeedback.heavyImpact();
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _bannerEntry?.remove();
    _bannerEntry = null;

    final event = m.data['type'] == 'app_event';
    final service = serviceById(m.data['service'] as String?) ?? serviceForApp('${m.data['app'] ?? ''}');
    final bug = m.data['ticket_type'] == 'Bug';
    final (pushTitle, body) = pushText(m);
    final title = pushTitle.isNotEmpty ? pushTitle : (event ? 'Console' : (bug ? 'New bug' : 'New improvement'));

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _InAppNotificationBanner(
        title: title,
        body: body,
        bug: bug,
        service: service,
        onTap: () {
          try {
            entry.remove();
          } catch (_) {}
          if (_bannerEntry == entry) _bannerEntry = null;
          _open(m);
        },
        onDismiss: () {
          try {
            entry.remove();
          } catch (_) {}
          if (_bannerEntry == entry) _bannerEntry = null;
        },
      ),
    );
    _bannerEntry = entry;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _InAppNotificationBanner extends StatefulWidget {
  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.bug,
    required this.onTap,
    required this.onDismiss,
    this.service,
  });

  final String title;
  final String body;
  final bool bug;

  /// The app it's about; its icon shows on the banner.
  final ConsoleService? service;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(const Duration(seconds: 5), _dismiss);
  }

  void _dismiss() async {
    _timer?.cancel();
    if (mounted) {
      await _controller.reverse();
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offset,
          child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onTap: () {
                _timer?.cancel();
                widget.onTap();
              },
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! < -6) {
                  _dismiss();
                }
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: kSurfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kLine, width: 0.8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: Row(
                  children: [
                    if (widget.service case final s?)
                      AppIcon(s, size: 38)
                    else
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(10)),
                        child: Icon(
                          widget.bug ? Icons.bug_report_outlined : Icons.lightbulb_outline_rounded,
                          color: kText,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14.5),
                          ),
                          if (widget.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kTextDim, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: kText, borderRadius: BorderRadius.circular(99)),
                      child: const Text(
                        'Open',
                        style: TextStyle(color: kBg, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sign in
// =============================================================================

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await GoogleData.instance.signIn();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _error = e.code == GoogleSignInExceptionCode.clientConfigurationError
            ? 'Google sign-in isn\'t set up for Console yet (see the README).'
            : (e.description ?? e.code.name));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.code == 'admin-restricted-operation'
          ? 'New sign-ups are turned off for Axis Optic.'
          : (e.message ?? 'Couldn\'t sign in.'));
    } catch (e) {
      setState(() => _error = 'Couldn\'t sign in. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/optic_mark.png', width: 64, height: 64)),
                  const SizedBox(height: 28),
                  const Text(
                    'Console',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, letterSpacing: 6),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'AXIS OPTIC DEVELOPER',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextFaint, fontSize: 11.5, letterSpacing: 2.4),
                  ),
                  const SizedBox(height: 48),
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.account_circle_outlined),
                    label: const Text('Sign in with Google'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kDanger, fontSize: 13)),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Developer accounts only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextFaint, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
