// Stores management and feature configuration page for Console.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store_takeout_service.dart';
import 'team_firebase.dart';
import 'stores.dart';
import 'ticket_pages.dart';
import 'theme.dart';

class StoresPage extends StatefulWidget {
  const StoresPage({super.key, required this.developerName, this.embedded = false});
  final String developerName;

  /// Shown inside the Axis Team app page: no Console header.
  final bool embedded;

  @override
  State<StoresPage> createState() => _StoresPageState();
}

class _StoresPageState extends State<StoresPage> {
  final _searchController = TextEditingController();
  String _search = '';
  _StoreFilter _filter = _StoreFilter.all;

  static DateTime _parseStoreCreatedAt(Map<String, dynamic> data) {
    final ca = data['created_at'];
    if (ca is Timestamp) return ca.toDate();
    if (ca is String && ca.isNotEmpty) {
      final dt = DateTime.tryParse(ca);
      if (dt != null) return dt;
    }
    final ua = data['updated_at'];
    if (ua is Timestamp) return ua.toDate();
    if (ua is String && ua.isNotEmpty) {
      final dt = DateTime.tryParse(ua);
      if (dt != null) return dt;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCreateStorePage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateStorePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateStorePage,
        backgroundColor: kText,
        foregroundColor: kBg,
        icon: const Icon(Icons.add_business_rounded, size: 20),
        label: const Text('New Store', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        top: !widget.embedded,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: teamDb.collection('stores').snapshots(),
          builder: (context, storesSnap) {
            if (storesSnap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load stores: ${storesSnap.error}',
                    style: const TextStyle(color: kDanger),
                  ),
                ),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: teamDb.collection('users').snapshots(),
              builder: (context, usersSnap) {
                if (!storesSnap.hasData || !usersSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rawDocs = storesSnap.data!.docs;
                // Order stores by newest added at the top
                final storeDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(rawDocs)
                  ..sort((a, b) {
                    final dateA = _parseStoreCreatedAt(a.data());
                    final dateB = _parseStoreCreatedAt(b.data());
                    final cmp = dateB.compareTo(dateA);
                    if (cmp != 0) return cmp;
                    return a.id.compareTo(b.id);
                  });
                final userDocs = usersSnap.data!.docs;
                final devCount = storeDocs
                    .where((d) => d.data()['is_dev'] == true || d.data()['isDev'] == true)
                    .length;

                return CustomScrollView(
                  slivers: [
                    // Header
                    if (!widget.embedded)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Image.asset('assets/optic_mark.png', width: 34, height: 34),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Stores',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                '${storeDocs.length} ${storeDocs.length == 1 ? "store" : "stores"}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Add Store',
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 24, color: Colors.white),
                              onPressed: _openCreateStorePage,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Quick Stats & Metrics Overview
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _StoreMetricsOverview(storeDocs: storeDocs),
                      ),
                    ),

                    // Search input
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search stores or owners…',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                            filled: true,
                            fillColor: kSurface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: kLine),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: kLine),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: kText, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Filter chips
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All (${storeDocs.length})',
                                selected: _filter == _StoreFilter.all,
                                onTap: () => setState(() => _filter = _StoreFilter.all),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Dev Mode ($devCount)',
                                icon: Icons.developer_mode_rounded,
                                color: kText,
                                selected: _filter == _StoreFilter.devOnly,
                                onTap: () => setState(() => _filter = _StoreFilter.devOnly),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Schedule ON',
                                icon: Icons.calendar_month_rounded,
                                color: kText,
                                selected: _filter == _StoreFilter.scheduleOn,
                                onTap: () => setState(() => _filter = _StoreFilter.scheduleOn),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Shifts ON',
                                icon: Icons.swap_horiz_rounded,
                                color: kText,
                                selected: _filter == _StoreFilter.shiftsOn,
                                onTap: () => setState(() => _filter = _StoreFilter.shiftsOn),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Stores List
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      sliver: _buildStoreList(storeDocs, userDocs),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoreList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> storeDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs,
  ) {
    if (storeDocs.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: Colors.white38),
              SizedBox(height: 12),
              Text('No stores found in Axis Team.', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      );
    }

    return SliverList.separated(
      itemCount: storeDocs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = storeDocs[index];
        final storeId = doc.id;
        final data = doc.data();
        final name = (data['name'] as String? ?? 'Store $storeId').trim();
        final isDev = data['is_dev'] == true || data['isDev'] == true;
        final owners = findStoreOwners(storeId, userDocs);

        // Search matching
        if (_search.isNotEmpty) {
          final matchName = name.toLowerCase().contains(_search);
          final matchId = storeId.toLowerCase().contains(_search);
          final matchOwner = owners.any(
            (o) => o.name.toLowerCase().contains(_search) || o.email.toLowerCase().contains(_search),
          );
          if (!matchName && !matchId && !matchOwner) {
            return const SizedBox.shrink();
          }
        }

        return _StoreCard(
          storeId: storeId,
          storeName: name,
          isDev: isDev,
          owners: owners,
          filter: _filter,
        );
      },
    );
  }
}

