// Firebase projects from your Google account (lib/google_data.dart): the
// list of projects, and each one's traffic and function health. Also each
// app's Traffic tab.

import 'package:flutter/material.dart';

import 'google_data.dart';
import 'services.dart';
import 'theme.dart';


String _count(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

ConsoleService? _serviceForProject(String projectId) {
  for (final s in kServices) {
    if (s.projectId == projectId) return s;
  }
  return null;
}

// =============================================================================
// Google account
// =============================================================================

/// The Apps page's account button: connect, or see who's connected.
class GoogleAccountButton extends StatelessWidget {
  const GoogleAccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final g = GoogleData.instance;
    g.start(); // restores the saved connection once
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final photo = g.account?.photoUrl;
        return IconButton(
          tooltip: g.connected ? 'Google account' : 'Connect Google account',
          onPressed: () => _sheet(context),
          icon: photo != null
              ? CircleAvatar(radius: 15, backgroundImage: NetworkImage(photo))
              : Icon(g.connected ? Icons.account_circle_rounded : Icons.cloud_outlined, size: 28),
        );
      },
    );
  }

  static void _sheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      builder: (context) => ListenableBuilder(
        listenable: GoogleData.instance,
        builder: (context, _) {
          final g = GoogleData.instance;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Google account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    g.connected
                        ? 'Connected as ${g.account!.email}. Console can read your Firebase projects, their Analytics traffic and their function stats. It can\'t change anything.'
                        : 'Connect the Google account that owns your Firebase projects to see every project, its traffic and its function stats here. Read-only.',
                    style: const TextStyle(color: kTextDim),
                  ),
                  if (g.error != null) ...[
                    const SizedBox(height: 10),
                    Text(g.error!, style: const TextStyle(color: kDanger)),
                  ],
                  const SizedBox(height: 16),
                  if (g.connected) ...[
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FirebaseProjectsPage()));
                      },
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Firebase projects'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: g.disconnect, child: const Text('Disconnect')),
                  ] else
                    FilledButton.icon(
                      onPressed: g.connect,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Connect Google account'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard();

  @override
  Widget build(BuildContext context) {
    final g = GoogleData.instance;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights_rounded, color: kTextDim),
              SizedBox(width: 10),
              Text('See traffic and function stats', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect the Google account that owns your Firebase projects. Console only reads; it can\'t change anything.',
            style: TextStyle(color: kTextDim),
          ),
          if (g.error != null) ...[
            const SizedBox(height: 10),
            Text(g.error!, style: const TextStyle(color: kDanger)),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: g.connect,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Connect Google account'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// All projects
// =============================================================================

class FirebaseProjectsPage extends StatefulWidget {
  const FirebaseProjectsPage({super.key});

  @override
  State<FirebaseProjectsPage> createState() => _FirebaseProjectsPageState();
}

class _FirebaseProjectsPageState extends State<FirebaseProjectsPage> {
  late Future<List<FirebaseProject>> _projects = GoogleData.instance.projects();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase projects', style: TextStyle(fontWeight: FontWeight.w600))),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _projects = GoogleData.instance.projects());
          await _projects.catchError((_) => <FirebaseProject>[]);
        },
        child: FutureBuilder<List<FirebaseProject>>(
          future: _projects,
          builder: (context, snap) {
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(16), children: [_ErrorPanel(snap.error!)]);
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final projects = snap.data!;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = projects[i];
                final service = _serviceForProject(p.id);
                return _Panel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: service != null
                        ? AppIcon(service, size: 40)
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(Icons.local_fire_department_outlined, color: kTextDim),
                          ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      service != null && service.name != p.name ? '${p.id} · ${service.name}' : p.id,
                      style: const TextStyle(color: kTextFaint, fontSize: 12.5),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: kTextFaint),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            titleSpacing: 0,
                            title: Row(
                              children: [
                                if (service != null) ...[AppIcon(service, size: 30), const SizedBox(width: 10)],
                                Flexible(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                          body: ProjectStatsView(projectId: p.id),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// One project's numbers
// =============================================================================

/// Traffic (Google Analytics) and Cloud Functions health for a project.
class ProjectStatsView extends StatefulWidget {
  const ProjectStatsView({super.key, required this.projectId, this.color});
  final String projectId;
  final Color? color;

  @override
  State<ProjectStatsView> createState() => _ProjectStatsViewState();
}

class _ProjectStatsViewState extends State<ProjectStatsView> {
  int _days = 7;
  Future<_Stats>? _stats;

  @override
  void initState() {
    super.initState();
    GoogleData.instance.addListener(_onAccount);
    GoogleData.instance.start();
    _onAccount();
  }

  @override
  void dispose() {
    GoogleData.instance.removeListener(_onAccount);
    super.dispose();
  }

  void _onAccount() {
    if (!mounted) return;
    setState(() => _stats = GoogleData.instance.connected ? _load() : null);
  }

  Future<_Stats> _load() async {
    final g = GoogleData.instance;
    final health = g.functionHealth(widget.projectId).then<Object>((h) => h, onError: (Object e) => e);
    final property = await g.analyticsProperty(widget.projectId);
    final traffic = property == null ? null : await g.traffic(property, days: _days);
    return _Stats(property: property, traffic: traffic, health: await health);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? kText;
    final stats = _stats;
    return RefreshIndicator(
      onRefresh: () async {
        if (stats == null) return;
        setState(() => _stats = _load());
        await _stats!.catchError((_) => const _Stats());
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (stats == null)
            const _ConnectCard()
          else
            FutureBuilder<_Stats>(
              future: stats,
              builder: (context, snap) {
                if (snap.hasError) return _ErrorPanel(snap.error!);
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final s = snap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('TRAFFIC', style: TextStyle(color: kTextFaint, fontWeight: FontWeight.w600, letterSpacing: 1)),
                        ),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 7, label: Text('7 days')),
                            ButtonSegment(value: 28, label: Text('28 days')),
                          ],
                          selected: {_days},
                          onSelectionChanged: (v) => setState(() {
                            _days = v.first;
                            _stats = _load();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (s.traffic case final t?)
                      ..._traffic(t, color)
                    else
                      const _Panel(
                        child: Text(
                          'Google Analytics isn\'t on for this project, so there\'s no traffic yet. '
                          'Turn it on in the Firebase console (Project settings → Integrations → Google Analytics), '
                          'then add Analytics to the app.',
                          style: TextStyle(color: kTextDim),
                        ),
                      ),
                    const SizedBox(height: 22),
                    const Text('FUNCTIONS', style: TextStyle(color: kTextFaint, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    switch (s.health) {
                      final FunctionHealth h => Row(
                        children: [
                          Expanded(child: _Stat(label: 'Calls · ${h.hours}h', value: _count(h.calls))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Stat(
                              label: 'Failed · ${h.hours}h',
                              value: _count(h.failed),
                              color: h.failed > 0 ? kDanger : null,
                            ),
                          ),
                        ],
                      ),
                      final Object? e => _ErrorPanel(e ?? 'No data'),
                    },
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  List<Widget> _traffic(Traffic t, Color color) {
    final maxViews = t.daily.fold<int>(1, (m, d) => d.views > m ? d.views : m);
    return [
      Row(
        children: [
          Expanded(child: _Stat(label: 'Visitors', value: _count(t.visitors))),
          const SizedBox(width: 10),
          Expanded(child: _Stat(label: 'Page views', value: _count(t.pageViews))),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _Stat(label: 'New visitors', value: _count(t.newVisitors))),
          const SizedBox(width: 10),
          Expanded(child: _Stat(label: 'Visits', value: _count(t.sessions))),
        ],
      ),
      const SizedBox(height: 10),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Page views per day', style: TextStyle(color: kTextDim, fontSize: 13)),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in t.daily)
                    Expanded(
                      child: Tooltip(
                        message: '${d.day.month}/${d.day.day}: ${d.views}',
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: t.daily.length > 14 ? 1 : 3),
                          height: d.views == 0 ? 2 : 4 + 86 * d.views / maxViews,
                          decoration: BoxDecoration(
                            color: d.views == 0 ? Colors.white12 : color,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(_short(t.daily.first.day), style: const TextStyle(color: kTextFaint, fontSize: 11)),
                const Spacer(),
                const Text('Today', style: TextStyle(color: kTextFaint, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(child: Text('Top pages', style: TextStyle(color: kTextDim, fontSize: 13))),
                Text('Views', style: TextStyle(color: kTextFaint, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            if (t.pages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('No page views yet.', style: TextStyle(color: kTextFaint)),
              ),
            for (final p in t.pages)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.path.isEmpty ? '(app screens)' : p.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(_count(p.views), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  static String _short(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _Stats {
  const _Stats({this.property, this.traffic, this.health});
  final String? property;
  final Traffic? traffic;

  /// A [FunctionHealth], or the error loading it.
  final Object? health;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: kTextDim, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, letterSpacing: -0.6, color: color)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: child,
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel(this.error);
  final Object error;

  @override
  Widget build(BuildContext context) {
    var text = '$error';
    if (error is GoogleDataException && (error as GoogleDataException).status == 403) {
      text = '$text\n\nThis Google account may not have access to this project, or the API needs turning on (see the README).';
    }
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: kDanger),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: kTextDim))),
        ],
      ),
    );
  }
}
