// lib/services/firestore_sync_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/batch.dart';
import '../models/student.dart';
import '../models/payment_record.dart';
import 'notification_service.dart';

class FirestoreSyncService {
  FirestoreSyncService._private();
  static final FirestoreSyncService instance = FirestoreSyncService._private();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _studentsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentsSub;

  // ---------- bulk upload local -> firestore (chunked) ----------
  Future<void> syncLocalToFirestore(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    // ensure user doc exists
    await userRef.set({'profile': {'lastSyncedAt': FieldValue.serverTimestamp()}}, SetOptions(merge: true));

    // defensive: boxes must be open in main.dart normally
    if (!Hive.isBoxOpen('batches') || !Hive.isBoxOpen('students') || !Hive.isBoxOpen('payments')) {
      // try open (non-blocking)
      if (!Hive.isBoxOpen('batches')) await Hive.openBox<Batch>('batches');
      if (!Hive.isBoxOpen('students')) await Hive.openBox<Student>('students');
      if (!Hive.isBoxOpen('payments')) await Hive.openBox<PaymentRecord>('payments');
    }

    final batchesBox = Hive.box<Batch>('batches');
    final studentsBox = Hive.box<Student>('students');
    final paymentsBox = Hive.box<PaymentRecord>('payments');

    // collect actions
    final actions = <void Function(WriteBatch)>[];

    for (final Batch b in batchesBox.values) {
      actions.add((WriteBatch batch) {
        final doc = userRef.collection('batches').doc(b.id);
        batch.set(doc, b.toMap(), SetOptions(merge: true));
      });
    }

    for (final Student s in studentsBox.values) {
      actions.add((WriteBatch batch) {
        final doc = userRef.collection('students').doc(s.id);
        batch.set(doc, s.toMap(), SetOptions(merge: true));
      });
    }

    for (final PaymentRecord p in paymentsBox.values) {
      actions.add((WriteBatch batch) {
        final doc = userRef.collection('payments').doc(p.id);
        batch.set(doc, p.toMap(), SetOptions(merge: true));
      });
    }

    // commit in chunks (safe under 500 limit)
    const int chunkSize = 400;
    for (var i = 0; i < actions.length; i += chunkSize) {
      final batch = _db.batch();
      final end = (i + chunkSize < actions.length) ? i + chunkSize : actions.length;
      for (var j = i; j < end; j++) {
        actions[j](batch);
      }
      await batch.commit();
    }

    // mark last synced
    await userRef.set({'profile': {'lastSyncedAt': FieldValue.serverTimestamp()}}, SetOptions(merge: true));

    // Reset backup sync reminder alarm (since sync completed successfully)
    await NotificationService.instance.resetBackupReminder();

    // Register/update device FCM token
    final String? fcmToken = await NotificationService.instance.getDeviceToken();
    if (fcmToken != null) {
      await userRef.set({
        'profile': {
          'fcmToken': fcmToken,
        }
      }, SetOptions(merge: true));
    }
  }

  // ---------- start realtime listeners: firestore -> local Hive ----------
  void startListeners(String uid) {
    stopListeners(); // ensure no duplicate listeners
    final userRef = _db.collection('users').doc(uid);

    // batches listener
    _batchesSub = userRef.collection('batches').snapshots().listen((snap) {
      final box = Hive.box<Batch>('batches');
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;
        try {
          final batchObj = Batch.fromMap(data);
          if (change.type == DocumentChangeType.removed) {
            box.delete(batchObj.id);
          } else {
            // merge policy can be improved — keeping incoming unless you implement timestamp compare
            box.put(batchObj.id, batchObj);
          }
        } catch (_) { /* ignore malformed */ }
      }
    }, onError: (e) {
      // optional logging
    });

    // students listener
    _studentsSub = userRef.collection('students').snapshots().listen((snap) {
      final box = Hive.box<Student>('students');
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;
        try {
          final studentObj = Student.fromMap(data);
          if (change.type == DocumentChangeType.removed) {
            box.delete(studentObj.id);
          } else {
            box.put(studentObj.id, studentObj);
          }
        } catch (_) {}
      }
    });

    // payments listener
    _paymentsSub = userRef.collection('payments').snapshots().listen((snap) {
      final box = Hive.box<PaymentRecord>('payments');
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;
        try {
          final payObj = PaymentRecord.fromMap(data);
          if (change.type == DocumentChangeType.removed) {
            box.delete(payObj.id);
          } else {
            box.put(payObj.id, payObj);
          }
        } catch (_) {}
      }
    });
  }

  // ---------- stop listeners (call on sign-out) ----------
  void stopListeners() {
    _batchesSub?.cancel();
    _studentsSub?.cancel();
    _paymentsSub?.cancel();
    _batchesSub = _studentsSub = _paymentsSub = null;
  }

  // ---------- single-record uploads (call from provider) ----------
  Future<void> uploadBatch(String uid, Batch batch) async {
    final doc = _db.collection('users').doc(uid).collection('batches').doc(batch.id);
    await doc.set(batch.toMap(), SetOptions(merge: true));
  }

  Future<void> uploadStudent(String uid, Student s) async {
    final doc = _db.collection('users').doc(uid).collection('students').doc(s.id);
    await doc.set(s.toMap(), SetOptions(merge: true));
  }

  Future<void> uploadPayment(String uid, PaymentRecord p) async {
    final doc = _db.collection('users').doc(uid).collection('payments').doc(p.id);
    await doc.set(p.toMap(), SetOptions(merge: true));
  }
}
