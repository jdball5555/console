// Stores data and models for Optic developer app.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

class StoreOwner {
  const StoreOwner({
    required this.uid,
    required this.name,
    required this.email,
  });

  final String uid;
  final String name;
  final String email;
}

class StoreSettingsData {
  const StoreSettingsData({
    this.isScheduleEnabled = false,
    this.isShiftBoardEnabled = false,
  });

  final bool isScheduleEnabled;
  final bool isShiftBoardEnabled;

  factory StoreSettingsData.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const StoreSettingsData();
    return StoreSettingsData(
      isScheduleEnabled: data['isScheduleEnabled'] as bool? ?? false,
      isShiftBoardEnabled: data['isShiftBoardEnabled'] as bool? ?? false,
    );
  }
}

/// Finds the owner(s) of a store from the global users collection.
List<StoreOwner> findStoreOwners(
  String storeId,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs,
) {
  final owners = <StoreOwner>[];
  for (final doc in userDocs) {
    final d = doc.data();
    final owned = d['owned_stores'];
    final isOwnerRole = (d['role'] as String? ?? '').toLowerCase() == 'owner';
    final hasInOwned = owned is List && owned.contains(storeId);
    final hasAsStoreId = d['storeId'] == storeId && isOwnerRole;

    if (hasInOwned || hasAsStoreId) {
      final name = [d['first_name'], d['last_name']]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      final email = (d['email'] as String? ?? '').trim();
      owners.add(
        StoreOwner(
          uid: doc.id,
          name: name.isEmpty ? (email.isNotEmpty ? email : 'Unnamed Owner') : name,
          email: email,
        ),
      );
    }
  }
  return owners;
}

