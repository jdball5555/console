// Optic: Axis Optic's developer app.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_pages.dart';
import 'firebase_options.dart';
import 'notifications.dart';
import 'services.dart';
import 'ticket_pages.dart';
import 'tickets.dart';

/// Logins that can use Optic (or set `developer: true` on /users/{uid}).
const kDeveloperEmails = {'david@axisoptic.com', 'jdball0292@gmail.com'};

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await showPush(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const OpticApp());
}

class OpticApp extends StatelessWidget {
  const OpticApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B0B0D);
    const card = Color(0xFF17171B);
    final scheme = ColorScheme.fromSeed(
      seedColor: kRed,
      brightness: Brightness.dark,
    ).copyWith(primary: kRed, surface: card);
    return MaterialApp(
      title: 'Optic',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        cardColor: card,
        dividerColor: const Color(0xFF26262C),
        appBarTheme: const AppBarTheme(backgroundColor: bg, surfaceTintColor: Colors.transparent),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
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
            if (dev.data != true) return _NotDeveloper(email: user.email ?? user.uid);
            final name = (user.displayName?.isNotEmpty == true) ? user.displayName! : 'David';
            return PushSetup(
              developerName: name,
              child: OpticHomeScreen(developerName: name),
            );
          },
        );
      },
    );
  }

  static Future<bool> _isDeveloper(User user) async {
    if (kDeveloperEmails.contains((user.email ?? '').toLowerCase())) return true;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      return doc.data()?['developer'] == true;
    } catch (_) {
      return false;
    }
  }
}

class _NotDeveloper extends StatelessWidget {
  const _NotDeveloper({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 40, color: Colors.white54),
              const SizedBox(height: 12),
              Text('$email isn\'t a developer login.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: FirebaseAuth.instance.signOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Main shell: Tickets (every app's feedback) and Apps (one page per app).
class OpticHomeScreen extends StatefulWidget {
  const OpticHomeScreen({super.key, required this.developerName});
  final String developerName;

  @override
  State<OpticHomeScreen> createState() => _OpticHomeScreenState();
}

class _OpticHomeScreenState extends State<OpticHomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          TicketsPage(developerName: widget.developerName),
          AppsPage(developerName: widget.developerName),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141418),
          border: Border(
            top: BorderSide(color: Color(0xFF26262C), width: 0.8),
          ),
        ),
        child: StreamBuilder<List<Ticket>>(
          stream: allTickets(),
          builder: (context, ticketsSnap) {
            final openCount = (ticketsSnap.data ?? const <Ticket>[]).where((t) => t.isOpen).length;

            Widget badged(IconData icon) => openCount > 0
                ? Badge.count(count: openCount, backgroundColor: kRed, textColor: Colors.white, child: Icon(icon))
                : Icon(icon);

            return NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 64,
                backgroundColor: Colors.transparent,
                indicatorColor: kRed.withValues(alpha: 0.2),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white);
                  }
                  return const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF8E8E93));
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const IconThemeData(color: kRed, size: 24);
                  }
                  return const IconThemeData(color: Color(0xFF8E8E93), size: 24);
                }),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (idx) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = idx);
                },
                destinations: [
                  NavigationDestination(
                    icon: badged(Icons.confirmation_number_outlined),
                    selectedIcon: badged(Icons.confirmation_number_rounded),
                    label: 'Tickets',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.apps_outlined),
                    selectedIcon: Icon(Icons.apps_rounded),
                    label: 'Apps',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Saves this phone for Optic notifications and opens the ticket (or the app /
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

  Future<void> _save(String token) => FirebaseFirestore.instance.collection('dev').doc('devices').set({
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
    final title = pushTitle.isNotEmpty ? pushTitle : (event ? 'Optic' : (bug ? 'New bug' : 'New improvement'));

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _InAppNotificationBanner(
        title: title,
        body: body,
        bug: bug,
        accent: event ? service?.color : null,
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
    this.accent,
    this.service,
  });

  final String title;
  final String body;
  final bool bug;

  /// The app's color, for app alerts.
  final Color? accent;

  /// The app it's about; its icon shows on the banner.
  final OpticService? service;
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
    final accentColor = widget.accent ?? (widget.bug ? kRed : kBlue);
    return Positioned(
      top: topPadding + 8,
      left: 14,
      right: 14,
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withValues(alpha: 0.65), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (widget.service case final s?)
                      AppIcon(s, size: 36)
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.bug ? Icons.bug_report_rounded : Icons.lightbulb_rounded,
                          color: accentColor,
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
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Open',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found'
          ? 'Wrong email or password.'
          : (e.message ?? 'Couldn\'t sign in.'));
    } catch (_) {
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
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/optic_mark.png', width: 96, height: 96)),
                  const SizedBox(height: 14),
                  const Text(
                    'Optic',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Axis Optic developer tools',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _signIn(),
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: kRed)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Use your Axis Team login.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
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


