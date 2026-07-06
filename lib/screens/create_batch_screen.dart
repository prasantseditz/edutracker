// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:edutracker/screens/batches_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../providers/edutrack_provider.dart';
import '../models/batch.dart';
import '../models/student.dart';
import '../services/ad_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/responsive_container.dart';

// CreateBatchScreen with offline-check dialog and create-button lock
class CreateBatchScreen extends StatefulWidget {
  const CreateBatchScreen({super.key});
  @override
  State<CreateBatchScreen> createState() => _CreateBatchScreenState();
}

class _CreateBatchScreenState extends State<CreateBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _batchName = TextEditingController();
  final _studentClass = TextEditingController();
  final _defaultFees = TextEditingController(); // New: default fees for batch
  final ScrollController _scrollController = ScrollController();
  final List<_StudentFields> _studentFields = <_StudentFields>[
    _StudentFields()
  ];

  static const String _interstitialCounterKey = 'interstitial_nav_count';
  bool _isSaving = false;
  String _feesCycle = 'monthly';

  @override
  void dispose() {
    _batchName.dispose();
    _studentClass.dispose();
    _defaultFees.dispose();
    for (final f in _studentFields) {
      f.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  String _makeStudentId(String baseName) {
    return '${DateTime.now().millisecondsSinceEpoch}_${baseName.hashCode}';
  }

  void _addStudentField({bool focus = true}) {
    final f = _StudentFields();
    setState(() => _studentFields.add(f));
    if (focus) {
      Future.microtask(() {
        if (mounted) f.nameFocus.requestFocus();
      });
    }
    // Scroll to bottom to show new field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeStudentField(int index) {
    if (_studentFields.length <= 1) return;
    final removed = _studentFields.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _onCreatePressed() async {
    if (_isSaving) return; // lock while saving
    if (_formKey.currentState?.validate() != true) return;

    // check connectivity
    final online = await NetworkStatus.checkNow();
    bool proceed = true;
    if (!online) {
      proceed = await showOfflineNotice(context);
    }

    if (!proceed) return;

    // proceed to create
    await _createBatchFromAppBar();
  }

  Future<void> _createBatchFromAppBar() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isSaving = true);

    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final batchNameTrim = _batchName.text.trim();
    final studentClassTrim = _studentClass.text.trim();
    final defaultFees = double.tryParse(_defaultFees.text.trim()) ?? 0.0;

    final batch = Batch(
      id: batchId,
      name: batchNameTrim,
      studentClass: studentClassTrim,
      defaultFees: defaultFees,
      feesCycle: _feesCycle,
    );

    final students = _studentFields.map((f) {
      final nameTrim = f.name.text.trim();
      return Student(
        id: _makeStudentId(nameTrim),
        name: nameTrim,
        batchName: batchNameTrim,
        studentClass: studentClassTrim,
        phoneNumber: f.phone.text.trim().isEmpty ? null : f.phone.text.trim(),
        notes: f.notes.text.trim().isEmpty ? null : f.notes.text.trim(),
        entryDate: DateTime.now(),
        feesPaid: false,
        paymentHistory: [],
        monthlyFees: defaultFees, // Use batch's default fees
      );
    }).toList();

    // capture navigator & provider BEFORE awaiting async calls
    final navigator = Navigator.of(context);
    final provider = context.read<EduTrackProvider>();

    // show quick saving message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Saving batch...'),
          duration: Duration(milliseconds: 700)),
    );

    try {
      // IMPORTANT: provider.createBatchWithStudents will always save locally (Hive) first.
      // Firestore sync is attempted separately by provider (and will not block the UI).
      await provider.createBatchWithStudents(batch, students);
    } catch (e) {
      debugPrint('createBatchWithStudents error: $e');
      // still allow navigation back to batches; user saved locally
    }

    if (!mounted) return;

    // handle ad & navigation (same as before) but guard with _isSaving flag
    try {
      final settings = Hive.box('settings');
      final int prev = (settings.get(_interstitialCounterKey) as int?) ?? 0;
      final int next = prev + 1;
      await settings.put(_interstitialCounterKey, next);

      final prefs = await SharedPreferences.getInstance();
      final bool intervalExtended = prefs.getBool('ad_interval_extended') ?? false;
      final int currentShowEvery = intervalExtended ? 10 : 3;

      final bool shouldShowAd = (next % currentShowEvery == 0);

      if (shouldShowAd) {
        final allowed = await AdManager.instance.canShowInterstitial();
        if (allowed) {
          final completer = Completer<void>();
          AdManager.instance.showRewardedInterstitialAd(
            context: context,
            onUserEarnedReward: (_) {},
            onAdClosed: () {
              if (mounted) {
                navigator.pushReplacement(
                  MaterialPageRoute(builder: (_) => const BatchesScreen()),
                );
              }
              if (!completer.isCompleted) completer.complete();
            },
            onFailedToLoad: (e) {
              if (mounted) {
                navigator.pushReplacement(
                  MaterialPageRoute(builder: (_) => const BatchesScreen()),
                );
              }
              if (!completer.isCompleted) completer.complete();
            },
          );
          await completer.future;
          return;
        }
      }

      // No ad to show — directly navigate to Batches screen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Batch created'),
              duration: Duration(milliseconds: 650)),
        );
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const BatchesScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${provider.batchLabel} created (ad check failed): ${e.toString()}'),
            duration: const Duration(seconds: 2)),
      );
      if (mounted) {
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const BatchesScreen()),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();
    // AppBar action button style (violet)
    final appBarActionStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.deepPurple,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Create New ${provider.batchLabel}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10),
            child: TextButton(
              style: appBarActionStyle,
              onPressed: _isSaving ? null : _onCreatePressed,
              child: _isSaving
                  ? Row(children: const [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('Saving...')
                    ])
                  : const Text('Create',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 800,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _batchName,
                      decoration: InputDecoration(
                          labelText: '${provider.batchLabel} Name *'),
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _studentClass,
                      decoration:
                          InputDecoration(labelText: '${provider.subLabel} *'),
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _defaultFees,
                      decoration: InputDecoration(
                        labelText:
                            'Default Monthly Fees (${provider.currencySymbol}) *',
                        hintText: 'Enter amount',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Default fees is required';
                        }
                        final num = double.tryParse(v.trim());
                        if (num == null) return 'Enter a valid number';
                        if (num <= 0) return 'Fees must be greater than 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      initialValue: _feesCycle,
                      decoration: const InputDecoration(
                        labelText: 'Fees Payment Cycle',
                        prefixIcon: Icon(Icons.sync),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(
                            value: 'bi_monthly',
                            child: Text('Bi-monthly (2 months once)')),
                        DropdownMenuItem(
                            value: 'quarterly',
                            child: Text('Quarterly (3 months once)')),
                        DropdownMenuItem(
                            value: 'half_yearly',
                            child: Text('Half-yearly (6 months once)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _feesCycle = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Students',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ..._studentFields.asMap().entries.map((e) {
                      final idx = e.key;
                      final fld = e.value;
                      return _StudentCard(
                        index: idx + 1,
                        fields: fld,
                        onRemove: _studentFields.length > 1
                            ? () => _removeStudentField(idx)
                            : null,
                      );
                    }),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _addStudentField(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Another Student'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // small bottom padding so last field not hidden by system UI
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentFields {
  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController notes = TextEditingController();
  final FocusNode nameFocus = FocusNode();

  void dispose() {
    name.dispose();
    phone.dispose();
    notes.dispose();
    nameFocus.dispose();
  }
}

class _StudentCard extends StatelessWidget {
  final int index;
  final _StudentFields fields;
  final VoidCallback? onRemove;
  const _StudentCard(
      {required this.index, required this.fields, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Student $index',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (onRemove != null)
              IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle, color: Colors.red))
          ]),
          TextFormField(
            controller: fields.name,
            focusNode: fields.nameFocus,
            decoration: const InputDecoration(labelText: 'Student Name *'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
              controller: fields.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          TextFormField(
              controller: fields.notes,
              decoration: const InputDecoration(labelText: 'Additional Notes')),
        ]),
      ),
    );
  }
}

/// Simple network helper using connectivity_plus
class NetworkStatus {
  static Future<bool> checkNow() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) return false;
      // note: connectivity_plus doesn't guarantee internet access, but this is usually enough.
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Show offline notice dialog. Returns true if user chose "Continue anyway".
Future<bool> showOfflineNotice(BuildContext context) async {
  final res = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('You are offline'),
        content: const Text(
            'You are currently offline. Any changes will be saved locally and will sync to the server when internet is available. Do you want to continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue anyway'),
          ),
        ],
      );
    },
  );
  return res == true;
}