/// Updates a store feature toggle in Firestore (`stores/{storeId}/settings/global_config`).
Future<void> updateStoreFeature({
  required String storeId,
  required String featureKey,
  required bool enabled,
}) async {
  await FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('settings')
      .doc('global_config')
      .set({
        featureKey: enabled,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

/// Updates store developer mode in Firestore (`stores/{storeId}`).
Future<void> updateStoreDevMode({
  required String storeId,
  required bool isDev,
}) async {
  await FirebaseFirestore.instance.collection('stores').doc(storeId).set({
    'is_dev': isDev,
    'updated_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Updates an owner's details (email, first name, last name) across Firestore.
Future<void> updateOwnerDetails({
  required String ownerUid,
  required String storeId,
  required String newEmail,
  String? newFirstName,
  String? newLastName,
}) async {
  final cleanEmail = newEmail.trim().toLowerCase();
  final cleanFirst = (newFirstName ?? '').trim();
  final cleanLast = (newLastName ?? '').trim();

  // 1. Update in /users/{ownerUid}
  final updates = <String, dynamic>{
    'email': cleanEmail,
    'updated_at': FieldValue.serverTimestamp(),
  };
  if (cleanFirst.isNotEmpty) updates['first_name'] = cleanFirst;
  if (cleanLast.isNotEmpty) updates['last_name'] = cleanLast;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(ownerUid)
      .set(updates, SetOptions(merge: true));

  // 2. Also update in /stores/{storeId}/users/{ownerUid} if it exists
  final storeUserRef = FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('users')
      .doc(ownerUid);
  final storeUserDoc = await storeUserRef.get();
  if (storeUserDoc.exists) {
    await storeUserRef.set({
      'email': cleanEmail,
      if (cleanFirst.isNotEmpty || cleanLast.isNotEmpty)
        'name': '$cleanFirst $cleanLast'.trim(),
      'first_name': cleanFirst,
      'last_name': cleanLast,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Permanently deletes a store, cleans up its subcollections, and removes
/// it from all owner records in Firestore.
Future<void> deleteStore({required String storeId}) async {
  final firestore = FirebaseFirestore.instance;
  final storeDocRef = firestore.collection('stores').doc(storeId);

  // Subcollections to clean up under /stores/{storeId}
  final subcollections = [
    'settings',
    'users',
    'portal_links',
    'shifts',
    'schedules',
    'time_off_requests',
    'active_availability',
    'training_progress',
  ];

  for (final sub in subcollections) {
    try {
      final snap = await storeDocRef.collection(sub).get();
      if (snap.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  // Remove storeId from owned_stores in all users
  try {
    final ownersQuery = await firestore
        .collection('users')
        .where('owned_stores', arrayContains: storeId)
        .get();
    if (ownersQuery.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in ownersQuery.docs) {
        batch.update(doc.reference, {
          'owned_stores': FieldValue.arrayRemove([storeId]),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  } catch (_) {}

  // Delete the main store document
  await storeDocRef.delete();
}


/// Result returned from creating a new store.
class CreateStoreResult {
  const CreateStoreResult({
    required this.storeId,
    required this.ownerUid,
    required this.isExistingUser,
  });

  final String storeId;
  final String ownerUid;
  final bool isExistingUser;
}

/// Creates a new store and configures the owner user account.
///
/// Supports having multiple owner accounts with the same email.
/// Uses an isolated secondary FirebaseApp so the currently signed-in
/// developer session in Optic is never interrupted or signed out.
Future<CreateStoreResult> createNewStoreWithOwner({
  required String storeTitle,
  required String ownerFirstName,
  required String ownerLastName,
  required String ownerEmail,
  required String ownerPassword,
  required bool isDev,
  required bool isScheduleEnabled,
  required bool isShiftBoardEnabled,
  String? customStoreId,
}) async {
  final cleanFirst = ownerFirstName.trim();
  final cleanLast = ownerLastName.trim();
  final cleanEmail = ownerEmail.trim().toLowerCase();
  final cleanTitle = storeTitle.trim();

  String ownerUid = '';
  bool isExistingUser = false;

  // 1. Create or resolve the Auth user using an isolated secondary app
  final secondaryAppName = 'StoreCreator_${DateTime.now().millisecondsSinceEpoch}';
  FirebaseApp? secondaryApp;
  try {
    secondaryApp = await Firebase.initializeApp(
      name: secondaryAppName,
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final creds = await FirebaseAuth.instanceFor(app: secondaryApp)
        .createUserWithEmailAndPassword(
          email: cleanEmail,
          password: ownerPassword,
        );
    ownerUid = creds.user!.uid;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') {
      // 1 account per email: link store to existing owner account
      final existingQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        ownerUid = existingQuery.docs.first.id;
        isExistingUser = true;
      } else {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'An account with this email already exists. Each owner account must have a unique email.',
        );
      }
    } else {
      rethrow;
    }
  } finally {
    if (secondaryApp != null) {
      await secondaryApp.delete();
    }
  }

  // 2. Create the store document in /stores/{storeId}
  final storeRef = customStoreId != null && customStoreId.trim().isNotEmpty
      ? FirebaseFirestore.instance.collection('stores').doc(customStoreId.trim())
      : FirebaseFirestore.instance.collection('stores').doc();
  final storeId = storeRef.id;

  await storeRef.set({
    'name': cleanTitle,
    'is_dev': isDev,
    'created_at': FieldValue.serverTimestamp(),
    'created_by': 'Optic Developer App',
  });

  // 3. Create default global_config settings in /stores/{storeId}/settings/global_config
  int idCounter = 0;
  String uniqueId(String name) =>
      '${DateTime.now().microsecondsSinceEpoch}_${idCounter++}_$name';

  await storeRef.collection('settings').doc('global_config').set({
    'positions': ['SVC', 'DT', 'KT', 'TRAINER', 'DIR', 'SEA'],
    'titles': [
      {'id': uniqueId('In Training'), 'name': 'In Training'},
      {'id': uniqueId('Team Member'), 'name': 'Team Member'},
      {'id': uniqueId('Trainer'), 'name': 'Trainer'},
      {'id': uniqueId('Leader'), 'name': 'Leader'},
      {'id': uniqueId('Director'), 'name': 'Director'},
    ],
    'workingTimes': ['Daytime', 'Night', 'Unassigned'],
    'tags': [
      {'id': uniqueId('Minor'), 'name': 'Minor'},
      {'id': uniqueId('Key Holder'), 'name': 'Key Holder'},
    ],
    'designations': ['Adult', 'College', 'High School'],
    'isScheduleEnabled': isScheduleEnabled,
    'isShiftBoardEnabled': isShiftBoardEnabled,
    'created_at': FieldValue.serverTimestamp(),
  });

  // 4. Update or create global user record in /users/{ownerUid}
  await FirebaseFirestore.instance.collection('users').doc(ownerUid).set({
    'first_name': cleanFirst.isNotEmpty ? cleanFirst : 'Owner',
    'last_name': cleanLast,
    'email': cleanEmail,
    'role': 'owner',
    'owned_stores': FieldValue.arrayUnion([storeId]),
    'created_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // 5. Add owner to the store's users roster subcollection
  await storeRef.collection('users').doc(ownerUid).set({
    'name': '$cleanFirst $cleanLast'.trim(),
    'first_name': cleanFirst,
    'last_name': cleanLast,
    'email': cleanEmail,
    'role': 'owner',
    'title': 'Owner',
    'store': storeId,
    'created_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  return CreateStoreResult(
    storeId: storeId,
    ownerUid: ownerUid,
    isExistingUser: isExistingUser,
  );
}
