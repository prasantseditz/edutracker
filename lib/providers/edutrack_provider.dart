// / lib/providers/edutrack_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:collection/collection.dart';
import 'package:fuzzy/fuzzy.dart' as fuzzy;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore: unused_import
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../models/student.dart';
import '../models/batch.dart';
import '../models/payment_record.dart';
import '../services/ad_manager.dart'; // Import AdManager
import '../services/notification_service.dart';

class EduTrackProvider extends ChangeNotifier {
  late Box<Student> _studentsBox;
  late Box<Batch> _batchesBox;
  late Box<PaymentRecord> _paymentsBox;
  late Box _settingsBox;

  Color _appColor = Colors.deepPurple;
  Color get appColor => _appColor;
  void setAppColor(Color color) {
    _appColor = color;
    notifyListeners();
  }

  // Mode & Currency Support
  String _appMode = 'tutor'; // 'tutor' or 'org'
  String get appMode => _appMode;

  String _currencySymbol = '₹';
  String get currencySymbol => _currencySymbol;

  void setCurrency(String symbol) {
    _currencySymbol = symbol;
    _settingsBox.put('currency_symbol', symbol);
    notifyListeners();
  }

  Future<void> setAppMode(String mode) async {
    if (_appMode == mode) return;

    // Sync before switching to ensure data is up to date on server
    if (_auth.currentUser != null) {
      await syncLocalToFirestore();
    }

    _appMode = mode;
    await _settingsBox.put('app_mode', mode);
    // Reload boxes for the new mode
    await _init();
  }

  Future<void> completeOnboarding(String name, String mode) async {
    await _settingsBox.put('name', name);
    await _settingsBox.put('app_mode', mode);
    await _settingsBox.put('onboarding_complete', true);
    _appMode = mode;
    await _init(); // Re-initialize with the new mode
  }

  // Dynamic Labels
  String get batchLabel => _appMode == 'org' ? 'Class' : 'Batch';
  String get batchLabelPlural => _appMode == 'org' ? 'Classes' : 'Batches';
  String get subLabel => _appMode == 'org' ? 'Section / Dept' : 'Class';

  bool _isLoading = true;
  bool _isInitialized = false;
  bool get isLoading => _isLoading;
  Timer? _autoBackupTimer;
  Duration autoBackupInterval = const Duration(days: 3);

