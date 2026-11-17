// The Apps tab: one page per Axis app (lib/services.dart) with its feedback,
// its own tabs (Axis Team → Stores), its users and its alerts.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'project_pages.dart';
import 'service_api.dart';
import 'services.dart';
import 'ticket_pages.dart';
import 'tickets.dart';

const _kCard = Color(0xFF17171C);
const _kBorder = Color(0xFF26262E);

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
    showTopToast(context, '$e', icon: Icons.error_outline_rounded, color: kRed);

// =============================================================================
// Apps hub
// =============================================================================

class AppsPage extends StatelessWidget {
  const AppsPage({super.key, required this.developerName});
  final String developerName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Ticket>>(
          stream: allTickets(),
          builder: (context, snap) {
            final tickets = snap.data ?? const <Ticket>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
                  child: Row(
                    children: [
                      Image.asset('assets/optic_mark.png', width: 34, height: 34),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Apps', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ),
                      const GoogleAccountButton(),
                    ],
                  ),
                ),
                for (final s in kServices) ...[
                  _ServiceCard(
                    service: s,
                    tickets: [for (final t in tickets) if (t.isOpen && serviceForApp(t.app)?.id == s.id) t],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ServicePage(service: s, developerName: developerName)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.tickets, required this.onTap});
  final OpticService service;
  final List<Ticket> tickets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bugs = tickets.where((t) => t.isBug).length;
    final ideas = tickets.length - bugs;
    return Material(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: service.color.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              AppIcon(service, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(service.tagline, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(icon: Icons.bug_report_rounded, label: '$bugs', color: kRed, dim: bugs == 0),
                        _Chip(icon: Icons.lightbulb_rounded, label: '$ideas', color: kBlue, dim: ideas == 0),
                        for (final t in service.tabs) _Chip(icon: t.icon, label: t.label, color: Colors.white70),
                        if (service.remoteUsers)
                          const _Chip(icon: Icons.people_alt_rounded, label: 'Users', color: Colors.white70),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({this.icon, this.leading, required this.label, required this.color, this.dim = false});
  final IconData? icon;

  /// In place of [icon] (e.g. an app's icon).
  final Widget? leading;
  final String label;
  final Color color;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = dim ? Colors.white30 : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ?? Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
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
  final OpticService service;
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
        ('Traffic', Icons.insights_rounded, ProjectStatsView(projectId: id, color: service.color)),
      ('Alerts', Icons.notifications_active_rounded, ServiceAlertsTab(service: service)),
    ];
    final start = tabs.indexWhere((t) => t.$1 == initialTab);

    return DefaultTabController(
      length: tabs.length,
      initialIndex: start < 0 ? 0 : start,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              AppIcon(service, size: 30),
              const SizedBox(width: 10),
              Text(service.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          bottom: TabBar(
            isScrollable: tabs.length > 4,
            tabAlignment: tabs.length > 4 ? TabAlignment.start : TabAlignment.fill,
            indicatorColor: service.color,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            dividerColor: _kBorder,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: t.$1, height: 58)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

// =============================================================================
// Users (apps with optic.js)
// =============================================================================

enum _UserFilter { all, newThisWeek, blocked }

class ServiceUsersTab extends StatefulWidget {
  const ServiceUsersTab({super.key, required this.service});
  final OpticService service;

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
    final color = widget.service.color;
    return RefreshIndicator(
      color: color,
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
              SliverToBoxAdapter(child: _StatsRow(future: _stats, color: color)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search name or email…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _q.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: _search.clear),
                      filled: true,
                      fillColor: _kCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: color, width: 1.5),
                      ),
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
                          showCheckmark: false,
                          selectedColor: color.withValues(alpha: 0.25),
                          side: BorderSide(color: _filter == f ? color : _kBorder),
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
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
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
                      color: color,
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
  const _StatsRow({required this.future, required this.color});
  final Future<List<ServiceStat>> future;
  final Color color;

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
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${stats[i].value ?? '—'}',
                    style: TextStyle(fontSize: 22, height: 1, fontWeight: FontWeight.w800, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600),
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
  const _Avatar({required this.text, required this.color, this.size = 42});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
    child: Text(
      _initials(text),
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.36),
    ),
  );
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.color, required this.onTap});
  final ServiceUser user;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (user.created != null) 'Joined ${timeAgo(user.created)}',
      ...user.tags,
    ].join(' · ');
    return Material(
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: user.disabled ? kRed.withValues(alpha: 0.5) : _kBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Avatar(text: user.displayName, color: user.disabled ? Colors.white38 : color),
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
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        if (user.disabled) ...[
                          const SizedBox(width: 6),
                          const _Chip(icon: Icons.block_rounded, label: 'Blocked', color: kRed),
                        ],
                      ],
                    ),
                    if (user.email.isNotEmpty && user.email != user.displayName)
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white30),
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
  final OpticService service;
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
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            if (f.hint != null) ...[
              const SizedBox(height: 8),
              Text(f.hint!, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
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
            style: FilledButton.styleFrom(backgroundColor: danger ? kRed : widget.service.color),
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
    final color = widget.service.color;
    final user = _detail?.user ?? widget.preview;
    return Scaffold(
      appBar: AppBar(title: Text(user?.displayName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w700))),
      body: RefreshIndicator(
        color: color,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (user != null) _UserHeader(user: user, color: color, service: widget.service),
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
              const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))
            else ...[
              for (final s in _detail!.sections) _section(s, color),
              if (_detail!.actions.isNotEmpty) ...[
                const _SectionTitle('Actions'),
                for (final a in _detail!.actions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: a.danger ? kRed : Colors.white,
                        side: BorderSide(color: a.danger ? kRed.withValues(alpha: 0.6) : _kBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _busy.contains('action:${a.id}') ? null : () => _run(a),
                      icon: _busy.contains('action:${a.id}')
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_actionIcon(a.icon), size: 18),
                      label: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _section(SettingSection s, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(s.title),
        if (s.note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(s.note!, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          ),
        Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            children: [
              for (var i = 0; i < s.fields.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _field(s.fields[i], color),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(SettingField f, Color color) {
    final busy = f.key != null && _busy.contains(f.key);
    final value = _value(f);
    switch (f.type) {
      case 'bool':
        final activeColor = f.danger ? kRed : color;
        return SwitchListTile(
          title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: f.hint == null
              ? null
              : Text(f.hint!, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          value: value == true,
          activeThumbColor: Colors.white,
          activeTrackColor: activeColor,
          secondary: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onChanged: busy ? null : (v) => _toggle(f, v),
        );
      case 'text':
        final text = '${value ?? ''}';
        return ListTile(
          title: Text(f.label, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          subtitle: Text(
            text.isEmpty ? 'Not set' : text,
            style: TextStyle(
              color: text.isEmpty ? Colors.white38 : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.edit_rounded, size: 18, color: color),
          onTap: busy ? null : () => _editText(f),
        );
      default:
        final text = f.format == 'date' && value is String
            ? formatDate(DateTime.tryParse(value)?.toLocal())
            : (value == null || '$value'.isEmpty ? '—' : '$value');
        return ListTile(
          dense: true,
          title: Text(f.label, style: const TextStyle(color: Colors.white60, fontSize: 13.5)),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              text,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
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
  const _UserHeader({required this.user, required this.color, required this.service});
  final ServiceUser user;
  final Color color;
  final OpticService service;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _Avatar(text: user.displayName, color: user.disabled ? Colors.white38 : color, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (user.email.isNotEmpty && user.email != user.displayName)
                  Text(user.email, style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(leading: AppIcon(service, size: 15), label: service.name, color: color),
                    if (user.disabled) const _Chip(icon: Icons.block_rounded, label: 'Blocked', color: kRed),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8),
    ),
  );
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
          Icon(icon, size: 44, color: Colors.white24),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
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
  final OpticService service;

  IconData _iconFor(String event) {
    for (final a in service.allAlerts) {
      if (a.key == event) return a.icon;
    }
    return Icons.notifications_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = service.color;
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
                    'Alert settings couldn\'t load. Optic needs read/write access to dev/notification_prefs.\n${snap.error}',
              );
            }
            final prefs = snap.data ?? const <String, bool>{};
            final alerts = service.allAlerts;
            return Container(
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < alerts.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      secondary: Icon(alerts[i].icon, color: color),
                      title: Text(alerts[i].label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        alerts[i].description,
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                      ),
                      value: prefs[alerts[i].key] ?? true,
                      activeThumbColor: Colors.white,
                      activeTrackColor: color,
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
          child: Text('Goes to every phone signed in to Optic.', style: TextStyle(color: Colors.white38, fontSize: 12.5)),
        ),
        const _SectionTitle('Recent activity'),
        StreamBuilder<List<ActivityEvent>>(
          stream: activity(service.id),
          builder: (context, snap) {
            if (snap.hasError) {
              return _Message(
                icon: Icons.lock_outline_rounded,
                text: 'Activity couldn\'t load. Optic needs read access to dev/activity.\n${snap.error}',
              );
            }
            final events = snap.data;
            if (events == null) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
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
                          backgroundColor: color.withValues(alpha: 0.16),
                          child: Icon(_iconFor(e.event), color: color, size: 20),
                        ),
                        title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                        subtitle: Text(
                          [if (e.body.isNotEmpty) e.body, timeAgo(e.at)].join('\n'),
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                        ),
                        isThreeLine: e.body.isNotEmpty,
                        trailing: canOpen ? const Icon(Icons.chevron_right_rounded, color: Colors.white30) : null,
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
