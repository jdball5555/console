// The ticket inbox and one ticket's conversation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'services.dart';
import 'theme.dart';
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

  /// Shown inside an app's page: no app bar.
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
      appBar: widget.embedded ? null : AppBar(title: const Text('All tickets')),
      body: StreamBuilder<List<Ticket>>(
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: _CountCard(
                          count: bugs,
                          label: bugs == 1 ? 'Open bug' : 'Open bugs',
                          icon: Icons.bug_report_outlined,
                          selected: _tab == _Tab.open && _kind == _Kind.bugs,
                          onTap: () => setState(() {
                            _tab = _Tab.open;
                            _kind = _kind == _Kind.bugs ? _Kind.all : _Kind.bugs;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CountCard(
                          count: ideas,
                          label: ideas == 1 ? 'Improvement' : 'Improvements',
                          icon: Icons.lightbulb_outline_rounded,
                          selected: _tab == _Tab.open && _kind == _Kind.improvements,
                          onTap: () => setState(() {
                            _tab = _Tab.open;
                            _kind = _kind == _Kind.improvements ? _Kind.all : _Kind.improvements;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: SegmentedButton<_Tab>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: _Tab.open, label: Text('Open ${open.length}')),
                      ButtonSegment(
                        value: _Tab.waiting,
                        label: Text('Closed ${all.where((t) => t.isClosed).length}'),
                      ),
                      const ButtonSegment(value: _Tab.done, label: Text('Done')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
              ),
              if (_tab == _Tab.waiting)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'You closed these. Waiting for the sender to agree or reopen.',
                      style: TextStyle(color: kTextFaint, fontSize: 13),
                    ),
                  ),
                ),
              if (snap.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: Icons.error_outline_rounded,
                    text: 'Tickets couldn\'t load. Check the Firestore rules for feedback.\n${snap.error}',
                  ),
                )
              else if (!snap.hasData)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (shown.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: Icons.inbox_outlined,
                    text: _tab == _Tab.open
                        ? (widget.app == null ? 'No open tickets.' : 'No open ${widget.app} tickets.')
                        : 'Nothing here.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _TicketCard(ticket: shown[i], allTickets: shown, index: i),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.count,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final int count;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? kBg : kText;
    final dim = selected ? kBg.withValues(alpha: 0.6) : kTextDim;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? kText : kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? kText : kLine, width: 0.8),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: dim),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: dim, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 40, height: 1, fontWeight: FontWeight.w300, color: fg, letterSpacing: -1),
                ),
              ],
            ),
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
    final service = serviceForApp(t.app);
    return Material(
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kLine, width: 0.8),
      ),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(t.icon, size: 15, color: kTextDim),
                  const SizedBox(width: 6),
                  Text(
                    t.typeLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: kTextDim,
                    ),
                  ),
                  if (t.waitingOnMe && replies.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const _Pill('New reply', filled: true),
                  ],
                  if (t.reopenedCount > 0) ...[
                    const SizedBox(width: 6),
                    const _Pill('Reopened'),
                  ],
                  const Spacer(),
                  Text(timeAgo(t.updated), style: const TextStyle(fontSize: 12, color: kTextFaint)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15.5, height: 1.4, color: kText),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (service != null) ...[AppIcon(service, size: 16), const SizedBox(width: 6)],
                  Expanded(
                    child: _SenderName(
                      ticket: t,
                      prefix: [t.app, if (t.hasLocation) t.location].join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: kTextFaint),
                    ),
                  ),
                  if (replies.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.chat_bubble_outline_rounded, size: 13, color: kTextFaint),
                    const SizedBox(width: 4),
                    Text('${replies.length}', style: const TextStyle(fontSize: 12.5, color: kTextFaint)),
                  ],
                ],
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
  const _SenderName({required this.ticket, required this.style, this.prefix});
  final Ticket ticket;
  final TextStyle style;

  /// Shown before the name, e.g. "Axis Team · Schedule".
  final String? prefix;

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
      return [
        if (prefix != null && prefix!.isNotEmpty) prefix!,
        who,
        ?store,
      ].join(' · ');
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
  const _Pill(this.label, {this.filled = false});
  final String label;

  /// White with black text, for things that need attention.
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
    decoration: BoxDecoration(
      color: filled ? kText : Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: filled ? kText : kLine),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: filled ? kBg : kTextDim),
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
        Icon(icon, size: 32, color: kTextFaint),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kTextFaint)),
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
          color: kDanger,
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
              style: TextStyle(color: kTextDim),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'What changed? (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
        showTopToast(context, 'All open tickets closed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showTopToast(
          context,
          'Couldn\'t close ticket: $e',
          icon: Icons.error_outline_rounded,
          color: kDanger,
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
          return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final t = Ticket(snap.data!);
        final statusLabel = t.isOpen
            ? (t.reopenedCount > 0 ? 'Reopened' : 'Open')
            : t.isClosed
            ? 'Closed · waiting on sender'
            : 'Done · sender agreed';
        final service = serviceForApp(t.app);

        return Scaffold(
          appBar: AppBar(
            title: Text(t.typeLabel),
            actions: [
              if (_queue.length > 1) ...[
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
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
                    '${_currentIndex + 1}/${_queue.length}',
                    style: const TextStyle(fontSize: 13, color: kTextDim, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Next ticket',
                  onPressed: _currentIndex < _queue.length - 1
                      ? () => setState(() {
                          _currentIndex++;
                          _currentRef = _queue[_currentIndex];
                          _reply.clear();
                        })
                      : null,
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  children: [
                    // The ticket.
                    Row(
                      children: [
                        _Pill(statusLabel, filled: t.isOpen),
                        const Spacer(),
                        Text(timeAgo(t.created), style: const TextStyle(fontSize: 12.5, color: kTextFaint)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SelectableText(
                      t.message,
                      style: const TextStyle(fontSize: 19, height: 1.45, fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: panelDecoration(radius: 14),
                      child: Column(
                        children: [
                          _MetaRow(
                            label: 'App',
                            leading: service == null ? null : AppIcon(service, size: 18),
                            child: Text(t.app),
                          ),
                          if (t.hasLocation) ...[
                            const Divider(height: 1, indent: 14, endIndent: 14),
                            _MetaRow(label: 'Location', child: Text(t.location)),
                          ],
                          const Divider(height: 1, indent: 14, endIndent: 14),
                          _MetaRow(
                            label: 'From',
                            child: _SenderName(ticket: t, style: const TextStyle(color: kText)),
                          ),
                        ],
                      ),
                    ),
                    const SectionLabel('Conversation'),
                    if (t.replies.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No replies yet.', textAlign: TextAlign.center, style: TextStyle(color: kTextFaint)),
                      ),
                    for (final r in t.replies) _Bubble(reply: r),
                  ],
                ),
              ),
              // Actions + reply box.
              Container(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(
                  color: kBg,
                  border: Border(top: BorderSide(color: kLine, width: 0.6)),
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
                              hintText: 'Reply…',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: kLine),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: kLine),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: kTextDim),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: kText,
                            foregroundColor: kBg,
                            minimumSize: const Size(46, 46),
                          ),
                          onPressed: _busy
                              ? null
                              : () {
                                  final text = _reply.text.trim();
                                  if (text.isEmpty) return;
                                  _reply.clear();
                                  _run(() => TicketWrites.reply(t, text, _devName), 'Reply sent');
                                },
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: t.isOpen
                          ? FilledButton(
                              onPressed: _busy ? null : () => _close(t),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                              child: const Text('Close ticket'),
                            )
                          : OutlinedButton(
                              onPressed: _busy ? null : () => _run(() => TicketWrites.reopen(t), 'Reopened'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                              child: const Text('Reopen'),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.child, this.leading});
  final String label;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        SizedBox(width: 78, child: Text(label, style: const TextStyle(color: kTextFaint, fontSize: 13.5))),
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 14, color: kText),
            child: child,
          ),
        ),
      ],
    ),
  );
}

/// Floating top notification toast so it never covers bottom action buttons.
void showTopToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_rounded,
  Color color = kText,
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
                  color: kSurfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kLine, width: 0.8),
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
                          color: kText,
                          fontWeight: FontWeight.w500,
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
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: mine ? kText : kSurfaceHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
              ),
              child: SelectableText(
                reply.text,
                style: TextStyle(fontSize: 15, height: 1.35, color: mine ? kBg : kText),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
              child: Text(
                '${mine ? 'You' : (reply.name.isEmpty ? 'Them' : reply.name)} · ${timeAgo(reply.at)}',
                style: const TextStyle(fontSize: 11.5, color: kTextFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