  // Firestore & Auth
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _premiumSub;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  // Method to check premium status (Based on Approved Subscription Requests)
  void _checkPremiumStatus() {
    final user = _auth.currentUser;
    if (user == null) {
      _isPremium = false;
      notifyListeners();
      return;
    }

    _premiumSub?.cancel();
    _premiumSub = _firestore
        .collection('subscription_requests')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      // Check for approved status in Dart to avoid Firestore Index requirement
      final hasApprovedSubscription =
          snapshot.docs.any((doc) => doc.data()['approved'] == true);

      // TODO1: Add 14-Day Trial Logic here later (Current Date < Signup Date + 14)

      if (hasApprovedSubscription != _isPremium) {
        _isPremium = hasApprovedSubscription;

        // Update AdManager
        AdManager.instance.setPremium(_isPremium);

        notifyListeners();
        debugPrint('Premium Status Updated: $_isPremium');
      }
    }, onError: (e) {
      debugPrint('Error listening to premium status: $e');
    });
  }

  // <-- new
  EduTrackProvider() {
    debugPrint('>>> EduTrackProvider constructor called');
    _init();
  }

  Future<void> _init() async {
    debugPrint('>>> EduTrackProvider._init start');
    try {
      await _openBoxesSafely();
      await _ensureBatchNameConsistency();
      _isInitialized = true;

      // Check premium Status
      if (_auth.currentUser != null) {
        _checkPremiumStatus();
      }

      // ===== NEW: migrate existing data to add fees fields =====
      await _migrateExistingData();

      // ===== NEW: reconcile feesPaid flags after boxes are ready =====
      await _reconcileFeesPaidFlags();

      // schedule auto-backup if setting present
      final enabled =
          _settingsBox.get('auto_backup_enabled', defaultValue: false) as bool;
      if (enabled) {
        _scheduleAutoBackup();
      }

      // Load mode and currency
      _appMode = _settingsBox.get('app_mode', defaultValue: 'tutor') as String;
      _currencySymbol =
          _settingsBox.get('currency_symbol', defaultValue: '₹') as String;

      // Start listening to auth changes for Firestore sync
      _authSub = _auth.authStateChanges().listen((user) async {
        if (user != null) {
          debugPrint('>>> user signed in: ${user.uid}');
          // start listening to firestore user batches & payments
          _startFirestoreListener(user.uid);
          _startPaymentsListener(user.uid);
          // try an immediate sync local -> firestore
          await syncLocalToFirestore();
        } else {
          debugPrint('>>> user signed out');
          _stopFirestoreListener();
          _stopPaymentsListener();
        }
      });

      debugPrint('>>> EduTrackProvider._init completed: initialized=true');
    } catch (e, st) {
      if (kDebugMode) {
        print('EduTrackProvider._init error: $e\n$st');
      }
      _isInitialized = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _openBoxesSafely() async {
    if (!Hive.isBoxOpen('settings')) {
      _settingsBox = await Hive.openBox('settings');
      debugPrint('>>> opened settings box');
    } else {
      _settingsBox = Hive.box('settings');
      debugPrint('>>> settings box already open');
    }

    // Determine current mode to decide box names
    _appMode = _settingsBox.get('app_mode', defaultValue: 'tutor') as String;
    final suffix = _appMode == 'org' ? '_org' : '';

    final studentBoxName = 'students$suffix';
    final batchBoxName = 'batches$suffix';
    final paymentBoxName = 'payments$suffix';

    if (!Hive.isBoxOpen(studentBoxName)) {
      _studentsBox = await Hive.openBox<Student>(studentBoxName);
      debugPrint('>>> opened $studentBoxName box');
    } else {
      _studentsBox = Hive.box<Student>(studentBoxName);
      debugPrint('>>> $studentBoxName box already open');
    }

    if (!Hive.isBoxOpen(batchBoxName)) {
      _batchesBox = await Hive.openBox<Batch>(batchBoxName);
      debugPrint('>>> opened $batchBoxName box');
    } else {
      _batchesBox = Hive.box<Batch>(batchBoxName);
      debugPrint('>>> $batchBoxName box already open');
    }

    if (!Hive.isBoxOpen(paymentBoxName)) {
      _paymentsBox = await Hive.openBox<PaymentRecord>(paymentBoxName);
      debugPrint('>>> opened $paymentBoxName box');
    } else {
      _paymentsBox = Hive.box<PaymentRecord>(paymentBoxName);
      debugPrint('>>> $paymentBoxName box already open');
    }
  }

  Future<void> _ensureBatchNameConsistency() async {
    debugPrint('>>> _ensureBatchNameConsistency running');
    final Map<String, String> seenNames = {};
    final List<String> duplicatesToDelete = [];
    for (final b in _batchesBox.values) {
      if (!seenNames.containsKey(b.name)) {
        seenNames[b.name] = b.id;
      } else {
        duplicatesToDelete.add(b.id);
      }
    }
    for (final dupId in duplicatesToDelete) {
      try {
        await _batchesBox.delete(dupId);
        debugPrint('>>> deleted duplicate batch id=$dupId');
      } catch (e) {
        if (kDebugMode) print('Failed to delete duplicate batch $dupId: $e');
      }
    }
  }

  // ---------- Safe getters ----------
  List<Batch> get batches => _isInitialized ? _batchesBox.values.toList() : [];
  List<Student> get students =>
      _isInitialized ? _studentsBox.values.toList() : [];
  List<PaymentRecord> get payments =>
      _isInitialized ? _paymentsBox.values.toList() : [];
  int get totalStudents => _isInitialized ? _studentsBox.length : 0;
  int get feesPaidCount =>
      _isInitialized ? _studentsBox.values.where((s) => s.feesPaid).length : 0;
  int get feesDueCount =>
      _isInitialized ? _studentsBox.values.where((s) => !s.feesPaid).length : 0;
  int get activeBatches =>
      _isInitialized ? _batchesBox.values.where((b) => !b.postponed).length : 0;

  // ---------- Fees Amount Calculations ----------

  /// Get total paid amount for current month
  double getTotalPaidCurrentMonth() {
    if (!_isInitialized) return 0.0;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);

    return _paymentsBox.values
        .where((p) =>
            p.isPaid &&
            p.month.year == currentMonth.year &&
            p.month.month == currentMonth.month)
        .fold(0.0, (total, p) => total + p.amount);
  }

  /// Get total due amount for current month
  double getTotalDueCurrentMonth() {
    if (!_isInitialized) return 0.0;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);

    double totalDue = 0.0;
    for (final s in _studentsBox.values) {
      // 1. Check if eligible by entry date
      final ed = s.entryDate;
      final eligible = ed.year < currentMonth.year ||
          (ed.year == currentMonth.year && ed.month <= currentMonth.month);
      if (!eligible) continue;

      // 2. Find batch to get cycle
      final batch =
          _batchesBox.values.firstWhereOrNull((b) => b.name == s.batchName);

      // Check for postponed batch
      if (batch != null && batch.postponed) continue;

      final cycle = batch?.feesCycle ?? 'monthly';

      // 3. Check if paid for this cycle
      if (!isPaidForCycle(s.id, currentMonth, cycle)) {
        totalDue += s.monthlyFees;
      }
    }
    return totalDue;
  }

  // ---------- Migration for existing data ----------

  Future<void> _migrateExistingData() async {
    if (!_isInitialized) return;

    int migratedCount = 0;

    // First, cache batch defaults
    final batchDefaults = <String, double>{};
    for (final b in _batchesBox.values) {
      if (b.defaultFees > 0) {
        batchDefaults[b.name] = b.defaultFees;
      }
    }

    // Migrate students
    for (final student in _studentsBox.values) {
      if (student.monthlyFees == 0.0) {
        // Try to find default from batch
        final def = batchDefaults[student.batchName];
        if (def != null && def > 0) {
          final updated = student.copyWith(monthlyFees: def);
          await _studentsBox.put(student.id, updated);
          migratedCount++;
        }
      }
    }

    // Migrate batches (just flag them if needed, can't guess default fees)
    for (final batch in _batchesBox.values) {
      if (batch.defaultFees == 0.0) {
        // This is an old batch, keep at 0.0
      }
    }

    if (migratedCount > 0 && kDebugMode) {
      debugPrint(
          '>>> Migrated existing data: Updated $migratedCount students with 0 fees to batch defaults');
    }
  }

  // -----------------------------
  // Firestore listener & sync
  // -----------------------------
  void _startFirestoreListener(String uid) {
    _batchesSub?.cancel();
    final userBatchesColl =
        _firestore.collection('users').doc(uid).collection('batches');
    _batchesSub = userBatchesColl.snapshots().listen((snapshot) async {
      debugPrint(
          '>>> firestore snapshot received: ${snapshot.docChanges.length} changes');
      // Process changes incrementally to reduce duplicate work
      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data() ?? {};
        try {
          if (change.type == DocumentChangeType.removed) {
            // Remote batch removed -> cascade-delete local students & payments
            final localBatch = _batchesBox.get(doc.id);
            if (localBatch != null) {
              await _cascadeDeleteLocalBatch(localBatch);
              debugPrint(
                  '>>> firestore removed -> cascade deleted local batch ${doc.id}');
            }
          } else {
            // added or modified
            data['id'] = data['id'] ?? doc.id;

            // Check for pending deletion
            final pendingDeletions = _settingsBox
                .get('pending_deletions', defaultValue: <dynamic>[]) as List;
            final List<String> strPending =
                pendingDeletions.map((e) => e.toString()).toList();
            if (strPending.contains(data['id'])) {
              debugPrint(
                  '>>> firestore listener: skipping zombie batch ${data['id']} (pending delete)');
              // Retry delete since it reappeared
              doc.reference.delete().catchError((_) {});
              continue;
            }

            final remoteBatch = Batch.fromMap(Map<String, dynamic>.from(data));

            // DEFENSIVE SYNC: Prevent wiping local data if server has empty student list
            // This happens if write failed previously but document exists
            final localBatch = _batchesBox.get(remoteBatch.id);
            if (remoteBatch.students.isEmpty &&
                localBatch != null &&
                localBatch.students.isNotEmpty) {
              debugPrint(
                  '>>> firestore listener: DETECTED POTENTIAL DATA LOSS. Remote batch ${remoteBatch.id} has 0 students, Local has ${localBatch.students.length}. PRESERVING LOCAL.');

              // Keep local students, update only metadata
              final mergedBatch =
                  remoteBatch.copyWith(students: localBatch.students);
              await _batchesBox.put(mergedBatch.id, mergedBatch);

              // Trigger upstream sync to fix server
              // We put a slight delay to allow current processing to finish
              Future.delayed(const Duration(seconds: 2), syncLocalToFirestore);
            } else {
              // Normal: Trust server
              await _batchesBox.put(remoteBatch.id, remoteBatch);
              debugPrint(
                  '>>> firestore upsert -> saved batch ${remoteBatch.id}');
            }

            // store students locally (replace existing entries for these students)
            for (final s in remoteBatch.students) {
              var studentToSave = s;
              if (_studentsBox.containsKey(s.id)) {
                final localS = _studentsBox.get(s.id);
                if (localS != null) {
                  // Defensive merge: monthlyFees
                  if (studentToSave.monthlyFees == 0.0 &&
                      localS.monthlyFees > 0.0) {
                    studentToSave =
                        studentToSave.copyWith(monthlyFees: localS.monthlyFees);
                    debugPrint(
                        '>>> firestore listener: preserved local fees ${localS.monthlyFees} for student ${s.id}');
                  }

                  // Defensive merge: paymentHistory amounts
                  final mergedHistory =
                      List<PaymentRecord>.from(studentToSave.paymentHistory);
                  bool historyChanged = false;
                  for (int i = 0; i < mergedHistory.length; i++) {
                    final remoteP = mergedHistory[i];
                    if (remoteP.amount == 0.0) {
                      final localP = localS.paymentHistory
                          .firstWhereOrNull((p) => p.id == remoteP.id);
                      if (localP != null && localP.amount > 0.0) {
                        mergedHistory[i] =
                            remoteP.copyWith(amount: localP.amount);
                        historyChanged = true;
                      }
                    }
                  }
                  if (historyChanged) {
                    studentToSave =
                        studentToSave.copyWith(paymentHistory: mergedHistory);
                  }
                }
              }
              await _studentsBox.put(studentToSave.id, studentToSave);
            }
          }
        } catch (e) {
          debugPrint('Error processing change for doc ${doc.id}: $e');
        }
      }

      // after processing remote snapshot, recalculate feesPaid flags
      try {
        await _reconcileFeesPaidFlags();
      } catch (e) {
        debugPrint('Error reconciling fees after firestore snapshot: $e');
      }

      notifyListeners();
    }, onError: (err) {
      debugPrint('Firestore listener error: $err');
    });
  }

  void _stopFirestoreListener() {
    _batchesSub?.cancel();
    _batchesSub = null;
  }

  /// Start listening payments collection from Firestore for signed-in user.
  void _startPaymentsListener(String uid) {
    _paymentsSub?.cancel();
    final paymentsColl =
        _firestore.collection('users').doc(uid).collection('payments');
    _paymentsSub = paymentsColl.snapshots().listen((snapshot) async {
      debugPrint(
          '>>> payments snapshot: ${snapshot.docChanges.length} changes');
      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data() ?? {};
        try {
          if (change.type == DocumentChangeType.removed) {
            // delete local payment
            if (_paymentsBox.containsKey(doc.id)) {
              await _paymentsBox.delete(doc.id);
              debugPrint(
                  '>>> payments listener: deleted local payment ${doc.id}');
            }
            // Also remove from student.history if present
            for (final s in _studentsBox.values) {
              final idx = s.paymentHistory.indexWhere((p) => p.id == doc.id);
              if (idx != -1) {
                s.paymentHistory.removeAt(idx);
                await _studentsBox.put(s.id, s);
                debugPrint(
                    '>>> payments listener: removed payment ${doc.id} from student ${s.id}');
              }
            }
          } else {
            // added or modified
            final Map<String, dynamic> m = Map<String, dynamic>.from(data);
            m['id'] = m['id'] ?? doc.id;
            // coerce Firestore Timestamp -> int/string -> PaymentRecord.fromMap handles variants,
            // but we make sure timestamps are converted to epoch ms for consistency
            if (m['month'] is Timestamp) {
              m['month'] = (m['month'] as Timestamp).millisecondsSinceEpoch;
            }
            if (m['paymentDate'] is Timestamp) {
              m['paymentDate'] =
                  (m['paymentDate'] as Timestamp).millisecondsSinceEpoch;
            }
            if (m['createdAt'] is Timestamp) {
              m['createdAt'] =
                  (m['createdAt'] as Timestamp).millisecondsSinceEpoch;
            }
            if (m['updatedAt'] is Timestamp) {
              m['updatedAt'] =
                  (m['updatedAt'] as Timestamp).millisecondsSinceEpoch;
            }

            var pr = PaymentRecord.fromMap(m);

            // Defensive: if remote amount is 0 but we have a local record with amount, keep local amount
            if (pr.amount == 0.0 && _paymentsBox.containsKey(pr.id)) {
              final localPr = _paymentsBox.get(pr.id);
              if (localPr != null && localPr.amount > 0.0) {
                pr = pr.copyWith(amount: localPr.amount);
                debugPrint(
                    '>>> payments listener: preserved local amount ${pr.amount} for ${pr.id}');
              }
            }

            // save to local payments box
            await _paymentsBox.put(pr.id, pr);
            debugPrint(
                '>>> payments listener: saved/updated local payment ${pr.id}');

            // also ensure student's paymentHistory contains/updates this record
            final student = _studentsBox.get(pr.studentId);
            if (student != null) {
              final idx = student.paymentHistory.indexWhere((p) =>
                  p.id == pr.id ||
                  (p.month.year == pr.month.year &&
                      p.month.month == pr.month.month));
              if (idx != -1) {
                student.paymentHistory[idx] = pr;
              } else {
                student.paymentHistory.add(pr);
              }

              // sort history: latest paymentDate first (nulls last)
              student.paymentHistory.sort((a, b) {
                if (a.paymentDate == null && b.paymentDate == null) return 0;
                if (a.paymentDate == null) return 1;
                if (b.paymentDate == null) return -1;
                return b.paymentDate!.compareTo(a.paymentDate!);
              });

              // update feesPaid flag for current month
              final now = DateTime.now();
              final currentMonth = DateTime(now.year, now.month);
              final paidForCurrent = student.paymentHistory.any((p) =>
                  p.month.year == currentMonth.year &&
                  p.month.month == currentMonth.month &&
                  p.isPaid == true);
              student.feesPaid = paidForCurrent;
              await _studentsBox.put(student.id, student);
              debugPrint(
                  '>>> payments listener: updated student ${student.id} history & feesPaid=$paidForCurrent');
            }
          }
        } catch (e) {
          debugPrint(
              '>>> payments listener processing error for doc ${doc.id}: $e');
        }
      }

      // after processing payments snapshot, reconcile flags (defensive)
      try {
        await _reconcileFeesPaidFlags();
      } catch (e) {
        debugPrint('Error reconciling fees after payments snapshot: $e');
      }

      notifyListeners();
    }, onError: (err) {
      debugPrint('Payments listener error: $err');
    });
  }

  void _stopPaymentsListener() {
    _paymentsSub?.cancel();
    _paymentsSub = null;
  }

  /// Upload local data to Firestore for the signed-in user.
  /// Strategy: for each local batch, set doc in users/{uid}/batches/{id} with batch.toMap()
  Future<void> syncLocalToFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final userColl =
        _firestore.collection('users').doc(user.uid).collection('batches');
    for (final Batch local in _batchesBox.values) {
      try {
        final docRef = userColl.doc(local.id);
        // Push complete batch including nested students
        await docRef
            .set(local.toMap()..['lastUpdated'] = FieldValue.serverTimestamp());
        debugPrint('syncLocalToFirestore: uploaded batch ${local.id}');
      } catch (e) {
        debugPrint('syncLocalToFirestore error for ${local.id}: $e');
      }
    }

    // Also sync payments to users/{uid}/payments
    try {
      final paymentsColl =
          _firestore.collection('users').doc(user.uid).collection('payments');
      for (final PaymentRecord p in _paymentsBox.values) {
        try {
          final m = p.toMap();
          // if you want Firestore server timestamps for created/updated: m['lastUpdated'] = FieldValue.serverTimestamp();
          // convert epoch ms ints to Timestamp? Firestore SDK will accept ints too.
          await paymentsColl.doc(p.id).set(m);
        } catch (e) {
          debugPrint('syncLocalToFirestore payment error for ${p.id}: $e');
        }
      }
    } catch (e) {
      if (e is FirebaseException) {
        debugPrint(
            'CRITICAL: syncLocalToFirestore payments failed. Code: ${e.code}, Msg: ${e.message}');
      } else {
        debugPrint('syncLocalToFirestore payments error: $e');
      }
    }

    // Reset backup sync reminder alarm (since sync completed successfully)
    await NotificationService.instance.resetBackupReminder();

    // Register/update device FCM token
    final String? fcmToken = await NotificationService.instance.getDeviceToken();
    if (fcmToken != null) {
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'profile': {
            'fcmToken': fcmToken,
          }
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Failed to upload FCM token in provider sync: $e');
      }
    }
  }

  // ---------- Batch / Student CRUD (defensive) ----------
  Future<void> addBatch(Batch batch) async {
    if (!_isInitialized) return;
    final existing =
        _batchesBox.values.firstWhereOrNull((b) => b.name == batch.name);
    if (existing != null) {
      final updated = Batch(
          id: existing.id,
          name: batch.name,
          studentClass: batch.studentClass,
          students: existing.students);
      await _batchesBox.put(existing.id, updated);
      debugPrint('>>> addBatch -> updated existing batch ${existing.id}');
    } else {
      await _batchesBox.put(batch.id, batch);
      debugPrint('>>> addBatch -> created batch ${batch.id}');
    }

    // Try upload to Firestore if signed in
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .doc(batch.id)
            .set(batch.toMap()..['lastUpdated'] = FieldValue.serverTimestamp());
      } catch (e) {
        debugPrint('addBatch firestore error: $e');
      }
    }
    notifyListeners();
  }

  Future<void> createBatchWithStudents(
      Batch batch, List<Student> studentsList) async {
    if (!_isInitialized) return;
    final existing =
        _batchesBox.values.firstWhereOrNull((b) => b.name == batch.name);
    final targetBatchId = existing?.id ?? batch.id;

    // create Batch with students passed in (ensure student objects are linked)
    final batchToSave = Batch(
        id: targetBatchId,
        name: batch.name,
        studentClass: batch.studentClass,
        defaultFees: batch.defaultFees, // Preserve default fees!
        students: studentsList);
    await _batchesBox.put(targetBatchId, batchToSave);
    debugPrint(
        '>>> createBatchWithStudents -> batch saved $targetBatchId with ${studentsList.length} students');

    for (final s in studentsList) {
      final existingStudent = _studentsBox.values.firstWhereOrNull(
          (es) => es.name == s.name && es.batchName == batch.name);
      if (existingStudent != null) {
        final updatedStudent = Student(
          id: existingStudent.id,
          name: s.name,
          batchName: batch.name,
          studentClass: s.studentClass,
          phoneNumber: s.phoneNumber,
          notes: s.notes,
          feesPaid: s.feesPaid,
          entryDate: s.entryDate,
          paymentHistory: s.paymentHistory,
        );
        await _studentsBox.put(existingStudent.id, updatedStudent);
        debugPrint(
            '>>> createBatchWithStudents -> updated student ${existingStudent.id}');
      } else {
        final studentToSave = Student(
          id: s.id,
          name: s.name,
          batchName: batch.name,
          studentClass: s.studentClass,
          phoneNumber: s.phoneNumber,
          notes: s.notes,
          entryDate: s.entryDate,
          feesPaid: s.feesPaid,
          paymentHistory: s.paymentHistory,
        );
        await _studentsBox.put(studentToSave.id, studentToSave);
        debugPrint(
            '>>> createBatchWithStudents -> added student ${studentToSave.id}');
      }
    }

    // Upload to Firestore if user signed in
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .doc(batchToSave.id)
            .set(batchToSave.toMap()
              ..['lastUpdated'] = FieldValue.serverTimestamp());
        // also ensure nested students are uploaded as separate student docs (optional)
        final studentsColl =
            _firestore.collection('users').doc(user.uid).collection('students');
        for (final s in studentsList) {
          try {
            await studentsColl
                .doc(s.id)
                .set(s.toMap()..['lastUpdated'] = FieldValue.serverTimestamp());
          } catch (e) {
            debugPrint(
                'createBatchWithStudents -> student upload error ${s.id}: $e');
          }
        }
        debugPrint(
            '>>> createBatchWithStudents -> uploaded to firestore ${batchToSave.id}');
      } catch (e) {
        debugPrint('>>> createBatchWithStudents firestore error: $e');
      }
    }
    notifyListeners();
  }

  Future<void> addStudent(Student student) async {
    if (!_isInitialized) return;
    final batchName = student.batchName;

    // Check if fees is 0, if so try to use batch default
    double finalFees = student.monthlyFees;
    final existingBatch =
        _batchesBox.values.firstWhereOrNull((b) => b.name == batchName);

    if (finalFees == 0.0 &&
        existingBatch != null &&
        existingBatch.defaultFees > 0) {
      finalFees = existingBatch.defaultFees;
      debugPrint(
          '>>> addStudent -> Auto-assigned batch default fees: $finalFees');
    }

    final studentToSave = student.copyWith(monthlyFees: finalFees);

    if (existingBatch == null) {
      final newBatchId = DateTime.now().millisecondsSinceEpoch.toString();
      final newBatch = Batch(
          id: newBatchId,
          name: batchName,
          studentClass: studentToSave.studentClass,
          defaultFees: studentToSave.monthlyFees);
      await _batchesBox.put(newBatchId, newBatch);
      debugPrint(
          '>>> addStudent -> created batch $newBatchId for ${studentToSave.name}');
    }

    await _studentsBox.put(studentToSave.id, studentToSave);
    debugPrint(
        '>>> addStudent -> saved student ${studentToSave.id} with fees $finalFees');

    // Handle Sibling Back-linking
    if (studentToSave.siblingId != null) {
      final sibling = _studentsBox.get(studentToSave.siblingId);
      if (sibling != null) {
        sibling.siblingId = studentToSave.id;
        await _studentsBox.put(sibling.id, sibling);
        // Sync sibling back-link to Firestore
        final user = _auth.currentUser;
        if (user != null) {
          try {
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('students')
                .doc(sibling.id)
                .set(sibling.toMap()
                  ..['lastUpdated'] = FieldValue.serverTimestamp());
          } catch (_) {}
        }
      }
    }

    // update the batch's students list locally
    final batch =
        _batchesBox.values.firstWhereOrNull((b) => b.name == batchName);
    if (batch != null) {
      final updatedStudents = List<Student>.from(batch.students)
        ..insert(0, studentToSave);
      final updatedBatch = batch.copyWith(
          students: updatedStudents, lastUpdated: DateTime.now());
      await _batchesBox.put(updatedBatch.id, updatedBatch);
    }

    // try upload to Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final batchDocRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .doc(batch?.id ?? studentToSave.batchName);
        // ensure batch is present on server (if batch.id is not valid, create server doc with new id)
        final serverBatch = batch ??
            Batch(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: batchName,
              studentClass: studentToSave.studentClass,
              students: [studentToSave],
            );
        await batchDocRef.set(serverBatch.toMap()
          ..['lastUpdated'] = FieldValue.serverTimestamp());
        // create/update separate student doc as well (optional)
        final studentsColl =
            _firestore.collection('users').doc(user.uid).collection('students');
        await studentsColl.doc(studentToSave.id).set(studentToSave.toMap()
          ..['lastUpdated'] = FieldValue.serverTimestamp());
        debugPrint('addStudent -> uploaded batch/student to firestore');
      } catch (e) {
        if (e is FirebaseException) {
          debugPrint(
              'CRITICAL: addStudent firestore error. Code: ${e.code}, Msg: ${e.message}');
        } else {
          debugPrint('addStudent firestore error: $e');
        }
      }
    } else {
      debugPrint('CRITICAL: addStudent called but User is NULL. Cannot sync.');
    }
    notifyListeners();
  }

  Future<void> updateStudent(Student updatedStudent) async {
    if (!_isInitialized) return;

    // Check if fees changed and update current month's payment record if needed
    final oldStudent = _studentsBox.get(updatedStudent.id);

    // Handle Sibling Linkage Update
    await _updateSiblingLinkage(updatedStudent, oldStudent);

    if (oldStudent != null &&
        oldStudent.monthlyFees != updatedStudent.monthlyFees) {
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);

      // Check for current month's payment record in _paymentsBox directly
      final existingPayment = _paymentsBox.values.firstWhereOrNull((p) =>
          p.studentId == updatedStudent.id &&
          p.month.year == currentMonth.year &&
          p.month.month == currentMonth.month);

      if (existingPayment != null) {
        // Update the record
        final newRecord =
            existingPayment.copyWith(amount: updatedStudent.monthlyFees);
        await _paymentsBox.put(newRecord.id, newRecord);

        // Also update in student history if present
        final historyIndex = updatedStudent.paymentHistory
            .indexWhere((p) => p.id == newRecord.id);
        if (historyIndex != -1) {
          updatedStudent.paymentHistory[historyIndex] = newRecord;
        } else {
          updatedStudent.paymentHistory.add(newRecord);
        }

        // Sync payment update to Firestore
        final user = _auth.currentUser;
        if (user != null) {
          try {
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('payments')
                .doc(newRecord.id)
                .set(newRecord.toMap()
                  ..['lastUpdated'] = FieldValue.serverTimestamp());
          } catch (e) {
            debugPrint('updateStudent payment sync error: $e');
          }
        }
      }
    }

    await _studentsBox.put(updatedStudent.id, updatedStudent);
    debugPrint('>>> updateStudent -> updated ${updatedStudent.id}');

    // FIX: Update local batch as well to keep sync consistent
    final batchName = updatedStudent.batchName;
    final batch =
        _batchesBox.values.firstWhereOrNull((b) => b.name == batchName);
    if (batch != null) {
      final updatedStudentsList = List<Student>.from(batch.students);
      final idx =
          updatedStudentsList.indexWhere((s) => s.id == updatedStudent.id);
      if (idx != -1) {
        updatedStudentsList[idx] = updatedStudent;
        // Create new batch object
        final updatedBatch = batch.copyWith(
            students: updatedStudentsList, lastUpdated: DateTime.now());
        await _batchesBox.put(updatedBatch.id, updatedBatch);
        debugPrint('>>> updateStudent -> synched to local batch ${batch.id}');
      }
    }

    // push update to Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        // update the parent batch document too (students array inside batch doc)
        final batchQuery = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .where('name', isEqualTo: updatedStudent.batchName)
            .limit(1)
            .get();
        if (batchQuery.docs.isNotEmpty) {
          final docRef = batchQuery.docs.first.reference;
          final docData = batchQuery.docs.first.data();
          final List<dynamic> studentsList =
              (docData['students'] as List<dynamic>?) ?? [];
          final idx = studentsList.indexWhere(
              (el) => (el is Map && (el['id'] == updatedStudent.id)));
          if (idx != -1) {
            studentsList[idx] = updatedStudent.toMap();
          } else {
            studentsList.insert(0, updatedStudent.toMap());
          }
          await docRef.set({
            'students': studentsList,
            'lastUpdated': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));
        }

        // update separate student doc
        final studentsColl =
            _firestore.collection('users').doc(user.uid).collection('students');
        await studentsColl.doc(updatedStudent.id).set(updatedStudent.toMap()
          ..['lastUpdated'] = FieldValue.serverTimestamp());
      } catch (e) {
        debugPrint('updateStudent firestore error: $e');
      }
    }
    notifyListeners();
  }

  Future<void> deleteStudent(String studentId) async {
    if (!_isInitialized) return;
    final student = _studentsBox.get(studentId);
    if (student == null) return;

    // Delete local payments for this student
    final paymentsToDelete =
        _paymentsBox.values.where((p) => p.studentId == studentId).toList();
    for (final payment in paymentsToDelete) {
      await _paymentsBox.delete(payment.id);
      debugPrint('>>> deleteStudent -> deleted local payment ${payment.id}');
    }

    // Delete local student
    await _studentsBox.delete(studentId);
    debugPrint('>>> deleteStudent -> deleted local student $studentId');

    // Clear Sibling linkage
    final siblingId = student.siblingId;
    if (siblingId != null) {
      final sibling = _studentsBox.get(siblingId);
      if (sibling != null) {
        sibling.siblingId = null;
        await _studentsBox.put(sibling.id, sibling);
        // Sync sibling update to Firestore
        final user = _auth.currentUser;
        if (user != null) {
          try {
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('students')
                .doc(sibling.id)
                .set(sibling.toMap()
                  ..['lastUpdated'] = FieldValue.serverTimestamp());
          } catch (_) {}
        }
      }
    }

    // Firestore: delete payments docs under users/{uid}/payments where studentId == studentId
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final paymentsColl =
            _firestore.collection('users').doc(user.uid).collection('payments');
        final paySnap =
            await paymentsColl.where('studentId', isEqualTo: studentId).get();
        for (final d in paySnap.docs) {
          try {
            await d.reference.delete();
            debugPrint(
                '>>> deleteStudent -> deleted firestore payment ${d.id}');
          } catch (e) {
            debugPrint(
                '>>> deleteStudent -> failed deleting firestore payment ${d.id}: $e');
          }
        }

        // Delete separate student doc if exists
        final studentsColl =
            _firestore.collection('users').doc(user.uid).collection('students');
        final stuDoc = studentsColl.doc(studentId);
        final stuSnap = await stuDoc.get();
        if (stuSnap.exists) {
          await stuDoc.delete();
          debugPrint(
              '>>> deleteStudent -> deleted firestore student doc $studentId');
        }

        // Remove student from its batch doc's students array
        final batchQuery = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .where('name', isEqualTo: student.batchName)
            .limit(1)
            .get();
        if (batchQuery.docs.isNotEmpty) {
          final docRef = batchQuery.docs.first.reference;
          final docData = batchQuery.docs.first.data();
          final List<dynamic> studentsList =
              (docData['students'] as List<dynamic>?) ?? [];
          studentsList
              .removeWhere((el) => (el is Map && el['id'] == studentId));
          await docRef.set({
            'students': studentsList,
            'lastUpdated': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('deleteStudent firestore error: $e');
      }
    }
    notifyListeners();
  }

  int _getCycleMonths(String cycle) {
    switch (cycle) {
      case 'bi_monthly':
        return 2;
      case 'quarterly':
        return 3; // User specified 4 months for quarterly
      case 'half_yearly':
        return 6;
      default:
        return 1;
    }
  }

  Future<void> _internalSetPaymentStatus(
      String studentId, DateTime month, bool isPaid) async {
    final targetMonth = DateTime(month.year, month.month);
    final student = _studentsBox.get(studentId);
    if (student == null) return;

    PaymentRecord? pRecord = _paymentsBox.values.firstWhereOrNull(
      (p) =>
          p.studentId == studentId &&
          p.month.month == targetMonth.month &&
          p.month.year == targetMonth.year,
    );

    PaymentRecord recordToSave;
    if (pRecord != null) {
      if (pRecord.isPaid == isPaid) return; // Already in desired state
      pRecord.isPaid = isPaid;
      pRecord.paymentDate = isPaid ? DateTime.now() : null;
      recordToSave = pRecord;
    } else {
      recordToSave = PaymentRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString() +
            (targetMonth.month + targetMonth.year * 12).toString(),
        studentId: studentId,
        month: targetMonth,
        isPaid: isPaid,
        paymentDate: isPaid ? DateTime.now() : null,
        amount: student.monthlyFees,
      );
    }

    await _paymentsBox.put(recordToSave.id, recordToSave);

    // Update student history
    int histIdx = student.paymentHistory.indexWhere(
      (ph) =>
          ph.month.month == targetMonth.month &&
          ph.month.year == targetMonth.year,
    );
    if (histIdx != -1) {
      student.paymentHistory[histIdx] = recordToSave;
    } else {
      student.paymentHistory.add(recordToSave);
    }

    // Update feesPaid for current month if applicable
    final now = DateTime.now();
    if (targetMonth.year == now.year && targetMonth.month == now.month) {
      student.feesPaid = isPaid;
    }

    await _studentsBox.put(student.id, student);

    // Sync to Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('payments')
            .doc(recordToSave.id)
            .set(recordToSave.toMap()
              ..['lastUpdated'] = FieldValue.serverTimestamp());
      } catch (e) {
        debugPrint('Firestore sync error in _internalSetPaymentStatus: $e');
      }
    }
  }

  Future<void> togglePaymentStatusForMonth(
      String studentId, DateTime month) async {
    if (!_isInitialized) return;
    final student = _studentsBox.get(studentId);
    if (student == null) return;

    final batch = _batchesBox.values.firstWhereOrNull(
      (b) => b.name == student.batchName,
    );
    final cycle = batch?.feesCycle ?? 'monthly';
    final monthsInCycle = _getCycleMonths(cycle);

    // Determine current global status for the target month
    PaymentRecord? existingRecord = _paymentsBox.values.firstWhereOrNull(
      (p) =>
          p.studentId == studentId &&
          p.month.month == month.month &&
          p.month.year == month.year,
    );

    bool shouldBePaid = existingRecord == null || !existingRecord.isPaid;

    final startOfBlock = getCycleStart(month, cycle);

    for (int i = 0; i < monthsInCycle; i++) {
      final currentCycleMonth =
          DateTime(startOfBlock.year, startOfBlock.month + i);
      await _internalSetPaymentStatus(
          studentId, currentCycleMonth, shouldBePaid);
    }

    // Refresh student to ensure history is sorted
    final s = _studentsBox.get(studentId);
    if (s != null) {
      s.paymentHistory.sort((a, b) {
        if (a.paymentDate == null && b.paymentDate == null) return 0;
        if (a.paymentDate == null) return 1;
        if (b.paymentDate == null) return -1;
        return b.paymentDate!.compareTo(a.paymentDate!);
      });
      await _studentsBox.put(s.id, s);
    }

    notifyListeners();
  }

  DateTime? getEarliestUnpaidMonth(String studentId) {
    if (!_isInitialized) return null;
    final student = _studentsBox.get(studentId);
    if (student == null) return null;

    final now = DateTime.now();
    final ed = student.entryDate;
    DateTime checkDate = DateTime(ed.year, ed.month);
    final endLimit = DateTime(now.year, now.month);

    while (!checkDate.isAfter(endLimit)) {
      final p = _paymentsBox.values.firstWhereOrNull((pay) =>
          pay.studentId == studentId &&
          pay.month.year == checkDate.year &&
          pay.month.month == checkDate.month);
      if (p == null || !p.isPaid) {
        return checkDate;
      }
      checkDate = DateTime(checkDate.year, checkDate.month + 1);
    }
    return null;
  }

  Future<void> payDuesInRange(
      String studentId, DateTime start, DateTime end) async {
    if (!_isInitialized) return;
    DateTime current = DateTime(start.year, start.month);
    final limit = DateTime(end.year, end.month);

    while (!current.isAfter(limit)) {
      await _internalSetPaymentStatus(studentId, current, true);
      current = DateTime(current.year, current.month + 1);
    }

    // Sort history once at the end
    final s = _studentsBox.get(studentId);
    if (s != null) {
      s.paymentHistory.sort((a, b) {
        if (a.paymentDate == null && b.paymentDate == null) return 0;
        if (a.paymentDate == null) return 1;
        if (b.paymentDate == null) return -1;
        return b.paymentDate!.compareTo(a.paymentDate!);
      });
      await _studentsBox.put(s.id, s);
    }
    notifyListeners();
  }

  Future<void> toggleAdmissionStatus(String studentId) async {
    if (!_isInitialized) return;
    final student = _studentsBox.get(studentId);
    if (student == null) return;

    student.isAdmissionPaid = !student.isAdmissionPaid;
    await _studentsBox.put(student.id, student);

    // Sync to Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('students')
            .doc(student.id)
            .set(student.toMap()
              ..['lastUpdated'] = FieldValue.serverTimestamp());
      } catch (e) {
        debugPrint('toggleAdmissionStatus firestore error: $e');
      }
    }
    notifyListeners();
  }

  // ---------- Search ----------
  List<Student> searchStudents(String query) {
    debugPrint('>>> searchStudents called with query="$query"');
    if (!_isInitialized) return [];
    final studentsList = _studentsBox.values.toList();
    if (query.trim().isEmpty) return studentsList;

    final fuse = fuzzy.Fuzzy<Student>(
      studentsList,
      options: fuzzy.FuzzyOptions<Student>(
        keys: [
          fuzzy.WeightedKey<Student>(
              name: 'name', weight: 0.8, getter: (s) => s.name),
          fuzzy.WeightedKey<Student>(
              name: 'batchName', weight: 0.2, getter: (s) => s.batchName),
        ],
      ),
    );

    final result = fuse.search(query);
    final items = result.map((r) => r.item).toList();
    debugPrint(
        '>>> searchStudents found ${items.length} students for query="$query"');
    return items;
  }

  List<Batch> searchBatches(String query) {
    debugPrint('>>> searchBatches called with query="$query"');
    if (!_isInitialized) return [];
    final batchesList = _batchesBox.values.toList();
    if (query.trim().isEmpty) return batchesList;

    final fuse = fuzzy.Fuzzy<Batch>(
      batchesList,
      options: fuzzy.FuzzyOptions<Batch>(
        keys: [
          fuzzy.WeightedKey<Batch>(
              name: 'name', weight: 0.8, getter: (b) => b.name),
          fuzzy.WeightedKey<Batch>(
              name: 'studentClass', weight: 0.2, getter: (b) => b.studentClass),
        ],
      ),
    );

    final result = fuse.search(query);
    final items = result.map((r) => r.item).toList();
    debugPrint(
        '>>> searchBatches found ${items.length} batches for query="$query"');
    return items;
  }

  Map<Batch, List<Student>> searchStudentsAndBatches(String query) {
    debugPrint('>>> searchStudentsAndBatches called with query="$query"');
    if (!_isInitialized) return {};
    final searchedStudents = searchStudents(query);
    final searchedBatches = searchBatches(query);
    final Map<Batch, List<Student>> results = {};

    for (final s in searchedStudents) {
      final batch =
          _batchesBox.values.firstWhereOrNull((b) => b.name == s.batchName);
      if (batch != null) {
        results.putIfAbsent(batch, () => []);
        if (!results[batch]!.any((st) => st.id == s.id)) {
          results[batch]!.add(s);
        }
      }
    }

    for (final b in searchedBatches) {
      if (!results.containsKey(b)) {
        final studentsInBatch =
            _studentsBox.values.where((s) => s.batchName == b.name).toList();
        results[b] = studentsInBatch;
      }
    }

    if (query.trim().isEmpty) {
      results.clear();
      for (final batch in _batchesBox.values) {
        results.putIfAbsent(
            batch,
            () => _studentsBox.values
                .where((s) => s.batchName == batch.name)
                .toList());
      }
    }

    debugPrint(
        '>>> searchStudentsAndBatches returning ${results.length} batches with total students ${results.values.fold<int>(0, (p, e) => p + e.length)}');
    return results;
  }

  /// Cascade delete: local-only helper to remove batch, its students and payments
  Future<void> _cascadeDeleteLocalBatch(Batch batch) async {
    // delete payments for students
    final studentsToDelete =
        _studentsBox.values.where((s) => s.batchName == batch.name).toList();
    for (final student in studentsToDelete) {
      final paymentsToDelete =
          _paymentsBox.values.where((p) => p.studentId == student.id).toList();
      for (final payment in paymentsToDelete) {
        await _paymentsBox.delete(payment.id);
      }
      await _studentsBox.delete(student.id);
      debugPrint(
          '>>> _cascadeDeleteLocalBatch -> deleted local student ${student.id} and ${paymentsToDelete.length} payments');
    }

    // delete batch
    await _batchesBox.delete(batch.id);
    debugPrint(
        '>>> _cascadeDeleteLocalBatch -> deleted local batch ${batch.id}');
    notifyListeners();
  }

  /// Cascade delete both locally (Hive) and remotely (Firestore)
  Future<void> deleteBatch(String batchId) async {
    if (!_isInitialized) return;
    final batch = _batchesBox.get(batchId);
    if (batch == null) return;

    // Capture students to delete
    final studentsToDelete =
        _studentsBox.values.where((s) => s.batchName == batch.name).toList();

    // First, delete local payments & students
    for (final student in studentsToDelete) {
      final paymentsToDelete =
          _paymentsBox.values.where((p) => p.studentId == student.id).toList();
      for (final payment in paymentsToDelete) {
        await _paymentsBox.delete(payment.id);
        debugPrint('>>> deleteBatch -> deleted local payment ${payment.id}');
      }
      await _studentsBox.delete(student.id);
      debugPrint('>>> deleteBatch -> deleted local student ${student.id}');
    }

    // delete local batch
    await _batchesBox.delete(batchId);

    // Track pending deletion locally to prevent zombie resurrection by listener
    final pendingDeletions = _settingsBox
        .get('pending_deletions', defaultValue: <dynamic>[]) as List;
    final List<String> strPending =
        pendingDeletions.map((e) => e.toString()).toList();
    if (!strPending.contains(batchId)) {
      strPending.add(batchId);
      await _settingsBox.put('pending_deletions', strPending);
    }

    debugPrint(
        '>>> deleteBatch -> deleted local batch $batchId and ${studentsToDelete.length} students');

    // Firestore delete if signed in (cascade there too)
    final user = _auth.currentUser;
    if (user != null) {
      try {
        // 1) Delete payments docs in users/{uid}/payments for each student
        final paymentsColl =
            _firestore.collection('users').doc(user.uid).collection('payments');
        for (final student in studentsToDelete) {
          try {
            final paySnap = await paymentsColl
                .where('studentId', isEqualTo: student.id)
                .get();
            for (final d in paySnap.docs) {
              await d.reference.delete();
              debugPrint(
                  '>>> deleteBatch -> deleted firestore payment ${d.id}');
            }
          } catch (e) {
            debugPrint(
                '>>> deleteBatch -> failed to delete payments for student ${student.id}: $e');
          }
        }

        // 2) Delete separate student docs in users/{uid}/students if they exist
        final studentsColl =
            _firestore.collection('users').doc(user.uid).collection('students');
        for (final student in studentsToDelete) {
          try {
            final docRef = studentsColl.doc(student.id);
            final docSnap = await docRef.get();
            if (docSnap.exists) {
              await docRef.delete();
              debugPrint(
                  '>>> deleteBatch -> deleted firestore student doc ${student.id}');
            }
          } catch (e) {
            debugPrint(
                '>>> deleteBatch -> failed to delete firestore student ${student.id}: $e');
          }
        }

        // 3) Remove students from batch doc if present (defensive) then delete batch doc
        final batchDocRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .doc(batchId);
        try {
          await batchDocRef.delete();
          debugPrint('>>> deleteBatch -> deleted firestore batch doc $batchId');

          // Since we successfully deleted from server, remove from pending
          final pending = _settingsBox
              .get('pending_deletions', defaultValue: <dynamic>[]) as List;
          final List<String> currentPending =
              pending.map((e) => e.toString()).toList();
          if (currentPending.contains(batchId)) {
            currentPending.remove(batchId);
            await _settingsBox.put('pending_deletions', currentPending);
          }
        } catch (e) {
          debugPrint(
              '>>> deleteBatch -> failed to delete batch doc $batchId: $e');
          // still attempt to cleanup by querying by name
          try {
            final altQuery = await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('batches')
                .where('name', isEqualTo: batch.name)
                .get();
            for (final d in altQuery.docs) {
              await d.reference.delete();
              debugPrint(
                  '>>> deleteBatch -> deleted firestore alt batch doc ${d.id}');
            }
          } catch (e2) {
            debugPrint('>>> deleteBatch -> alt deletion also failed: $e2');
          }
        }
      } catch (e) {
        debugPrint('deleteBatch firestore error overall: $e');
      }
    }
    notifyListeners();
  }

  Future<void> updateBatch(Batch updatedBatch) async {
    if (!_isInitialized) return;
    final oldBatch = _batchesBox.get(updatedBatch.id);
    if (oldBatch == null) return;
    await _batchesBox.put(updatedBatch.id, updatedBatch);
    if (oldBatch.name != updatedBatch.name) {
      final studentsToUpdate = _studentsBox.values
          .where((s) => s.batchName == oldBatch.name)
          .toList();
      for (final student in studentsToUpdate) {
        student.batchName = updatedBatch.name;
        await _studentsBox.put(student.id, student);
      }
    }
    debugPrint('>>> updateBatch -> updated ${updatedBatch.id}');

    // Firestore update
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .doc(updatedBatch.id)
            .set(updatedBatch.toMap()
              ..['lastUpdated'] = FieldValue.serverTimestamp());
      } catch (e) {
        debugPrint('updateBatch firestore error: $e');
      }
    }
    notifyListeners();
  }

  Future<void> updateBatchWithFees(Batch updatedBatch, double newFees,
      String updateMode, double oldFees) async {
    if (!_isInitialized) return;

    // 1. Update the batch basic info (name, defaultFees) first
    await updateBatch(updatedBatch);

    if (updateMode == 'none') return;

    // Fetch students based on the batch name (updateBatch handles name propagation)
    final studentsInBatch = _studentsBox.values
        .where((s) => s.batchName == updatedBatch.name)
        .toList();

    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    bool anyStudentUpdated = false;

    for (final student in studentsInBatch) {
      bool shouldUpdate = false;
      if (updateMode == 'all') {
        shouldUpdate = true;
      } else if (updateMode == 'default') {
        // Update if student's current fee matches the OLD default fee
        // Use epsilon for double comparison
        if ((student.monthlyFees - oldFees).abs() < 0.01) {
          shouldUpdate = true;
        }
      }

      if (shouldUpdate) {
        anyStudentUpdated = true;
        // Update student's monthly fees
        student.monthlyFees = newFees;

        // Check for current month's payment record in _paymentsBox directly
        final existingPayment = _paymentsBox.values.firstWhereOrNull((p) =>
            p.studentId == student.id &&
            p.month.year == currentMonth.year &&
            p.month.month == currentMonth.month);

        if (existingPayment != null) {
          // Update the record
          final newRecord = existingPayment.copyWith(amount: newFees);
          await _paymentsBox.put(newRecord.id, newRecord);

          // Also update in student history if present
          final historyIndex =
              student.paymentHistory.indexWhere((p) => p.id == newRecord.id);
          if (historyIndex != -1) {
            student.paymentHistory[historyIndex] = newRecord;
          } else {
            student.paymentHistory.add(newRecord);
          }

          // Sync payment update to Firestore
          final user = _auth.currentUser;
          if (user != null) {
            try {
              await _firestore
                  .collection('users')
                  .doc(user.uid)
                  .collection('payments')
                  .doc(newRecord.id)
                  .set(newRecord.toMap()
                    ..['lastUpdated'] = FieldValue.serverTimestamp());
            } catch (e) {
              debugPrint('updateBatchWithFees payment sync error: $e');
            }
          }
        }

        await _studentsBox.put(student.id, student);

        // Sync student update to Firestore
        final user = _auth.currentUser;
        if (user != null) {
          try {
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('students')
                .doc(student.id)
                .set(student.toMap()
                  ..['lastUpdated'] = FieldValue.serverTimestamp());
          } catch (e) {
            debugPrint('updateBatchWithFees student sync error: $e');
          }
        }
      }
    }

    // CRITICAL: If we updated any students, we MUST update the Batch object's
    // student list in _batchesBox, because Batch stores a COPY of the list.
    if (anyStudentUpdated) {
      final freshStudents = _studentsBox.values
          .where((s) => s.batchName == updatedBatch.name)
          .toList();

      final finalBatch = updatedBatch.copyWith(students: freshStudents);
      await _batchesBox.put(finalBatch.id, finalBatch);
      debugPrint(
          '>>> updateBatchWithFees -> synced batch ${finalBatch.id} with updated students');

      // Sync updated batch to Firestore
      final user = _auth.currentUser;
      if (user != null) {
        try {
          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('batches')
              .doc(finalBatch.id)
              .set(finalBatch.toMap()
                ..['lastUpdated'] = FieldValue.serverTimestamp());
        } catch (e) {
          debugPrint('updateBatchWithFees final batch sync error: $e');
        }
      }
    }

    notifyListeners();
  }

  Future<void> addStudentsToBatchByName(
      String batchName, List<Student> newStudents) async {
    if (!_isInitialized) return;
    final batch =
        _batchesBox.values.firstWhereOrNull((b) => b.name == batchName);
    if (batch == null) {
      final newBatchId = DateTime.now().millisecondsSinceEpoch.toString();
      await _batchesBox.put(
          newBatchId,
          Batch(
              id: newBatchId,
              name: batchName,
              studentClass: newStudents.isNotEmpty
                  ? newStudents.first.studentClass
                  : ''));
      debugPrint(
          '>>> addStudentsToBatchByName -> created new batch $newBatchId');
    }
    for (final s in newStudents) {
      await _studentsBox.put(s.id, s);
      debugPrint('>>> addStudentsToBatchByName -> added student ${s.id}');
    }

    // Firestore update
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final batchDocQuery = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .where('name', isEqualTo: batchName)
            .limit(1)
            .get();
        if (batchDocQuery.docs.isNotEmpty) {
          final docRef = batchDocQuery.docs.first.reference;
          final docData = batchDocQuery.docs.first.data();
          final List<dynamic> studentsList =
              (docData['students'] as List<dynamic>?) ?? [];
          studentsList.addAll(newStudents.map((s) => s.toMap()));
          await docRef.set({
            'students': studentsList,
            'lastUpdated': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));
        } else {
          // create new batch doc
          final newBatch = Batch(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: batchName,
              studentClass: newStudents.first.studentClass,
              students: newStudents);
          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('batches')
              .doc(newBatch.id)
              .set(newBatch.toMap()
                ..['lastUpdated'] = FieldValue.serverTimestamp());
        }
      } catch (e) {
        debugPrint('addStudentsToBatchByName firestore error: $e');
      }
    }
    notifyListeners();
  }

  // ----------------------------
  // Backup / Export / Import (provider wrappers)
  // ----------------------------
  Future<File> exportBackup() async {
    if (!_isInitialized) throw Exception('Provider not initialized');
    final data = <String, dynamic>{};
    data['createdAt'] = DateTime.now().toIso8601String();

    // students
    data['students'] = _studentsBox.values.map((s) {
      return {
        'id': s.id,
        'name': s.name,
        'batchName': s.batchName,
        'studentClass': s.studentClass,
        'phoneNumber': s.phoneNumber,
        'notes': s.notes,
        'feesPaid': s.feesPaid,
        'entryDate': s.entryDate.toIso8601String(),
        'paymentHistory': s.paymentHistory.map((p) {
          return {
            'id': p.id,
            'studentId': p.studentId,
            'month': p.month.toIso8601String(),
            'isPaid': p.isPaid,
            'paymentDate': p.paymentDate?.toIso8601String(),
          };
        }).toList(),
      };
    }).toList();

    // batches
    data['batches'] = _batchesBox.values.map((b) {
      return {
        'id': b.id,
        'name': b.name,
        'studentClass': b.studentClass,
        'students': b.students.map((s) => s.id).toList(),
      };
    }).toList();

    // payments
    data['payments'] = _paymentsBox.values.map((p) {
      return {
        'id': p.id,
        'studentId': p.studentId,
        'month': p.month.toIso8601String(),
        'isPaid': p.isPaid,
        'paymentDate': p.paymentDate?.toIso8601String(),
      };
    }).toList();

    // Write backup to app documents directory
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${directory.path}/EduTrackerBackups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'edutrack_backup_$timestamp.json';
    final file = File('${backupDir.path}/$fileName');

    final jsonString = jsonEncode(data);
    await file.writeAsString(jsonString);

    // save last backup info
    await _settingsBox.put('last_backup_path', file.path);
    await _settingsBox.put(
        'last_backup_time', DateTime.now().toIso8601String());

    if (kDebugMode) debugPrint('Backup saved to: ${file.path}');
    return file;
  }

  Future<void> shareBackup({bool createIfMissing = true}) async {
    try {
      String? path = _settingsBox.get('last_backup_path') as String?;
      if (path == null || !(await File(path).exists())) {
        if (!createIfMissing) {
          throw Exception('No backup found');
        }
        final f = await exportBackup();
        path = f.path;
      }
      final xf = XFile(path);
      final params = ShareParams(
        text: 'EduTrack backup file',
        files: [xf],
      );
      await SharePlus.instance.share(params);
      debugPrint('shareBackup: shared file at $path');
    } catch (e) {
      debugPrint('shareBackup error: $e');
      rethrow;
    }
  }

  Future<void> importBackupFromPath(String path) async {
    if (!_isInitialized) throw Exception('Provider not initialized');
    final file = File(path);
    if (!await file.exists()) throw Exception('File not found');
    final content = await file.readAsString();
    final Map<String, dynamic> json = jsonDecode(content);

    // Import batches first (to have batch ids available)
    final List<dynamic> batchesList = (json['batches'] as List<dynamic>?) ?? [];
    for (final b in batchesList) {
      try {
        final id = b['id'] as String;
        final batch = Batch(
            id: id,
            name: b['name'] as String,
            studentClass: b['studentClass'] as String,
            students: <Student>[]);
        await _batchesBox.put(id, batch);
      } catch (e) {
        debugPrint('failed to import batch: $e');
      }
    }

    // Import students
    final List<dynamic> studentsList =
        (json['students'] as List<dynamic>?) ?? [];
    for (final s in studentsList) {
      try {
        final id = s['id'] as String;
        final entryDate = DateTime.parse(s['entryDate'] as String);
        final payments = <PaymentRecord>[];
        final ph = (s['paymentHistory'] as List<dynamic>?) ?? [];
        for (final p in ph) {
          payments.add(PaymentRecord(
            id: p['id'] as String,
            studentId: p['studentId'] as String,
            month: DateTime.parse(p['month'] as String),
            isPaid: p['isPaid'] as bool,
            paymentDate: p['paymentDate'] != null
                ? DateTime.parse(p['paymentDate'] as String)
                : null,
          ));
        }
        final student = Student(
          id: id,
          name: s['name'] as String,
          batchName: s['batchName'] as String,
          studentClass: s['studentClass'] as String,
          phoneNumber: s['phoneNumber'] as String?,
          notes: s['notes'] as String?,
          feesPaid: s['feesPaid'] as bool,
          entryDate: entryDate,
          paymentHistory: payments,
        );
        await _studentsBox.put(id, student);
      } catch (e) {
        debugPrint('failed to import student: $e');
      }
    }

    // Import payments (separate box)
    final List<dynamic> paymentsList =
        (json['payments'] as List<dynamic>?) ?? [];
    for (final p in paymentsList) {
      try {
        final id = p['id'] as String;
        final pr = PaymentRecord(
          id: id,
          studentId: p['studentId'] as String,
          month: DateTime.parse(p['month'] as String),
          isPaid: p['isPaid'] as bool,
          paymentDate: p['paymentDate'] != null
              ? DateTime.parse(p['paymentDate'] as String)
              : null,
        );
        await _paymentsBox.put(id, pr);
      } catch (e) {
        debugPrint('failed to import payment: $e');
      }
    }

    // Optionally: update feesPaid flag on students for current month based on payments
    for (final s in _studentsBox.values) {
      final current = DateTime.now();
      final paymentForThisMonth = _paymentsBox.values.firstWhereOrNull(
        (p) =>
            p.studentId == s.id &&
            p.month.month == current.month &&
            p.month.year == current.year,
      );
      if (paymentForThisMonth != null) {
        s.feesPaid = paymentForThisMonth.isPaid;
        await _studentsBox.put(s.id, s);
      }
    }

    // ===== NEW: after import, reconcile feesPaid flags to ensure consistency =====
    try {
      await _reconcileFeesPaidFlags();
    } catch (e) {
      debugPrint('Error reconciling fees after import: $e');
    }

    await _settingsBox.put(
        'last_import_time', DateTime.now().toIso8601String());
    notifyListeners();
    debugPrint('>>> importBackupFromPath completed');
  }

  Future<void> pickAndImportBackup() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null) {
        debugPrint('pickAndImportBackup: user canceled');
        return;
      }
      final path = result.files.single.path;
      if (path == null) throw Exception('Selected file path is null');
      await importBackupFromPath(path);
    } catch (e) {
      debugPrint('pickAndImportBackup error: $e');
      rethrow;
    }
  }

  // ----------------------------
  // Auto-backup scheduling
  // ----------------------------
  Future<void> enableAutoBackup(bool enabled) async {
    await _settingsBox.put('auto_backup_enabled', enabled);
    if (enabled) {
      try {
        await exportBackup();
      } catch (e) {
        debugPrint('enableAutoBackup: immediate backup failed: $e');
      }
      _scheduleAutoBackup();
    } else {
      _cancelAutoBackup();
    }
    notifyListeners();
  }

  void _scheduleAutoBackup() {
    _cancelAutoBackup();
    _autoBackupTimer = Timer.periodic(autoBackupInterval, (timer) async {
      try {
        await exportBackup();
        debugPrint('Auto-backup executed at ${DateTime.now()}');
      } catch (e) {
        debugPrint('Auto-backup failed: $e');
      }
    });
    debugPrint(
        'Auto-backup scheduled: interval ${autoBackupInterval.inDays} days');
  }

  void _cancelAutoBackup() {
    if (_autoBackupTimer != null) {
      _autoBackupTimer?.cancel();
      _autoBackupTimer = null;
      debugPrint('Auto-backup cancelled');
    }
  }

  bool get isAutoBackupEnabled {
    if (!_isInitialized) return false;
    return _settingsBox.get('auto_backup_enabled', defaultValue: false) as bool;
  }

  String? get lastBackupPath => _settingsBox.get('last_backup_path') as String?;
  String? get lastBackupTime => _settingsBox.get('last_backup_time') as String?;
  String? get lastImportTime => _settingsBox.get('last_import_time') as String?;

  @override
  void dispose() {
    _cancelAutoBackup();
    _authSub?.cancel();
    _batchesSub?.cancel();
    _paymentsSub?.cancel();
    // <-- cancel payments listener
    super.dispose();
  }

  // ----------------------------
  // ======= NEW helper(s) =======
  // ----------------------------

  /// Normalize month to year-month (day = 1) to compare months safely.
  DateTime _normalizeMonth(DateTime dt) => DateTime(dt.year, dt.month);

  /// Recompute feesPaid flag AND paymentHistory for every student based on payments stored in _paymentsBox.
  /// This ensures that after restart/import/firestore-sync the student's local data
  /// correctly reflects the source of truth in _paymentsBox.
  Future<void> _reconcileFeesPaidFlags() async {
    if (!_isInitialized) return;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);

    for (final student in _studentsBox.values) {
      try {
        // 1. Rebuild paymentHistory from _paymentsBox (Source of Truth)
        final studentPayments = _paymentsBox.values
            .where((p) => p.studentId == student.id)
            .toList();

        // Sort by paymentDate descending (nulls last)
        studentPayments.sort((a, b) {
          if (a.paymentDate == null && b.paymentDate == null) return 0;
          if (a.paymentDate == null) return 1;
          if (b.paymentDate == null) return -1;
          return b.paymentDate!.compareTo(a.paymentDate!);
        });

        // Check if we need to update the student object
        // (Simple check: length mismatch or different IDs)
        bool historyChanged = false;
        if (student.paymentHistory.length != studentPayments.length) {
          historyChanged = true;
        } else {
          for (int i = 0; i < studentPayments.length; i++) {
            if (student.paymentHistory[i].id != studentPayments[i].id ||
                student.paymentHistory[i].isPaid != studentPayments[i].isPaid) {
              historyChanged = true;
              break;
            }
          }
        }

        if (historyChanged) {
          student.paymentHistory = studentPayments;
          debugPrint(
              '>>> _reconcile: updated history for ${student.name} (${studentPayments.length} records)');
        }

        // 2. Recompute feesPaid flag for current month
        final bool hasPaidForCurrentMonth = studentPayments.any((p) {
          final pMonth = _normalizeMonth(p.month);
          return pMonth.year == currentMonth.year &&
              pMonth.month == currentMonth.month &&
              p.isPaid == true;
        });

        if (student.feesPaid != hasPaidForCurrentMonth || historyChanged) {
          student.feesPaid = hasPaidForCurrentMonth;
          await _studentsBox.put(student.id, student);
          debugPrint(
              '>>> _reconcile: saved student ${student.id} | feesPaid=$hasPaidForCurrentMonth | historyLen=${studentPayments.length}');
        }
      } catch (e) {
        debugPrint('>>> _reconcileFeesPaidFlags error for ${student.id}: $e');
      }
    }
    notifyListeners();
  }

  // -----------------------------
  // Account Deletion
  // -----------------------------
  Future<void> deleteUserAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    _isLoading = true;
    notifyListeners();

    try {
      final uid = user.uid;

      // 1. Delete all sub-collections (batches, students, payments)
      // Note: Firestore doesn't support recursive delete easily from client SDK.
      // We must fetch and delete documents one by one or use a Cloud Function.
      // For this app, client-side deletion is acceptable as data volume is likely low.

      // Delete Batches
      final batchesSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('batches')
          .get();
      for (final doc in batchesSnap.docs) {
        await doc.reference.delete();
      }

      // Delete Students
      final studentsSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('students')
          .get();
      for (final doc in studentsSnap.docs) {
        await doc.reference.delete();
      }

      // Delete Payments
      final paymentsSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('payments')
          .get();
      for (final doc in paymentsSnap.docs) {
        await doc.reference.delete();
      }

      // 2. Delete the user document itself
      await _firestore.collection('users').doc(uid).delete();

      // 3. Clear local data
      await _studentsBox.clear();
      await _batchesBox.clear();
      await _paymentsBox.clear();
      // keep settings if you want, or clear them too:
      // await _settingsBox.clear();

      // 4. Delete Auth Account
      await user.delete();

      debugPrint('>>> deleteUserAccount -> successfully deleted account $uid');
    } catch (e) {
      debugPrint('deleteUserAccount error: $e');
      rethrow; // let UI handle the error (e.g. re-auth required)
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------- Cycle Utilities ----------

  DateTime getCycleStart(DateTime month, String cycle) {
    if (cycle == 'monthly') return DateTime(month.year, month.month);
    if (cycle == 'bi_monthly') {
      int startMonth = month.month % 2 == 1 ? month.month : month.month - 1;
      return DateTime(month.year, startMonth);
    }
    if (cycle == 'quarterly') {
      int startMonth = ((month.month - 1) ~/ 3) * 3 + 1;
      return DateTime(month.year, startMonth);
    }
    if (cycle == 'half_yearly') {
      int startMonth = ((month.month - 1) ~/ 6) * 6 + 1;
      return DateTime(month.year, startMonth);
    }
    return DateTime(month.year, month.month);
  }

  bool isPaidForCycle(String studentId, DateTime month, String cycle) {
    final start = getCycleStart(month, cycle);
    return _paymentsBox.values.any((p) =>
        p.studentId == studentId &&
        p.isPaid &&
        p.month.year == start.year &&
        p.month.month == start.month);
  }

  Future<void> _updateSiblingLinkage(
      Student updatedStudent, Student? oldStudent) async {
    final oldSiblingId = oldStudent?.siblingId;
    final newSiblingId = updatedStudent.siblingId;

    if (oldSiblingId == newSiblingId) return;

    // 1. If there was an old sibling, clear their reference to this student
    if (oldSiblingId != null) {
      final oldSibling = _studentsBox.get(oldSiblingId);
      if (oldSibling != null && oldSibling.siblingId == updatedStudent.id) {
        oldSibling.siblingId = null;
        await _studentsBox.put(oldSibling.id, oldSibling);
        await _syncStudentToFirestore(oldSibling);
      }
    }

    // 2. If there is a new sibling, set their reference to this student
    if (newSiblingId != null) {
      final newSibling = _studentsBox.get(newSiblingId);
      if (newSibling != null) {
        newSibling.siblingId = updatedStudent.id;
        await _studentsBox.put(newSibling.id, newSibling);
        await _syncStudentToFirestore(newSibling);
      }
    }
  }

  Future<void> _syncStudentToFirestore(Student student) async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('students')
            .doc(student.id)
            .set(student.toMap()
              ..['lastUpdated'] = FieldValue.serverTimestamp());
      } catch (_) {}
    }
  }

  Future<void> toggleBatchPostponed(String batchId, bool isPostponed) async {
    if (!_isInitialized) return;
    final batch = _batchesBox.get(batchId);
    if (batch == null) return;

    final updatedBatch =
        batch.copyWith(postponed: isPostponed, lastUpdated: DateTime.now());
    await _batchesBox.put(batchId, updatedBatch);
    debugPrint(
        '>>> toggleBatchPostponed -> batch $batchId postponed=$isPostponed');

    // Update Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('batches')
            .doc(batchId)
            .update({
          'postponed': isPostponed,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('toggleBatchPostponed firestore error: $e');
      }
    }
    notifyListeners();
  }
}
