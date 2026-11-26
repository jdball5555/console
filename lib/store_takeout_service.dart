import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import 'team_firebase.dart';

class StoreTakeoutService {
  static String _escapeCell(dynamic val) {
    if (val == null) return '';
    final str = val.toString();
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  static String _row(List<dynamic> cells) {
    final padded = List<dynamic>.from(cells);
    while (padded.length < 19) {
      padded.add('');
    }
    return padded.take(19).map(_escapeCell).join(',');
  }

  static String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    DateTime? dt;
    if (dateVal is Timestamp) {
      dt = dateVal.toDate();
    } else if (dateVal is DateTime) {
      dt = dateVal;
    } else if (dateVal is String && dateVal.isNotEmpty) {
      dt = DateTime.tryParse(dateVal);
      if (dt == null) return dateVal;
    }
    if (dt != null) {
      final yr = dt.year % 100;
      final yrStr = yr < 10 ? '0$yr' : '$yr';
      return '${dt.month}/${dt.day}/$yrStr';
    }
    return '';
  }

  /// Exports all store configs, portal links, and roster members to the exact CSV format.
  /// Saves to /sdcard/Download/ on Android and copies to system clipboard.
  static Future<Map<String, dynamic>> exportStoreTakeout({
    required String storeId,
    required String storeName,
  }) async {
    final db = teamDb;

    // 1. Fetch global config
    final configDoc = await db.collection('stores').doc(storeId).collection('settings').doc('global_config').get();
    final globalConfig = configDoc.data() ?? {};

    // 2. Fetch roster needs
    final needsDoc = await db.collection('stores').doc(storeId).collection('settings').doc('roster_needs').get();
    final rosterNeeds = needsDoc.data() ?? {};

    // 3. Fetch portal links
    final portalLinksSnap = await db.collection('stores').doc(storeId).collection('portal_links').get();
    final portalLinks = portalLinksSnap.docs.map((d) => d.data()).toList();

    // 4. Fetch users
    final usersSnap = await db.collection('stores').doc(storeId).collection('users').get();
    final userDocs = usersSnap.docs;

    final List<String> lines = [];

    // Header
    lines.add(
      'First Name / Config,Last Name / Config Name,Prefered Name / Config Data,Designation / Portal Header,Store / Portal Title,Position,Working Time,Avg Shifts per Week,Pay,Title,Additional Tags,Food Handlers Permit Expiration Date,Manager Permit Expiration Date,Start Date,End Date,Promotion Data,Hiring Notes,Review Notes/Onboarding & In-Training Data,General Notes',
    );

    // globalStartDate
    lines.add(_row(['__CONFIG__', 'globalStartDate', '46231']));

    // defaultPosition
    lines.add(_row(['__CONFIG__', 'defaultPosition', 'In Training']));

    // intervals
    const defaultIntervals = [
      {
        "id": "1",
        "reviewName": "30 Day Review",
        "unit": "days",
        "timeValue": 30,
        "daysFromStart": 30,
        "isRecurring": false,
        "notes": "Discuss initial onboarding, store core values, station training progress, and punctuality."
      },
      {
        "id": "2",
        "reviewName": "60 Day Review",
        "unit": "days",
        "timeValue": 60,
        "daysFromStart": 60,
        "isRecurring": false,
        "notes": "Review speed of service, customer connection, core station mastery, and peer feedback."
      },
      {
        "id": "3",
        "reviewName": "90 Day Review",
        "unit": "days",
        "timeValue": 90,
        "daysFromStart": 90,
        "isRecurring": false,
        "notes": "90-day evaluation, pathway compliance, self-assessment, and future growth goals."
      },
      {
        "id": "4",
        "reviewName": "Half-Year Review",
        "unit": "years",
        "timeValue": 0.5,
        "daysFromStart": 182,
        "isRecurring": true,
        "repeatDays": 365,
        "notes": "Mid-year performance check-in, operational efficiency, and potential leadership pathways."
      },
      {
        "id": "5",
        "reviewName": "Yearly Review",
        "unit": "years",
        "timeValue": 1,
        "daysFromStart": 365,
        "isRecurring": true,
        "repeatDays": 365,
        "notes": "Annual comprehensive evaluation, career development path, achievements, and wage review."
      }
    ];
    lines.add(_row(['__CONFIG__', 'intervals', jsonEncode(defaultIntervals)]));

    // reviewTitles
    lines.add(_row(['__CONFIG__', 'reviewTitles', jsonEncode(["Brandon Yost", "David Ball"])]));

    // completedLogs
    lines.add(_row(['__CONFIG__', 'completedLogs', '[]']));

    // stores
    lines.add(_row(['__CONFIG__', 'stores', jsonEncode([storeName])]));

    // positions_v2
    final positions = (globalConfig['positions'] as List?)?.map((e) => e.toString()).toList() ?? ['SVC', 'DT', 'KT'];
    lines.add(_row([
      '__CONFIG__', 'positions_v2', jsonEncode(positions), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // defaultTitle
    lines.add(_row([
      '__CONFIG__', 'defaultTitle', 'Onboarding', '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // workingTimes
    final workingTimes = (globalConfig['workingTimes'] as List?)?.map((e) => e.toString()).toList() ?? ['Daytime', 'Night'];
    lines.add(_row(['__CONFIG__', 'workingTimes', jsonEncode(workingTimes)]));

    // rosterNeeds
    lines.add(_row([
      '__CONFIG__', 'rosterNeeds', jsonEncode(rosterNeeds), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // titles & titleColors
    final rawTitles = (globalConfig['titles'] as List?) ?? [];
    final Map<String, String> titleColors = {};
    final List<String> titleNames = [];
    for (final t in rawTitles) {
      if (t is Map) {
        final tName = t['name']?.toString() ?? '';
        final tColor = t['color']?.toString() ?? '#FF1138';
        if (tName.isNotEmpty) {
          titleNames.add(tName);
          titleColors[tName] = tColor;
        }
      }
    }
    if (titleNames.isEmpty) {
      titleNames.addAll(['Onboarding', 'In Training', 'Team Member', 'Champion', 'Leader', 'Marketing Team', 'Seasonal', 'Director']);
    }
    lines.add(_row([
      '__CONFIG__', 'titleColors', jsonEncode(titleColors), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // title individual rows
    for (final t in rawTitles) {
      if (t is Map) {
        final tName = t['name']?.toString() ?? '';
        if (tName.isNotEmpty) {
          final tMap = {
            "name": tName,
            "color": t['color'] ?? "#FF1138",
            "isLeadership": t['isLeadership'] ?? false,
            "splitInArea": t['splitInArea'] ?? false,
            "separateRoster": t['isolatedRoster'] ?? false,
            "isolationPlacement": "bottom",
            "alsoInStandardRoster": false,
            "needsManagerPermit": t['mgrPermit'] ?? false,
            "linkedChecklists": t['linkedChecklistId'] != null ? [t['linkedChecklistId']] : [],
            "autoPromoteOnComplete": t['autoPromoteOnChecklist'] ?? false,
          };
          lines.add(_row([
            '__CONFIG__', 'title_$tName', jsonEncode(tMap), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
          ]));
        }
      }
    }

    // designations
    final designations = (globalConfig['designations'] as List?)?.map((e) => e.toString()).toList() ?? ['Adult', 'College', 'High School'];
    lines.add(_row(['__CONFIG__', 'designations', jsonEncode(designations)]));

    // portalLink rows
    for (final link in portalLinks) {
      final url = link['url']?.toString() ?? '';
      final group = link['group']?.toString() ?? 'General';
      final title = link['title']?.toString() ?? '';
      final desc = link['description']?.toString() ?? '';
      lines.add(_row([
        '__CONFIG__', 'portalLink', url, group, title, '', '', '', '', '', '', '', '', '', '', '', desc, '', ''
      ]));
    }

    // selectedCharts & chartOrder
    lines.add(_row([
      '__CONFIG__', 'selectedCharts', jsonEncode(["workingTime", "position", "designation", "tenure", "permits", "tenureYears"]), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));
    lines.add(_row([
      '__CONFIG__', 'chartOrder', jsonEncode(["workingTime", "position", "designation", "tenure", "permits"]), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // purge config
    lines.add(_row([
      '__CONFIG__', 'purgeDaysGone', (globalConfig['purgeDaysGone'] ?? 60).toString(), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));
    lines.add(_row([
      '__CONFIG__', 'autoPurgeFormer', (globalConfig['autoPurgeFormer'] ?? false).toString(), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // tags
    final rawTags = (globalConfig['tags'] as List?) ?? [];
    final Map<String, String> tagColors = {};
    for (final tag in rawTags) {
      if (tag is Map) {
        final tagName = tag['name']?.toString() ?? '';
        final tagColor = tag['color']?.toString() ?? '#004F71';
        if (tagName.isNotEmpty) {
          tagColors[tagName] = tagColor;
          final tagMap = {
            "name": tagName,
            "color": tagColor,
            "isLeadership": tag['isLeadership'] ?? false,
            "splitInArea": tag['splitInArea'] ?? false,
            "separateRoster": tag['isolatedRoster'] ?? false,
            "isolationPlacement": "bottom",
            "alsoInStandardRoster": false,
            "needsManagerPermit": tag['mgrPermit'] ?? false,
          };
          lines.add(_row([
            '__CONFIG__', 'tag_$tagName', jsonEncode(tagMap), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
          ]));
        }
      }
    }
    lines.add(_row([
      '__CONFIG__', 'tagColors', jsonEncode(tagColors), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // titles array
    lines.add(_row([
      '__CONFIG__', 'titles', jsonEncode(titleNames), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // rosters
    lines.add(_row([
      '__CONFIG__', 'rosters', jsonEncode([{
        "id": "default",
        "name": "Standard Roster",
        "isDefault": true,
        "needs": rosterNeeds,
        "shifts": {}
      }]), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));
    lines.add(_row([
      '__CONFIG__', 'activeRosterId', 'default', '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
    ]));

    // checklists
    final rawChecklists = (globalConfig['checklists'] as List?) ?? [];
    for (final chk in rawChecklists) {
      if (chk is Map) {
        final chkId = chk['id']?.toString() ?? '';
        if (chkId.isNotEmpty) {
          lines.add(_row([
            '__CONFIG__', 'checklist_$chkId', jsonEncode(chk), '', '', '', '', '', '', '', '', '', 'Config Row', '', '', '', '', '', ''
          ]));
        }
      }
    }

    // Member rows
    int memberCount = 0;
    for (final u in userDocs) {
      final data = u.data();
      final uid = u.id;
      if (uid.startsWith('owner_') || data['role'] == 'owner') continue;

      final first = data['first_name']?.toString() ?? '';
      final last = data['last_name']?.toString() ?? '';
      final pref = data['preferred_name']?.toString() ?? '';
      final desig = data['designation']?.toString() ?? '';
      final store = storeName;
      final pos = data['position']?.toString() ?? '';
      final wtime = data['working_time']?.toString() ?? '';
      final avgShifts = data['avg_shifts']?.toString() ?? '';
      final pay = data['pay_rate'] != null ? '\$${data['pay_rate']}' : '';
      final title = data['title']?.toString() ?? '';

      final tagsList = (data['additional_tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final tagsStr = tagsList.join(', ');

      final foodExp = _formatDate(data['food_handlers_expiration']);
      final mgrExp = _formatDate(data['manager_permit_expiration']);
      final startD = _formatDate(data['start_date']);
      final endD = _formatDate(data['end_date']);

      // Promotion Data
      String promoStr = '';
      final historyLogs = data['history_logs'];
      if (historyLogs is List && historyLogs.isNotEmpty) {
        final promos = historyLogs.where((h) => h is Map && (h['position'] != null || h['event'] == 'Promotion' || (h['text']?.toString().contains('Promoted') ?? false))).toList();
        if (promos.isNotEmpty) {
          promoStr = jsonEncode(promos);
        }
      }

      final hiringNotes = data['hiring_notes']?.toString() ?? '';

      final col17Map = {
        "reviews": data['reviews'] ?? [],
        "isOnboarding": data['is_onboarding'] ?? false,
        "onboardingTasks": data['onboarding_tasks'] ?? {},
        "isInTraining": data['is_in_training'] ?? false,
        "inTrainingTasks": data['in_training_tasks'] ?? {},
        "preferredName": pref,
        "notes": data['notes']?.toString() ?? "",
        "checklists": data['checklists'] ?? {}
      };
      final col17Str = jsonEncode(col17Map);

      final genNotes = data['general_notes']?.toString() ?? '';

      lines.add(_row([
        first, last, pref, desig, store, pos, wtime, avgShifts, pay, title, tagsStr, foodExp, mgrExp, startD, endD, promoStr, hiringNotes, col17Str, genNotes
      ]));
      memberCount++;
    }

    final csvContent = lines.join('\r\n');
    final safeName = storeName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final filename = 'takeout_${safeName}_$dateStr.csv';

    // 1. Copy to clipboard
    await Clipboard.setData(ClipboardData(text: csvContent));

    // 2. Try writing to Downloads directory on device
    String savedPath = '';
    try {
      final downloadDir = Directory('/sdcard/Download');
      if (await downloadDir.exists()) {
        final file = File('/sdcard/Download/$filename');
        await file.writeAsString(csvContent);
        savedPath = file.path;
      }
    } catch (_) {}

    return {
      'filename': filename,
      'memberCount': memberCount,
      'savedPath': savedPath,
      'csvContent': csvContent,
    };
  }
}
