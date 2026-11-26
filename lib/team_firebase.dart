// Axis Team's Firebase project (project-attendance-app).
//
// Console's own data (tickets, alerts, activity, user admin) is in Axis Optic.
// This second connection is only for Axis Team's Stores tab, which reads and
// writes Axis Team's database directly. Console signs in to it on its own:
// Axis Team's consoleAdmin function (through Axis Optic's consoleService)
// hands out a sign-in token with the claim developer: true, which Axis
// Team's database rules treat as every store. No second login for you.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

/// Console's Android app as registered in Axis Team's project.
const kTeamOptions = FirebaseOptions(
  apiKey: 'AIzaSyAwo82eDOdSE2YPBAPGjRfu28HxUf1KRoE',
  appId: '1:282213766426:android:b75bdac2b6baaf3c4848a3',
  messagingSenderId: '282213766426',
  projectId: 'project-attendance-app',
  storageBucket: 'project-attendance-app.firebasestorage.app',
);

const _kTeamAppName = 'axis-team';

Future<FirebaseApp> initTeamApp() async {
  for (final app in Firebase.apps) {
    if (app.name == _kTeamAppName) return app;
  }
  return Firebase.initializeApp(name: _kTeamAppName, options: kTeamOptions);
}

FirebaseApp get teamApp => Firebase.app(_kTeamAppName);
FirebaseFirestore get teamDb => FirebaseFirestore.instanceFor(app: teamApp);
FirebaseAuth get teamAuth => FirebaseAuth.instanceFor(app: teamApp);

/// Signs Console in to Axis Team (once; Firebase remembers it). Never throws:
/// without it only the Stores tab is affected.
Future<void> connectTeam() async {
  try {
    if (teamAuth.currentUser != null) return;
    final res = await FirebaseFunctions.instance
        .httpsCallable('consoleService')
        .call<Object?>({'service': 'axis_team', 'action': 'signInToken'});
    final token = (res.data as Map?)?['token'] as String?;
    if (token == null) throw Exception('no token');
    await teamAuth.signInWithCustomToken(token);
  } catch (e) {
    debugPrint('Axis Team sign-in failed: $e');
  }
}
