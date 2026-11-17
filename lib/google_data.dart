// Your Google account's Firebase data, read-only: the projects you can see,
// Google Analytics traffic for each, and how its Cloud Functions are doing.
//
// Optic asks Google for read-only access once (Apps → Google account) and
// then calls Google's APIs directly with that access token:
//   Firebase Management  projects, and each project's Analytics property
//   Analytics Data       visitors, page views, top pages
//   Cloud Monitoring     function calls and errors
// Nothing here can change a project.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const kGoogleScopes = [
  'https://www.googleapis.com/auth/firebase.readonly',
  'https://www.googleapis.com/auth/analytics.readonly',
  'https://www.googleapis.com/auth/monitoring.read',
];

class GoogleDataException implements Exception {
  const GoogleDataException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// The connected Google account (one per phone).
class GoogleData extends ChangeNotifier {
  GoogleData._();
  static final instance = GoogleData._();

  bool _started = false;
  GoogleSignInAccount? _account;
  String? _token;
  String? error;

  GoogleSignInAccount? get account => _account;
  bool get connected => _account != null;

  /// Restores a previous connection quietly (no UI).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await GoogleSignIn.instance.initialize();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (_account != null) {
        _token = (await _account!.authorizationClient.authorizationForScopes(kGoogleScopes))?.accessToken;
      }
    } catch (e) {
      debugPrint('Google account not restored: $e');
    }
    notifyListeners();
  }

  /// Picks an account and asks for read-only access.
  Future<void> connect() async {
    error = null;
    try {
      await start();
      final account = await GoogleSignIn.instance.authenticate();
      final authz = await account.authorizationClient.authorizeScopes(kGoogleScopes);
      _account = account;
      _token = authz.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = e.code == GoogleSignInExceptionCode.clientConfigurationError
            ? 'Google sign-in isn\'t set up for Optic yet (see the README).'
            : (e.description ?? e.code.name);
      }
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    _account = null;
    _token = null;
    notifyListeners();
  }

  Future<String> _accessToken({bool fresh = false}) async {
    final account = _account;
    if (account == null) throw const GoogleDataException('Connect your Google account first.');
    if (fresh && _token != null) {
      await account.authorizationClient.clearAuthorizationToken(accessToken: _token!);
      _token = null;
    }
    _token ??= (await account.authorizationClient.authorizationForScopes(kGoogleScopes) ??
            await account.authorizationClient.authorizeScopes(kGoogleScopes))
        .accessToken;
    return _token!;
  }

  Future<Map<String, dynamic>> _send(String method, String url, [Object? body]) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _accessToken(fresh: attempt > 0);
      final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
      final uri = Uri.parse(url);
      final res = await (method == 'POST'
              ? http.post(uri, headers: headers, body: jsonEncode(body))
              : http.get(uri, headers: headers))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 401 && attempt == 0) continue; // expired token
      Map<String, dynamic> json = {};
      try {
        json = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) return json;
      final msg = (json['error'] is Map ? json['error']['message'] : null) as String?;
      throw GoogleDataException(msg ?? 'HTTP ${res.statusCode}', status: res.statusCode);
    }
    throw const GoogleDataException('Google sign-in expired. Connect again.');
  }

  // ---------------------------------------------------------------------------
  // Firebase projects
  // ---------------------------------------------------------------------------

  Future<List<FirebaseProject>> projects() async {
    final out = <FirebaseProject>[];
    String? page;
    do {
      final r = await _send(
        'GET',
        'https://firebase.googleapis.com/v1beta1/projects?pageSize=100${page == null ? '' : '&pageToken=$page'}',
      );
      for (final p in (r['results'] as List? ?? const [])) {
        if (p is Map && p['state'] != 'DELETED') out.add(FirebaseProject(Map<String, dynamic>.from(p)));
      }
      page = r['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// The project's Google Analytics property id, or null if Analytics is off.
  Future<String?> analyticsProperty(String projectId) async {
    try {
      final r = await _send('GET', 'https://firebase.googleapis.com/v1beta1/projects/$projectId/analyticsDetails');
      final id = (r['analyticsProperty'] as Map?)?['id'];
      return id == null ? null : '$id'.replaceFirst('properties/', '');
    } on GoogleDataException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Traffic (Google Analytics)
  // ---------------------------------------------------------------------------

  Future<Traffic> traffic(String propertyId, {int days = 7}) async {
    final url = 'https://analyticsdata.googleapis.com/v1beta/properties/$propertyId:batchRunReports';
    final range = [
      {'startDate': '${days - 1}daysAgo', 'endDate': 'today'},
    ];
    final r = await _send('POST', url, {
      'requests': [
        {
          'dateRanges': range,
          'metrics': [
            {'name': 'activeUsers'},
            {'name': 'newUsers'},
            {'name': 'screenPageViews'},
            {'name': 'sessions'},
          ],
        },
        {
          'dateRanges': range,
          'dimensions': [
            {'name': 'date'},
          ],
          'metrics': [
            {'name': 'screenPageViews'},
            {'name': 'activeUsers'},
          ],
          'orderBys': [
            {
              'dimension': {'dimensionName': 'date'},
            },
          ],
        },
        {
          'dateRanges': range,
          'dimensions': [
            {'name': 'pagePath'},
          ],
          'metrics': [
            {'name': 'screenPageViews'},
            {'name': 'activeUsers'},
          ],
          'orderBys': [
            {
              'metric': {'metricName': 'screenPageViews'},
              'desc': true,
            },
          ],
          'limit': 12,
        },
      ],
    });
    final reports = (r['reports'] as List? ?? const []).cast<Map>();
    List<List<String>> rows(int i) => [
      if (i < reports.length)
        for (final row in (reports[i]['rows'] as List? ?? const []))
          [
            for (final d in ((row as Map)['dimensionValues'] as List? ?? const [])) '${(d as Map)['value']}',
            for (final m in (row['metricValues'] as List? ?? const [])) '${(m as Map)['value']}',
          ],
    ];
    int n(String s) => int.tryParse(s) ?? 0;

    final totals = rows(0).isEmpty ? const ['0', '0', '0', '0'] : rows(0).first;
    final byDay = {for (final r in rows(1)) r[0]: n(r[1])};
    final today = DateTime.now();
    final daily = <DailyViews>[
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          final key = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
          return DailyViews(d, byDay[key] ?? 0);
        }(),
    ];
    return Traffic(
      visitors: n(totals[0]),
      newVisitors: n(totals[1]),
      pageViews: n(totals[2]),
      sessions: n(totals[3]),
      daily: daily,
      pages: [for (final r in rows(2)) PageViews(r[0], n(r[1]), n(r[2]))],
    );
  }

  // ---------------------------------------------------------------------------
  // Cloud Functions (Cloud Monitoring)
  // ---------------------------------------------------------------------------

  /// Function calls and failures over the last [hours].
  Future<FunctionHealth> functionHealth(String projectId, {int hours = 24}) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(Duration(hours: hours));
    Future<Map<String, int>> sumBy(String metric, String label) async {
      final q = {
        'filter': 'metric.type="$metric"',
        'interval.startTime': start.toIso8601String(),
        'interval.endTime': end.toIso8601String(),
        'aggregation.alignmentPeriod': '${hours * 3600}s',
        'aggregation.perSeriesAligner': 'ALIGN_SUM',
        'aggregation.crossSeriesReducer': 'REDUCE_SUM',
        'aggregation.groupByFields': 'metric.label.$label',
      };
      final url = Uri.https('monitoring.googleapis.com', '/v3/projects/$projectId/timeSeries', q).toString();
      final r = await _send('GET', url);
      final out = <String, int>{};
      for (final s in (r['timeSeries'] as List? ?? const [])) {
        final key = '${((s as Map)['metric'] as Map?)?['labels']?[label] ?? ''}';
        var total = 0;
        for (final p in (s['points'] as List? ?? const [])) {
          total += int.tryParse('${((p as Map)['value'] as Map?)?['int64Value'] ?? 0}') ?? 0;
        }
        out[key] = (out[key] ?? 0) + total;
      }
      return out;
    }

    // 1st gen functions report a status; 2nd gen ones run on Cloud Run.
    final v1 = await sumBy('cloudfunctions.googleapis.com/function/execution_count', 'status');
    final v2 = await sumBy('run.googleapis.com/request_count', 'response_code_class');
    final calls = v1.values.fold<int>(0, (a, b) => a + b) + v2.values.fold<int>(0, (a, b) => a + b);
    final failed = v1.entries.where((e) => e.key != 'ok').fold<int>(0, (a, e) => a + e.value) + (v2['5xx'] ?? 0);
    return FunctionHealth(calls: calls, failed: failed, hours: hours);
  }
}

class FirebaseProject {
  FirebaseProject(Map<String, dynamic> m)
    : id = '${m['projectId']}',
      name = '${m['displayName'] ?? m['projectId']}',
      number = '${m['projectNumber'] ?? ''}';
  final String id, name, number;
}

class DailyViews {
  const DailyViews(this.day, this.views);
  final DateTime day;
  final int views;
}

class PageViews {
  const PageViews(this.path, this.views, this.visitors);
  final String path;
  final int views, visitors;
}

class Traffic {
  const Traffic({
    required this.visitors,
    required this.newVisitors,
    required this.pageViews,
    required this.sessions,
    required this.daily,
    required this.pages,
  });
  final int visitors, newVisitors, pageViews, sessions;
  final List<DailyViews> daily;
  final List<PageViews> pages;
}

class FunctionHealth {
  const FunctionHealth({required this.calls, required this.failed, required this.hours});
  final int calls, failed, hours;
}