enum _StoreFilter { all, devOnly, scheduleOn, shiftsOn }

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? Colors.white;
    return Material(
      color: selected ? activeColor.withValues(alpha: 0.16) : kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? activeColor.withValues(alpha: 0.7) : kLine,
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? activeColor : Colors.white60),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? (color ?? Colors.white) : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overview metric count cards.
class _StoreMetricsOverview extends StatefulWidget {
  const _StoreMetricsOverview({required this.storeDocs});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> storeDocs;

  @override
  State<_StoreMetricsOverview> createState() => _StoreMetricsOverviewState();
}

class _StoreMetricsOverviewState extends State<_StoreMetricsOverview> {
  final Map<String, StoreSettingsData> _configs = {};
  final Map<String, StreamSubscription> _subs = {};

  @override
  void initState() {
    super.initState();
    _syncSubscriptions();
  }

  @override
  void didUpdateWidget(covariant _StoreMetricsOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSubscriptions();
  }

  void _syncSubscriptions() {
    final currentIds = widget.storeDocs.map((d) => d.id).toSet();
    final toRemove = _subs.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in toRemove) {
      _subs[id]?.cancel();
      _subs.remove(id);
      _configs.remove(id);
    }
    for (final doc in widget.storeDocs) {
      if (!_subs.containsKey(doc.id)) {
        _subs[doc.id] = teamDb
            .collection('stores')
            .doc(doc.id)
            .collection('settings')
            .doc('global_config')
            .snapshots()
            .listen((snap) {
          if (mounted) {
            setState(() {
              _configs[doc.id] = StoreSettingsData.fromMap(snap.data());
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int scheduleCount = 0;
    int shiftCount = 0;
    int devCount = 0;

    for (final doc in widget.storeDocs) {
      final d = doc.data();
      if (d['is_dev'] == true || d['isDev'] == true) {
        devCount++;
      }
    }

    for (final config in _configs.values) {
      if (config.isScheduleEnabled) scheduleCount++;
      if (config.isShiftBoardEnabled) shiftCount++;
    }

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: 'Total',
            count: '${widget.storeDocs.length}',
            icon: Icons.storefront_rounded,
            color: Colors.white70,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            label: 'Dev Mode',
            count: '$devCount',
            icon: Icons.developer_mode_rounded,
            color: kText,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            label: 'Schedule',
            count: '$scheduleCount',
            icon: Icons.calendar_month_rounded,
            color: kText,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            label: 'Shifts',
            count: '$shiftCount',
            icon: Icons.swap_horiz_rounded,
            color: kText,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final String count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const Spacer(),
              Text(
                count,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.white60, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Store card showing owner, features, and tap to configure.
class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.storeId,
    required this.storeName,
    required this.isDev,
    required this.owners,
    required this.filter,
  });

  final String storeId;
  final String storeName;
  final bool isDev;
  final List<StoreOwner> owners;
  final _StoreFilter filter;

  Future<void> _confirmDeleteCardStore(BuildContext context, String sid, String sName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: kDanger, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Delete "$sName"?', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete store "$sName" ($sid)?\n\n'
          'This will remove all associated team rosters, settings, and portal links from Axis Team. This action cannot be undone.',
          style: const TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await deleteStore(storeId: sid);
      if (context.mounted) {
        showTopToast(
          context,
          'Store "$sName" deleted',
          icon: Icons.delete_outline_rounded,
          color: kDanger,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showTopToast(
          context,
          'Failed to delete store: $e',
          icon: Icons.error_outline_rounded,
          color: kDanger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (filter == _StoreFilter.devOnly && !isDev) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: teamDb
          .collection('stores')
          .doc(storeId)
          .collection('settings')
          .doc('global_config')
          .snapshots(),
      builder: (context, snap) {
        final settings = StoreSettingsData.fromMap(snap.data?.data());

        // Apply tab filter if needed
        if (filter == _StoreFilter.scheduleOn && !settings.isScheduleEnabled) {
          return const SizedBox.shrink();
        }
        if (filter == _StoreFilter.shiftsOn && !settings.isShiftBoardEnabled) {
          return const SizedBox.shrink();
        }

        return Material(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StoreDetailPage(
                    storeId: storeId,
                    storeName: storeName,
                    owners: owners,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDev ? kText.withValues(alpha: 0.35) : kLine,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Store Name + DEV badge + Store ID
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDev
                              ? kText.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isDev ? Icons.developer_mode_rounded : Icons.storefront_rounded,
                          size: 20,
                          color: isDev ? kText : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    storeName,
                                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isDev) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kText.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: kText.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: const Text(
                                      'DEV',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: kText,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'ID: $storeId',
                              style: const TextStyle(fontSize: 11.5, color: Colors.white38, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Store options',
                        onSelected: (val) async {
                          if (val == 'delete') {
                            _confirmDeleteCardStore(context, storeId, storeName);
                          } else if (val == 'takeout') {
                            try {
                              final res = await StoreTakeoutService.exportStoreTakeout(
                                storeId: storeId,
                                storeName: storeName,
                              );
                              if (context.mounted) {
                                final count = res['memberCount'] as int? ?? 0;
                                final path = res['savedPath'] as String? ?? '';
                                showTopToast(
                                  context,
                                  path.isNotEmpty
                                      ? 'Takeout exported: $count members saved to Downloads & copied to clipboard!'
                                      : 'Takeout exported: $count members copied to clipboard!',
                                  icon: Icons.check_circle_rounded,
                                  color: kText,
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showTopToast(
                                  context,
                                  'Takeout failed: $e',
                                  icon: Icons.error_outline_rounded,
                                  color: kDanger,
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'takeout',
                            child: Row(
                              children: [
                                Icon(Icons.file_download_outlined, color: kText, size: 18),
                                SizedBox(width: 8),
                                Text('Takeout Data (CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, color: kDanger, size: 18),
                                SizedBox(width: 8),
                                Text('Delete Store', style: TextStyle(color: kDanger, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: kSurfaceHigh, height: 1),
                  const SizedBox(height: 12),

                  // Owner Row
                  Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 15,
                        color: owners.isNotEmpty ? Colors.white70 : kTextDim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          owners.isNotEmpty
                              ? 'Owner: ${owners.map((o) => o.name).join(", ")}${owners.first.email.isNotEmpty ? " · ${owners.first.email}" : ""}'
                              : 'No owner assigned',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: owners.isNotEmpty ? Colors.white70 : kTextDim,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Feature Status Badges (Always visible in table without clicking)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _FeaturePill(
                        label: 'Dev Mode',
                        enabled: isDev,
                        icon: Icons.developer_mode_rounded,
                        activeColor: kText,
                      ),
                      _FeaturePill(
                        label: 'Schedule',
                        enabled: settings.isScheduleEnabled,
                        icon: Icons.calendar_month_rounded,
                        activeColor: kText,
                      ),
                      _FeaturePill(
                        label: 'Shift Board',
                        enabled: settings.isShiftBoardEnabled,
                        icon: Icons.swap_horiz_rounded,
                        activeColor: kText,
                      ),
                    ],
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

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.label,
    required this.enabled,
    required this.icon,
    required this.activeColor,
  });

  final String label;
  final bool enabled;
  final IconData icon;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? activeColor : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: enabled ? activeColor.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? activeColor.withValues(alpha: 0.45) : Colors.white12,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: ${enabled ? "ON" : "OFF"}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Store Detail & Configuration Page
class StoreDetailPage extends StatefulWidget {
  const StoreDetailPage({
    super.key,
    required this.storeId,
    required this.storeName,
    required this.owners,
  });

  final String storeId;
  final String storeName;
  final List<StoreOwner> owners;

  @override
  State<StoreDetailPage> createState() => _StoreDetailPageState();
}

class _StoreDetailPageState extends State<StoreDetailPage> {
  bool _saving = false;
  bool _exportingTakeout = false;

  Future<void> _runTakeout(String storeName) async {
    setState(() => _exportingTakeout = true);
    try {
      final res = await StoreTakeoutService.exportStoreTakeout(
        storeId: widget.storeId,
        storeName: storeName,
      );
      HapticFeedback.mediumImpact();
      if (mounted) {
        final path = res['savedPath'] as String? ?? '';
        final count = res['memberCount'] as int? ?? 0;
        showTopToast(
          context,
          path.isNotEmpty
              ? 'Exported $count members to $path & copied to clipboard!'
              : 'Exported $count members & copied to clipboard!',
          icon: Icons.check_circle_rounded,
          color: kText,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopToast(
          context,
          'Takeout failed: $e',
          icon: Icons.error_outline_rounded,
          color: kDanger,
        );
      }
    } finally {
      if (mounted) setState(() => _exportingTakeout = false);
    }
  }

  Future<void> _toggleDevMode({
    required bool currentVal,
    required String storeName,
  }) async {
    final newVal = !currentVal;
    final action = newVal ? 'Enable' : 'Disable';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Developer Mode?'),
        content: Text(
          newVal
              ? 'Are you sure you want to enable Developer Mode for "$storeName"?\n\nThis will reveal testing and database reset buttons on Axis Team (such as "Clear All" and "Seed Sample Store Data").'
              : 'Are you sure you want to disable Developer Mode for "$storeName"?\n\nThis will hide all developer testing and reset buttons from Axis Team.',
          style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: newVal ? kText : kDanger,
              foregroundColor: newVal ? kBg : kText,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('$action Dev Mode', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await updateStoreDevMode(
        storeId: widget.storeId,
        isDev: newVal,
      );
      HapticFeedback.heavyImpact();
      if (mounted) {
        showTopToast(
          context,
          'Developer Mode ${newVal ? "enabled" : "disabled"} for $storeName',
          icon: Icons.developer_mode_rounded,
          color: kText,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopToast(
          context,
          'Failed to update Developer Mode: $e',
          icon: Icons.error_outline_rounded,
          color: kDanger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleFeature({
    required String featureTitle,
    required String featureKey,
    required bool currentVal,
    required String storeName,
  }) async {
    final newVal = !currentVal;
    final action = newVal ? 'Enable' : 'Disable';

    // Required confirmation dialog before modifying setting
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action $featureTitle?'),
        content: Text(
          newVal
              ? 'Are you sure you want to enable $featureTitle for "$storeName"?\n\nTeam members and leaders will immediately have access to $featureTitle in Axis Team.'
              : 'Are you sure you want to disable $featureTitle for "$storeName"?\n\nThis will hide the $featureTitle module from all team members and leaders in Axis Team.',
          style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: newVal ? kText : kDanger,
              foregroundColor: newVal ? kBg : kText,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('$action $featureTitle', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await updateStoreFeature(
        storeId: widget.storeId,
        featureKey: featureKey,
        enabled: newVal,
      );
      HapticFeedback.heavyImpact();
      if (mounted) {
        showTopToast(
          context,
          '$featureTitle ${newVal ? "enabled" : "disabled"} for $storeName',
          icon: newVal ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          color: newVal ? kText : kTextDim,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopToast(
          context,
          'Failed to update $featureTitle: $e',
          icon: Icons.error_outline_rounded,
          color: kDanger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showEditOwnerDialog(BuildContext context, StoreOwner owner) async {
    final parts = owner.name.split(' ');
    final initialFirst = parts.isNotEmpty ? parts.first : '';
    final initialLast = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final firstController = TextEditingController(text: initialFirst);
    final lastController = TextEditingController(text: initialLast);
    final emailController = TextEditingController(text: owner.email);
    String? localError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.manage_accounts_rounded, size: 22, color: kText),
                SizedBox(width: 10),
                Text('Edit Owner Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Changes will update this owner account across Axis Team.',
                    style: TextStyle(fontSize: 12.5, color: Colors.white60),
                  ),
                  const SizedBox(height: 16),
                  if (localError != null) ...[
                    Text(
                      localError!,
                      style: const TextStyle(fontSize: 12.5, color: kDanger, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Text('First Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: firstController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: kSurfaceHigh,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Last Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: lastController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: kSurfaceHigh,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Owner Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: kSurfaceHigh,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kText,
                  foregroundColor: kBg,
                ),
                onPressed: () async {
                  final newEmail = emailController.text.trim();
                  final newFirst = firstController.text.trim();
                  final newLast = lastController.text.trim();

                  if (newEmail.isEmpty || !newEmail.contains('@') || !newEmail.contains('.')) {
                    setDialogState(() => localError = 'Please enter a valid email.');
                    return;
                  }
                  if (newFirst.isEmpty) {
                    setDialogState(() => localError = 'Please enter a first name.');
                    return;
                  }

                  Navigator.of(ctx).pop();
                  try {
                    await updateOwnerDetails(
                      ownerUid: owner.uid,
                      storeId: widget.storeId,
                      newEmail: newEmail,
                      newFirstName: newFirst,
                      newLastName: newLast,
                    );
                    if (context.mounted) {
                      showTopToast(
                        context,
                        'Owner updated: $newFirst $newLast ($newEmail)',
                        icon: Icons.check_circle_rounded,
                        color: kText,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showTopToast(
                        context,
                        'Failed to update owner: $e',
                        icon: Icons.error_outline_rounded,
                        color: kDanger,
                      );
                    }
                  }
                },
                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteStore(String storeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: kDanger, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Delete "$storeName"?', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete store "$storeName" (${widget.storeId})?\n\n'
          'This will remove all associated team rosters, settings, and portal links from Axis Team. This action cannot be undone.',
          style: const TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await deleteStore(storeId: widget.storeId);
      if (mounted) {
        Navigator.of(context).pop();
        showTopToast(
          context,
          'Store "$storeName" deleted',
          icon: Icons.delete_outline_rounded,
          color: kDanger,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTopToast(
          context,
          'Failed to delete store: $e',
          icon: Icons.error_outline_rounded,
          color: kDanger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.storeName, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Delete Store',
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
            onPressed: _saving ? null : () => _confirmDeleteStore(widget.storeName),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: teamDb.collection('stores').doc(widget.storeId).snapshots(),
        builder: (context, storeSnap) {
          final storeData = storeSnap.data?.data() ?? const {};
          final currentStoreName = (storeData['name'] as String? ?? widget.storeName).trim();
          final isDev = storeData['is_dev'] == true || storeData['isDev'] == true;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: teamDb
                .collection('stores')
                .doc(widget.storeId)
                .collection('settings')
                .doc('global_config')
                .snapshots(),
            builder: (context, settingsSnap) {
              final settings = StoreSettingsData.fromMap(settingsSnap.data?.data());

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Store Header Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDev ? kText.withValues(alpha: 0.35) : kLine,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDev
                                    ? kText.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isDev ? Icons.developer_mode_rounded : Icons.storefront_rounded,
                                size: 26,
                                color: isDev ? kText : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          currentStoreName,
                                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      if (isDev) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: kText.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: kText.withValues(alpha: 0.8),
                                            ),
                                          ),
                                          child: const Text(
                                            'DEV',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w900,
                                              color: kText,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Text(
                                        widget.storeId,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white38,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: widget.storeId));
                                          showTopToast(context, 'Store ID copied to clipboard');
                                        },
                                        child: const Icon(Icons.copy_rounded, size: 13, color: Colors.white38),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Owner Information Card
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: teamDb.collection('users').snapshots(),
                    builder: (context, usersSnap) {
                      final liveOwners = usersSnap.hasData
                          ? findStoreOwners(widget.storeId, usersSnap.data!.docs)
                          : widget.owners;

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kLine),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_rounded, size: 18, color: Colors.white70),
                                SizedBox(width: 8),
                                Text(
                                  'Store Owner',
                                  style: TextStyle(fontSize: 13, color: Colors.white60, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (liveOwners.isEmpty)
                              const Text(
                                'No owner account linked yet',
                                style: TextStyle(fontSize: 14, color: kTextDim),
                              )
                            else
                              ...liveOwners.map((owner) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: Colors.white10,
                                          child: Text(
                                            owner.name.isNotEmpty ? owner.name[0].toUpperCase() : '?',
                                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                owner.name,
                                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                              ),
                                              if (owner.email.isNotEmpty)
                                                Text(
                                                  owner.email,
                                                  style: const TextStyle(fontSize: 12.5, color: Colors.white60),
                                                ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.white70),
                                          tooltip: 'Edit Owner Details',
                                          onPressed: () => _showEditOwnerDialog(context, owner),
                                        ),
                                      ],
                                    ),
                                  )),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  // Active Members Summary
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: teamDb
                        .collection('stores')
                        .doc(widget.storeId)
                        .collection('users')
                        .snapshots(),
                    builder: (context, teamSnap) {
                      final count = teamSnap.data?.size ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kLine),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.group_outlined, size: 20, color: Colors.white70),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Registered Team Members',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Feature Access Section Title
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Feature Access & Modules',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Enable or disable tools for this store on the Axis Team site. Changes apply immediately.',
                          style: TextStyle(fontSize: 13, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Developer Mode Switch Card
                  _FeatureToggleTile(
                    title: 'Developer Mode',
                    subtitle: 'Enables developer tools on Axis Team ("Clear All", "Seed Sample Store Data") and unlocks testing buttons.',
                    icon: Icons.developer_mode_rounded,
                    activeColor: kText,
                    enabled: isDev,
                    busy: _saving,
                    onChanged: (val) => _toggleDevMode(
                      currentVal: isDev,
                      storeName: currentStoreName,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Schedule Switch Card
                  _FeatureToggleTile(
                    title: 'Schedule Module',
                    subtitle: 'Schedule builder, shift assignments, and published schedules for team members and managers.',
                    icon: Icons.calendar_month_rounded,
                    activeColor: kText,
                    enabled: settings.isScheduleEnabled,
                    busy: _saving,
                    onChanged: (val) => _toggleFeature(
                      featureTitle: 'Schedule',
                      featureKey: 'isScheduleEnabled',
                      currentVal: settings.isScheduleEnabled,
                      storeName: currentStoreName,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Shift Board Switch Card
                  _FeatureToggleTile(
                    title: 'Shift Board & Trading',
                    subtitle: 'Allows team members to post shifts, request covers, and pick up available open shifts.',
                    icon: Icons.swap_horiz_rounded,
                    activeColor: kText,
                    enabled: settings.isShiftBoardEnabled,
                    busy: _saving,
                    onChanged: (val) => _toggleFeature(
                      featureTitle: 'Shift Board',
                      featureKey: 'isShiftBoardEnabled',
                      currentVal: settings.isShiftBoardEnabled,
                      storeName: currentStoreName,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Store Data Takeout Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kText.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.download_rounded, color: kText, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Store Data Takeout',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Export all store configs, rosters, and notes into the exact 19-column CSV format.',
                                    style: TextStyle(fontSize: 12, color: Colors.white54),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: kLine),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _exportingTakeout
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.file_download_outlined, size: 18),
                            label: Text(
                              _exportingTakeout ? 'Generating Takeout…' : 'Export Store Data (CSV)',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onPressed: _exportingTakeout ? null : () => _runTakeout(currentStoreName),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Danger Zone Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kDanger.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 20, color: kDanger),
                            SizedBox(width: 8),
                            Text(
                              'Danger Zone',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kDanger),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Permanently delete this store, its rosters, portal links, and settings from Axis Team.',
                          style: TextStyle(fontSize: 12.5, color: Colors.white60, height: 1.35),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kDanger,
                              side: BorderSide(color: kDanger.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.delete_forever_rounded, size: 18),
                            label: const Text('Delete Store', style: TextStyle(fontWeight: FontWeight.w700)),
                            onPressed: _saving ? null : () => _confirmDeleteStore(currentStoreName),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FeatureToggleTile extends StatelessWidget {
  const _FeatureToggleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeColor,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color activeColor;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : () => onChanged(!enabled),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? activeColor.withValues(alpha: 0.35) : kLine,
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: enabled ? activeColor.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20, color: enabled ? activeColor : Colors.white38),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          enabled ? 'Enabled' : 'Disabled',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: enabled ? activeColor : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: busy ? null : onChanged,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12.5, color: Colors.white60, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen page for creating a new store and setting up its owner account.
class CreateStorePage extends StatefulWidget {
  const CreateStorePage({super.key});

  @override
  State<CreateStorePage> createState() => _CreateStorePageState();
}

class _CreateStorePageState extends State<CreateStorePage> {
  final _storeTitleController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isDev = false;
  bool _isScheduleEnabled = true;
  bool _isShiftBoardEnabled = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _storeTitleController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _generatePassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer('Axis');
    for (int i = 0; i < 6; i++) {
      buffer.write(chars[(rand + i * 19) % chars.length]);
    }
    buffer.write('!');
    setState(() {
      _passwordController.text = buffer.toString();
      _obscurePassword = false;
    });
  }

  Future<void> _submit() async {
    final title = _storeTitleController.text.trim();
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passwordController.text;

    if (title.isEmpty) {
      setState(() => _error = 'Please enter a store name.');
      return;
    }
    if (first.isEmpty) {
      setState(() => _error = "Please enter the owner's first name.");
      return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid owner email.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await createNewStoreWithOwner(
        storeTitle: title,
        ownerFirstName: first,
        ownerLastName: last,
        ownerEmail: email,
        ownerPassword: pass,
        isDev: _isDev,
        isScheduleEnabled: _isScheduleEnabled,
        isShiftBoardEnabled: _isShiftBoardEnabled,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      showTopToast(
        context,
        res.isExistingUser
            ? 'Store "$title" created and linked to owner $email!'
            : 'Store "$title" created with owner $email!',
        icon: Icons.check_circle_rounded,
        color: kText,
      );

      // Open new store detail view
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoreDetailPage(
            storeId: res.storeId,
            storeName: title,
            owners: [
              StoreOwner(
                uid: res.ownerUid,
                name: '$first $last'.trim(),
                email: email,
              ),
            ],
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message ?? 'Authentication error: ${e.code}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Error creating store: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Store', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        elevation: 0,
        backgroundColor: kBg,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kDanger.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: kDanger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Store Title Field
            const Text('Store Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: _storeTitleController,
              decoration: InputDecoration(
                hintText: 'e.g. Atlanta Flagship, Store 104…',
                prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
                filled: true,
                fillColor: kSurfaceHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kText, width: 1)),
              ),
            ),

            const SizedBox(height: 16),

            // Owner Name Fields
            const Text('Owner Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      hintText: 'First Name',
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                      filled: true,
                      fillColor: kSurfaceHigh,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kText, width: 1)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      hintText: 'Last Name',
                      filled: true,
                      fillColor: kSurfaceHigh,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kText, width: 1)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Owner Email Field
            const Text('Owner Email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'owner@example.com',
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                filled: true,
                fillColor: kSurfaceHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kText, width: 1)),
              ),
            ),

            const SizedBox(height: 16),

            // Owner Password Field
            Row(
              children: [
                const Text('Owner Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
                const Spacer(),
                InkWell(
                  onTap: _generatePassword,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Generate Random',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kDanger),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: 'Min 6 characters',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true,
                fillColor: kSurfaceHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kText, width: 1)),
              ),
            ),

            const SizedBox(height: 18),

            // Info box explaining no email confirmation is required
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kSurfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kLine),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: kTextDim),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Owner account is created immediately with Firebase Auth. No email verification code is required.',
                      style: TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Initial Feature Options
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Initial Store Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
                  const SizedBox(height: 8),

                  // Dev Mode switch
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Developer Mode', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Shows "Clear All" & test tools on Axis Team', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                    value: _isDev,
                    onChanged: (val) => setState(() => _isDev = val),
                  ),
                  const Divider(color: kLine, height: 1),

                  // Schedule switch
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Schedule Module', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Enable shift builder and rota views', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                    value: _isScheduleEnabled,
                    onChanged: (val) => setState(() => _isScheduleEnabled = val),
                  ),
                  const Divider(color: kLine, height: 1),

                  // Shift Board switch
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Shift Board & Trading', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Enable open shift pickups and trades', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                    value: _isShiftBoardEnabled,
                    onChanged: (val) => setState(() => _isShiftBoardEnabled = val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kText,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Create Store & Owner Account',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
