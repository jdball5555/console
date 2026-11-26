// The Apps tab: one page per Axis app (lib/services.dart) with its feedback,
// its own tabs (Axis Team → Stores), its users and its alerts.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'google_data.dart';
import 'project_pages.dart';
import 'service_api.dart';
import 'services.dart';
import 'theme.dart';
import 'ticket_pages.dart';
import 'tickets.dart';

String formatDate(DateTime? d) {
  if (d == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, ${d.year} · $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _initials(String s) {
  final parts = s.trim().split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

void _toastError(BuildContext context, Object e) =>
    showTopToast(context, '$e', icon: Icons.error_outline_rounded, color: kDanger);

// =============================================================================
// Apps hub
// =============================================================================

/// How many users each app has. Kept for the session so the Apps page doesn't
/// reload them every time it rebuilds; pull to refresh reloads them.
final _userCounts = <String, Future<int?>>{};

Future<int?> userCount(ConsoleService s, {bool refresh = false}) {
  final cached = _userCounts[s.id];
  if (!refresh && cached != null) return cached;
  return _userCounts[s.id] = _loadUserCount(s);
}

Future<int?> _loadUserCount(ConsoleService s) async {
  try {
    if (s.remoteUsers) return (await ServiceAdmin(s.id).users()).length;
  } catch (e) {
    debugPrint('User count for ${s.id} failed: $e');
  }
  _userCounts.remove(s.id); // try again next time
  return null;
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

class AppsPage extends StatefulWidget {
  const AppsPage({super.key, required this.developerName});
  final String developerName;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  late final Stream<List<Ticket>> _tickets = allTickets();

  Future<void> _refresh() async {
    final counts = [for (final s in kServices) userCount(s, refresh: true)];
    setState(() {});
    await Future.wait(counts);
  }

  void _openTickets() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TicketsPage(developerName: widget.developerName)),
    );
  }

  Future<void> _sendTestNotification() async {
    try {
      await FirebaseFunctions.instance.httpsCallable('sendTestPush').call<Object?>();
      if (mounted) showTopToast(context, 'Test notification sent');
    } catch (e) {
      if (mounted) _toastError(context, 'Failed to send test: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Ticket>>(
          stream: _tickets,
          builder: (context, snap) {
            final open = [for (final t in snap.data ?? const <Ticket>[]) if (t.isOpen) t];
            return RefreshIndicator(
              onRefresh: _refresh,
              color: kBg,
              backgroundColor: kText,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Row(
                    children: [
                      Image.asset('assets/optic_mark.png', width: 26, height: 26),
                      const Spacer(),
                      IconButton(
                        tooltip: 'All tickets',
                        onPressed: _openTickets,
                        icon: Badge(
                          isLabelVisible: open.isNotEmpty,
                          label: Text('${open.length}'),
                          child: const Icon(Icons.inbox_outlined),
                        ),
                      ),
                      const GoogleAccountButton(),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz_rounded),
                        onSelected: (v) {
                          if (v == 'test') _sendTestNotification();
                          if (v == 'out') GoogleData.instance.signOut();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'test', child: Text('Send test notification')),
                          PopupMenuItem(value: 'out', child: Text('Sign out')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Apps',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w500, letterSpacing: -0.8, height: 1),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openTickets,
                    child: Row(
                      children: [
                        Text(
                          !snap.hasData
                              ? ' '
                              : open.isEmpty
                              ? 'No open tickets'
                              : '${open.length} open ${open.length == 1 ? 'ticket' : 'tickets'}',
                          style: const TextStyle(color: kTextDim, fontSize: 15),
                        ),
                        if (snap.hasData) const Icon(Icons.chevron_right_rounded, size: 18, color: kTextFaint),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final (i, s) in kServices.indexed) ...[
                    if (i > 0) const Divider(),
                    _AppRow(
                      service: s,
                      openTickets: open.where((t) => serviceForApp(t.app)?.id == s.id).length,
                      users: userCount(s),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServicePage(service: s, developerName: widget.developerName),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One app on the Apps page: big icon, name, website, and its user count.
class _AppRow extends StatelessWidget {
  const _AppRow({required this.service, required this.openTickets, required this.users, required this.onTap});
  final ConsoleService service;
  final int openTickets;
  final Future<int?> users;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Hero(tag: 'app-icon-${service.id}', child: AppIcon(service, size: 92)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                  ),
                  if (service.website case final site?) ...[
                    const SizedBox(height: 3),
                    Text(
                      site,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kTextDim, fontSize: 13.5),
                    ),
                  ],
                  if (openTickets > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$openTickets open ${openTickets == 1 ? 'ticket' : 'tickets'}',
                      style: const TextStyle(color: kTextFaint, fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            FutureBuilder<int?>(
              future: users,
              builder: (context, snap) {
                final n = snap.data;
                final loading = snap.connectionState != ConnectionState.done;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        loading ? '·' : (n == null ? '—' : _compact(n)),
                        key: ValueKey('$loading$n'),
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -0.8,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      n == 1 ? 'user' : 'users',
                      style: const TextStyle(color: kTextFaint, fontSize: 12, letterSpacing: 0.3),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({this.icon, this.leading, required this.label, this.color = kTextDim});
  final IconData? icon;

  /// In place of [icon] (e.g. an app's icon).
  final Widget? leading;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color == kTextDim ? kLine : color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ?? Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

// =============================================================================
// One app
// =============================================================================

class ServicePage extends StatelessWidget {
  const ServicePage({super.key, required this.service, required this.developerName, this.initialTab});
  final ConsoleService service;
  final String developerName;

  /// Tab label to open on ("Feedback", "Stores", "Users", "Alerts").
  final String? initialTab;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, IconData, Widget)>[
      (
        'Feedback',
        Icons.confirmation_number_rounded,
        TicketsPage(developerName: developerName, app: service.name, embedded: true),
      ),
      for (final t in service.tabs) (t.label, t.icon, Builder(builder: (c) => t.builder(c, developerName))),
      if (service.remoteUsers) ('Users', Icons.people_alt_rounded, ServiceUsersTab(service: service)),
      if (service.projectId case final id?)
        ('Traffic', Icons.insights_rounded, ProjectStatsView(projectId: id, color: kText)),
      ('Alerts', Icons.notifications_active_rounded, ServiceAlertsTab(service: service)),
    ];
    final start = tabs.indexWhere((t) => t.$1 == initialTab);

    return DefaultTabController(
      length: tabs.length,
      initialIndex: start < 0 ? 0 : start,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Hero(tag: 'app-icon-${service.id}', child: AppIcon(service, size: 26)),
              const SizedBox(width: 10),
              Text(service.name),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            tabs: [for (final t in tabs) Tab(text: t.$1, height: 44)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

// =============================================================================
// Users (apps with console.js)
// =============================================================================

enum _UserFilter { all, newThisWeek, blocked }

class ServiceUsersTab extends StatefulWidget {
  const ServiceUsersTab({super.key, required this.service});
  final ConsoleService service;

  @override
  State<ServiceUsersTab> createState() => _ServiceUsersTabState();
}

class _ServiceUsersTabState extends State<ServiceUsersTab> with AutomaticKeepAliveClientMixin {
  late final _api = ServiceAdmin(widget.service.id);
  late Future<List<ServiceUser>> _users = _api.users();
  late Future<List<ServiceStat>> _stats = _api.summary();
  final _search = TextEditingController();
  String _q = '';
  _UserFilter _filter = _UserFilter.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _q = _search.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _users = _api.users();
      _stats = _api.summary();
    });
    try {
      await _users;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: kBg,
      backgroundColor: kText,
      onRefresh: _reload,
      child: FutureBuilder<List<ServiceUser>>(
        future: _users,
        builder: (context, snap) {
          final weekAgo = DateTime.now().subtract(const Duration(days: 7));
          final all = snap.data ?? const <ServiceUser>[];
          final shown = all.where((u) {
            final inFilter = switch (_filter) {
              _UserFilter.all => true,
              _UserFilter.newThisWeek => u.created != null && u.created!.isAfter(weekAgo),
              _UserFilter.blocked => u.disabled,
            };
            return inFilter && u.matches(_q);
          }).toList();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _StatsRow(future: _stats)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search name or email',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: kTextFaint),
                      suffixIcon: _q.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: _search.clear),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final (f, label) in [
                        (_UserFilter.all, 'All (${all.length})'),
                        (_UserFilter.newThisWeek, 'New this week'),
                        (_UserFilter.blocked, 'Blocked'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          labelStyle: TextStyle(
                            color: _filter == f ? kBg : kTextDim,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          side: BorderSide(color: _filter == f ? kText : kLine),
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
              ),
              if (snap.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Message(
                    icon: Icons.cloud_off_rounded,
                    text: 'Couldn\'t load ${widget.service.name} users.\n${snap.error}',
                    onRetry: _reload,
                  ),
                )
              else if (snap.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (shown.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Message(icon: Icons.person_search_rounded, text: 'No users match.'),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _UserTile(
                      user: shown[i],
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ServiceUserPage(service: widget.service, uid: shown[i].uid, preview: shown[i]),
                          ),
                        );
                        if (mounted) _reload();
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.future});
  final Future<List<ServiceStat>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceStat>>(
      future: future,
      builder: (context, snap) {
        final stats = snap.data;
        if (stats == null || stats.isEmpty) return const SizedBox(height: 4);
        return SizedBox(
          height: 86,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            scrollDirection: Axis.horizontal,
            itemCount: stats.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => Container(
              width: 112,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: panelDecoration(radius: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${stats[i].value ?? '—'}',
                    style: const TextStyle(fontSize: 24, height: 1, fontWeight: FontWeight.w300, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: kTextFaint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.text, this.dim = false, this.size = 42});
  final String text;
  final bool dim;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: kSurfaceHigh,
      shape: BoxShape.circle,
      border: Border.all(color: kLine, width: 0.8),
    ),
    child: Text(
      _initials(text),
      style: TextStyle(color: dim ? kTextFaint : kText, fontWeight: FontWeight.w500, fontSize: size * 0.36),
    ),
  );
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});
  final ServiceUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (user.created != null) 'Joined ${timeAgo(user.created)}',
      ...user.tags,
    ].join(' · ');
    return Material(
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: user.disabled ? kDanger.withValues(alpha: 0.5) : kLine, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Avatar(text: user.displayName, dim: user.disabled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                          ),
                        ),
                        if (user.disabled) ...[
                          const SizedBox(width: 6),
                          const _Chip(icon: Icons.block_rounded, label: 'Blocked', color: kDanger),
                        ],
                      ],
                    ),
                    if (user.email.isNotEmpty && user.email != user.displayName)
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kTextDim, fontSize: 13),
                      ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sub, style: const TextStyle(color: kTextFaint, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kTextFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// One user's settings
// =============================================================================

class ServiceUserPage extends StatefulWidget {
  const ServiceUserPage({super.key, required this.service, required this.uid, this.preview});
  final ConsoleService service;
  final String uid;
  final ServiceUser? preview;

  @override
  State<ServiceUserPage> createState() => _ServiceUserPageState();
}

class _ServiceUserPageState extends State<ServiceUserPage> {
  late final _api = ServiceAdmin(widget.service.id);
  UserDetail? _detail;
  Object? _error;
  final Set<String> _busy = {};

  /// Changes made here that haven't been reloaded from the server yet.
  final Map<String, Object?> _local = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.user(widget.uid);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _error = null;
        _local.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Object? _value(SettingField f) => _local.containsKey(f.key) ? _local[f.key] : f.value;

  Future<void> _save(SettingField f, Object? value) async {
    final key = f.key!;
    setState(() {
      _busy.add(key);
      _local[key] = value;
    });
    try {
      await _api.update(widget.uid, {key: value});
      if (mounted) {
        HapticFeedback.lightImpact();
        showTopToast(context, '${f.label} saved');
      }
      if (f.type == 'text' || f.key == 'disabled') await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _local.remove(key));
        _toastError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _toggle(SettingField f, bool on) async {
    if (f.danger && on) {
      final ok = await _confirm('${f.label}?', f.hint ?? 'Are you sure?', f.label, danger: true);
      if (!ok) return;
    }
    await _save(f, on);
  }

  Future<void> _editText(SettingField f) async {
    final controller = TextEditingController(text: '${_value(f) ?? ''}');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: f.key == 'email' ? TextInputType.emailAddress : TextInputType.text,
              autocorrect: false,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            if (f.hint != null) ...[
              const SizedBox(height: 8),
              Text(f.hint!, style: const TextStyle(color: kTextDim, fontSize: 12.5)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim() == '${_value(f) ?? ''}') return;
    await _save(f, result.trim());
  }

  Future<bool> _confirm(String title, String body, String yes, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: kDanger, foregroundColor: kText) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(UserAction a) async {
    if (a.confirm != null && !await _confirm('${a.label}?', a.confirm!, a.label, danger: a.danger)) return;
    setState(() => _busy.add('action:${a.id}'));
    try {
      final r = await _api.action(widget.uid, a.id);
      final copy = r['copy'];
      if (copy is String && copy.isNotEmpty) await Clipboard.setData(ClipboardData(text: copy));
      if (mounted) showTopToast(context, '${r['message'] ?? 'Done'}');
    } catch (e) {
      if (mounted) _toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove('action:${a.id}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _detail?.user ?? widget.preview;
    return Scaffold(
      appBar: AppBar(title: Text(user?.displayName ?? 'User')),
      body: RefreshIndicator(
        color: kBg,
        backgroundColor: kText,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (user != null) _UserHeader(user: user, service: widget.service),
            if (_error != null && _detail == null)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: _Message(
                  icon: Icons.cloud_off_rounded,
                  text: 'Couldn\'t load this user.\n$_error',
                  onRetry: _load,
                ),
              )
            else if (_detail == null)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              for (final s in _detail!.sections) _section(s),
              if (_detail!.actions.isNotEmpty) ...[
                const _SectionTitle('Actions'),
                for (final a in _detail!.actions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: a.danger ? kDanger : kText,
                        side: BorderSide(color: a.danger ? kDanger.withValues(alpha: 0.5) : kLine),
                      ),
                      onPressed: _busy.contains('action:${a.id}') ? null : () => _run(a),
                      icon: _busy.contains('action:${a.id}')
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_actionIcon(a.icon), size: 18),
                      label: Text(a.label),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static IconData _actionIcon(String? name) => switch (name) {
    'logout' => Icons.logout_rounded,
    'key' => Icons.key_rounded,
    'delete' => Icons.delete_outline_rounded,
    'mail' => Icons.mail_outline_rounded,
    _ => Icons.bolt_rounded,
  };

  Widget _section(SettingSection s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(s.title),
        if (s.note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(s.note!, style: const TextStyle(color: kTextFaint, fontSize: 12.5)),
          ),
        Container(
          decoration: panelDecoration(),
          child: Column(
            children: [
              for (var i = 0; i < s.fields.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _field(s.fields[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(SettingField f) {
    final busy = f.key != null && _busy.contains(f.key);
    final value = _value(f);
    switch (f.type) {
      case 'bool':
        return SwitchListTile(
          title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: f.hint == null
              ? null
              : Text(f.hint!, style: const TextStyle(color: kTextFaint, fontSize: 12.5)),
          value: value == true,
          activeThumbColor: f.danger ? kText : null,
          activeTrackColor: f.danger ? kDanger : null,
          secondary: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onChanged: busy ? null : (v) => _toggle(f, v),
        );
      case 'text':
        final text = '${value ?? ''}';
        return ListTile(
          title: Text(f.label, style: const TextStyle(color: kTextFaint, fontSize: 12.5)),
          subtitle: Text(
            text.isEmpty ? 'Not set' : text,
            style: TextStyle(
              color: text.isEmpty ? kTextFaint : kText,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.edit_outlined, size: 18, color: kTextDim),
          onTap: busy ? null : () => _editText(f),
        );
      default:
        final text = f.format == 'date' && value is String
            ? formatDate(DateTime.tryParse(value)?.toLocal())
            : (value == null || '$value'.isEmpty ? '—' : '$value');
        return ListTile(
          dense: true,
          title: Text(f.label, style: const TextStyle(color: kTextDim, fontSize: 13.5)),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              text,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
            ),
          ),
          onTap: f.copy
              ? () {
                  Clipboard.setData(ClipboardData(text: text));
                  showTopToast(context, '${f.label} copied');
                }
              : null,
        );
    }
  }
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user, required this.service});
  final ServiceUser user;
  final ConsoleService service;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _Avatar(text: user.displayName, dim: user.disabled, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.3),
                ),
                if (user.email.isNotEmpty && user.email != user.displayName)
                  Text(user.email, style: const TextStyle(color: kTextDim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(leading: AppIcon(service, size: 15), label: service.name),
                    if (user.disabled) const _Chip(icon: Icons.block_rounded, label: 'Blocked', color: kDanger),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SectionLabel(text, padding: const EdgeInsets.fromLTRB(4, 24, 4, 10));
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: kTextFaint),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kTextFaint)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

// =============================================================================
// Alerts + activity
// =============================================================================

class ServiceAlertsTab extends StatelessWidget {
  const ServiceAlertsTab({super.key, required this.service});
  final ConsoleService service;

  IconData _iconFor(String event) {
    for (final a in service.allAlerts) {
      if (a.key == event) return a.icon;
    }
    return Icons.notifications_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const _SectionTitle('Push me when…'),
        StreamBuilder<Map<String, bool>>(
          stream: alertPrefs(service.id),
          builder: (context, snap) {
            if (snap.hasError) {
              return _Message(
                icon: Icons.lock_outline_rounded,
                text:
                    'Alert settings couldn\'t load. Console needs read/write access to console/alerts.\n${snap.error}',
              );
            }
            final prefs = snap.data ?? const <String, bool>{};
            final alerts = service.allAlerts;
            return Container(
              decoration: panelDecoration(),
              child: Column(
                children: [
                  for (var i = 0; i < alerts.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      secondary: Icon(alerts[i].icon, color: kTextDim, size: 22),
                      title: Text(alerts[i].label, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        alerts[i].description,
                        style: const TextStyle(color: kTextFaint, fontSize: 12.5),
                      ),
                      value: prefs[alerts[i].key] ?? true,
                      onChanged: snap.hasData
                          ? (v) async {
                              HapticFeedback.selectionClick();
                              try {
                                await setAlert(service.id, alerts[i].key, v);
                              } catch (e) {
                                if (context.mounted) _toastError(context, e);
                              }
                            }
                          : null,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text('Goes to every phone signed in to Console.', style: TextStyle(color: kTextFaint, fontSize: 12.5)),
        ),
        const _SectionTitle('Recent activity'),
        StreamBuilder<List<ActivityEvent>>(
          stream: activity(service.id),
          builder: (context, snap) {
            if (snap.hasError) {
              return _Message(
                icon: Icons.lock_outline_rounded,
                text: 'Activity couldn\'t load. Console needs read access to console/activity.\n${snap.error}',
              );
            }
            final events = snap.data;
            if (events == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (events.isEmpty) {
              return const _Message(
                icon: Icons.history_rounded,
                text: 'Nothing yet. New users and other alerts show up here.',
              );
            }
            return Column(
              children: [
                for (final e in events.take(50))
                  Builder(
                    builder: (context) {
                      final uid = e.data['uid'] ?? '';
                      final canOpen = service.remoteUsers && uid.isNotEmpty;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CircleAvatar(
                          backgroundColor: kSurfaceHigh,
                          child: Icon(_iconFor(e.event), color: kText, size: 19),
                        ),
                        title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5)),
                        subtitle: Text(
                          [if (e.body.isNotEmpty) e.body, timeAgo(e.at)].join('\n'),
                          style: const TextStyle(color: kTextFaint, fontSize: 12.5),
                        ),
                        isThreeLine: e.body.isNotEmpty,
                        trailing: canOpen ? const Icon(Icons.chevron_right_rounded, color: kTextFaint) : null,
                        onTap: canOpen
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ServiceUserPage(service: service, uid: uid)),
                              )
                            : null,
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
