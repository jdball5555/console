// The ticket inbox and one ticket's conversation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'services.dart';
import 'tickets.dart';

String _devName = 'Developer';

enum _Tab { open, waiting, done }

enum _Kind { all, bugs, improvements }

class TicketsPage extends StatefulWidget {
  const TicketsPage({
    super.key,
    required this.developerName,
    this.app,
    this.embedded = false,
  });
  final String developerName;

  /// Only this app's tickets (its `app` name, e.g. "Scorecards"). All when null.
  final String? app;

  /// Shown inside an app's page: no Optic header.
  final bool embedded;

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  _Tab _tab = _Tab.open;
  _Kind _kind = _Kind.all;
  late final Stream<List<Ticket>> _stream = allTickets();

  @override
  Widget build(BuildContext context) {
    _devName = widget.developerName;
    return Scaffold(
      body: SafeArea(
        top: !widget.embedded,
        child: StreamBuilder<List<Ticket>>(
          stream: _stream,
          builder: (context, snap) {
            final app = widget.app?.toLowerCase();
            final all = [
              for (final t in snap.data ?? const <Ticket>[])
                if (app == null || t.app.toLowerCase() == app) t,
            ];
            final open = all.where((t) => t.isOpen).toList();
            final bugs = open.where((t) => t.isBug).length;
            final ideas = open.length - bugs;
            final shown = all.where((t) {
              final inTab = switch (_tab) {
                _Tab.open => t.isOpen,
                _Tab.waiting => t.isClosed,
                _Tab.done => t.isResolved,
              };
              final inKind = switch (_kind) {
                _Kind.all => true,
                _Kind.bugs => t.isBug,
                _Kind.improvements => !t.isBug,
              };
              return inTab && inKind;
            }).toList()
              ..sort(compareTickets);

            return CustomScrollView(
              slivers: [
                if (!widget.embedded)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/optic_mark.png',
                          width: 34,
                          height: 34,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Optic',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (val) async {
                            if (val == 'out') {
                              await FirebaseAuth.instance.signOut();
                            } else if (val == 'test') {
                              try {
                                await FirebaseFirestore.instance
                                    .collection('notifications')
                                    .add({
                                      'type': 'feedback',
                                      'ticket_type': 'Bug',
                                      'ticket_path': '',
                                      'title':
                                          '🔴 Test Notification from Optic',
                                      'body':
                                          'Push notification delivery confirmed on your phone!',
                                      'send_at': Timestamp.now(),
                                      'status': 'scheduled',
                                      'created_at':
                                          FieldValue.serverTimestamp(),
                                    });
                                if (context.mounted) {
                                  showTopToast(
                                    context,
                                    'Test notification queued! It should appear shortly.',
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  showTopToast(
                                    context,
                                    'Failed to send test: $e',
                                    icon: Icons.error_outline_rounded,
                                    color: kRed,
                                  );
                                }
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'test',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.notifications_active_outlined,
                                    size: 18,
                                  ),
                                  SizedBox(width: 10),
                                  Text('Test notification'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, widget.embedded ? 14 : 18, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: _CountCard(
                            count: bugs,
                            label: bugs == 1 ? 'open bug' : 'open bugs',
                            color: kRed,
                            icon: Icons.bug_report_rounded,
                            selected: _tab == _Tab.open && _kind == _Kind.bugs,
                            onTap: () => setState(() {
                              _tab = _Tab.open;
                              _kind = _kind == _Kind.bugs
                                  ? _Kind.all
                                  : _Kind.bugs;
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CountCard(
                            count: ideas,
                            label: ideas == 1 ? 'improvement' : 'improvements',
                            color: kBlue,
                            icon: Icons.lightbulb_rounded,
                            selected:
                                _tab == _Tab.open &&
                                _kind == _Kind.improvements,
                            onTap: () => setState(() {
                              _tab = _Tab.open;
                              _kind = _kind == _Kind.improvements
                                  ? _Kind.all
                                  : _Kind.improvements;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  sliver: SliverToBoxAdapter(
                    child: SegmentedButton<_Tab>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: _Tab.open,
                          label: Text('Open (${open.length})'),
                        ),
                        ButtonSegment(
                          value: _Tab.waiting,
                          label: Text(
                            'Closed (${all.where((t) => t.isClosed).length})',
                          ),
                        ),
                        const ButtonSegment(
                          value: _Tab.done,
                          label: Text('Done'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                ),
                if (_tab == _Tab.waiting)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(22, 6, 22, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'You closed these. Waiting for the sender to agree or reopen.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  ),
                if (snap.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      icon: Icons.error_outline_rounded,
                      text:
                          'Tickets couldn\'t load. Check the Firestore rules for feedback.\n${snap.error}',
                    ),
                  )
                else if (!snap.hasData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (shown.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      icon: Icons.inbox_rounded,
                      text: _tab == _Tab.open
                          ? (widget.app == null ? 'No open tickets. Nice.' : 'No open ${widget.app} tickets. Nice.')
                          : 'Nothing here.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _TicketCard(
                        ticket: shown[i],
                        allTickets: shown,
                        index: i,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final int count;
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: selected ? 0.22 : 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: color.withValues(alpha: selected ? 0.9 : 0.35),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, this.allTickets, this.index});
  final Ticket ticket;
  final List<Ticket>? allTickets;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final replies = t.replies;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TicketPage(
              ticketRef: t.ref,
              ticketQueue: allTickets?.map((x) => x.ref).toList(),
              queueIndex: index,
            ),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: t.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(t.icon, size: 17, color: t.color),
                          const SizedBox(width: 6),
                          Text(
                            t.typeLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: t.color,
                            ),
                          ),
                          if (t.reopenedCount > 0) ...[
                            const SizedBox(width: 8),
                            const _Pill('Reopened', color: kAmber),
                          ],
                          if (t.waitingOnMe && replies.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const _Pill('New reply', color: kAmber),
                          ],
                          const Spacer(),
                          Text(
                            timeAgo(t.updated),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (serviceForApp(t.app) case final s?)
                                  AppIcon(s, size: 14)
                                else
                                  const Icon(
                                    Icons.language_rounded,
                                    size: 12,
                                    color: Colors.white60,
                                  ),
                                const SizedBox(width: 4),
                                Text(
                                  t.app,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (t.hasLocation)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kBlue.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: kBlue.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 12,
                                    color: kBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 160,
                                    ),
                                    child: Text(
                                      t.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: kBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _SenderName(
                              ticket: t,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                          if (replies.isNotEmpty) ...[
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 14,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${replies.length}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Jane Smith · Store 121", looked up from their login for older tickets.
class _SenderName extends StatelessWidget {
  const _SenderName({required this.ticket, required this.style});
  final Ticket ticket;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    String line(String? name, String? email) {
      final who = (name != null && name.trim().isNotEmpty)
          ? name
          : (email ?? 'Someone');
      final store =
          t.storeName ??
          (t.storeId.isEmpty || t.storeId == 'all'
              ? null
              : 'Store ${t.storeId}');
      return store == null ? who : '$who · $store';
    }

    if (t.submitterName != null || t.submitterEmail != null) {
      return Text(
        line(t.submitterName, t.submitterEmail),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: senderProfile(t.userId),
      builder: (context, snap) {
        final d = snap.data;
        final name = [
          d?['first_name'],
          d?['last_name'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
        return Text(
          line(name.isEmpty ? null : name, d?['email'] as String?),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 40, color: Colors.white38),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      ],
    ),
  );
}

// =============================================================================
// One ticket
// =============================================================================

class TicketPage extends StatefulWidget {
  const TicketPage({
    super.key,
    required this.ticketRef,
    this.ticketQueue,
    this.queueIndex,
  });
  final DocumentReference<Map<String, dynamic>> ticketRef;
  final List<DocumentReference<Map<String, dynamic>>>? ticketQueue;
  final int? queueIndex;

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  final _reply = TextEditingController();
  bool _busy = false;

  late DocumentReference<Map<String, dynamic>> _currentRef;
  late List<DocumentReference<Map<String, dynamic>>> _queue;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentRef = widget.ticketRef;
    _queue = widget.ticketQueue != null
        ? List<DocumentReference<Map<String, dynamic>>>.from(
            widget.ticketQueue!,
          )
        : [_currentRef];
    _currentIndex = _queue.indexWhere((r) => r.path == _currentRef.path);
    if (_currentIndex < 0) {
      _queue.insert(0, _currentRef);
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) showTopToast(context, done);
    } catch (e) {
      if (mounted) {
        showTopToast(
          context,
          'Couldn\'t save: $e',
          icon: Icons.error_outline_rounded,
          color: kRed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(Ticket t) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close this ticket?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'They\'ll see it\'s closed on their Feedback page and can agree or reopen it.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'What changed? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close ticket'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await TicketWrites.close(t, note.text, _devName);
      if (!mounted) return;

      _reply.clear();
      // Remove closed ticket from active queue
      _queue.removeWhere((r) => r.path == t.ref.path);

      if (_queue.isNotEmpty) {
        if (_currentIndex >= _queue.length) {
          _currentIndex = _queue.length - 1;
        }
        setState(() {
          _currentRef = _queue[_currentIndex];
          _busy = false;
        });
        showTopToast(context, 'Ticket closed · Showing next');
      } else {
        // Queue exhausted: immediately return to homepage
        Navigator.of(context).popUntil((route) => route.isFirst);
        showTopToast(context, 'All open tickets closed! 🎉');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showTopToast(
          context,
          'Couldn\'t close ticket: $e',
          icon: Icons.error_outline_rounded,
          color: kRed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey(_currentRef.path),
      stream: _currentRef.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final t = Ticket(snap.data!);
        final statusLabel = t.isOpen
            ? (t.reopenedCount > 0 ? 'Reopened' : 'Open')
            : t.isClosed
            ? 'Closed · waiting on sender'
            : 'Done · sender agreed';
        final statusColor = t.isOpen
            ? (t.reopenedCount > 0 ? kAmber : t.color)
            : kGreen;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(t.icon, color: t.color),
                const SizedBox(width: 8),
                Text(
                  t.typeLabel,
                  style: TextStyle(color: t.color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: [
              if (_queue.length > 1) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                  tooltip: 'Previous ticket',
                  onPressed: _currentIndex > 0
                      ? () => setState(() {
                          _currentIndex--;
                          _currentRef = _queue[_currentIndex];
                          _reply.clear();
                        })
                      : null,
                ),
                Center(
                  child: Text(
                    '${_currentIndex + 1} of ${_queue.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  tooltip: 'Next ticket',
                  onPressed: _currentIndex < _queue.length - 1
                      ? () => setState(() {
                          _currentIndex++;
                          _currentRef = _queue[_currentIndex];
                          _reply.clear();
                        })
                      : null,
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    // The ticket.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: t.color.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _Pill(statusLabel, color: statusColor),
                              const Spacer(),
                              Text(
                                timeAgo(t.created),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.language_rounded,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'App: ${t.app}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (t.hasLocation)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kBlue.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: kBlue.withValues(alpha: 0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.place_outlined,
                                        size: 14,
                                        color: kBlue,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Location: ${t.location}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: kBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            t.message,
                            style: const TextStyle(fontSize: 16.5, height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                size: 16,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _SenderName(
                                  ticket: t,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (t.replies.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No replies yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                    for (final r in t.replies) _Bubble(reply: r),
                  ],
                ),
              ),
              // Actions + reply box.
              Container(
                padding: EdgeInsets.fromLTRB(
                  12,
                  10,
                  12,
                  10 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _reply,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Reply to them…',
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _busy
                              ? null
                              : () {
                                  final text = _reply.text.trim();
                                  if (text.isEmpty) return;
                                  _reply.clear();
                                  _run(
                                    () => TicketWrites.reply(t, text, _devName),
                                    'Reply sent.',
                                  );
                                },
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: t.isOpen
                          ? FilledButton.icon(
                              onPressed: _busy ? null : () => _close(t),
                              style: FilledButton.styleFrom(
                                backgroundColor: kGreen,
                                foregroundColor: Colors.black,
                                minimumSize: const Size.fromHeight(48),
                              ),
                              icon: const Icon(Icons.check_circle_rounded),
                              label: const Text(
                                'Close ticket',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => TicketWrites.reopen(t),
                                      'Reopened.',
                                    ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              icon: const Icon(Icons.undo_rounded),
                              label: const Text('Reopen'),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Floating top notification toast so it never covers bottom action buttons.
void showTopToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Color color = kGreen,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TopToastWidget(
      message: message,
      icon: icon,
      color: color,
      onDismissed: () {
        try {
          entry.remove();
        } catch (_) {}
      },
    ),
  );
  overlay.insert(entry);
}

class _TopToastWidget extends StatefulWidget {
  const _TopToastWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.onDismissed,
  });
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onDismissed;

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offset,
          child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onTap: () async {
                await _controller.reverse();
                widget.onDismissed();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E222A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.color, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.reply});
  final Reply reply;

  @override
  Widget build(BuildContext context) {
    final mine = reply.fromDeveloper;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: mine
                ? kRed.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mine ? 'You' : (reply.name.isEmpty ? 'Them' : reply.name)} · ${timeAgo(reply.at)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                reply.text,
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
