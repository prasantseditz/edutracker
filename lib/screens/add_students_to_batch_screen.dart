import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';

import '../models/student.dart';
import '../models/batch.dart';
import '../providers/edutrack_provider.dart';
import '../services/ad_manager.dart';

class AddStudentsToBatchScreen extends StatefulWidget {
  final String batchName;
  final String studentClass;

  const AddStudentsToBatchScreen({
    super.key,
    required this.batchName,
    required this.studentClass,
  });

  @override
  State<AddStudentsToBatchScreen> createState() =>
      _AddStudentsToBatchScreenState();
}

class _AddStudentsToBatchScreenState extends State<AddStudentsToBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _phoneControllers = [];
  final List<TextEditingController> _notesControllers = [];
  final List<TextEditingController> _feesControllers =
      []; // New: fees controllers
  final List<bool> _useDefaultFees = []; // true = use default, false = custom
  final List<FocusNode> _nameFocusNodes = [];
  int _studentCount = 0;

  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  // NOTE: interstitial now managed via AdManager (centralized).
  static const String _interstitialCounterKey = 'interstitial_nav_count';
  static const int _showEvery = 3; // show every 3 navigations

  bool _fieldsInitialized = false;

  @override
  void initState() {
    super.initState();
    // Removed _addStudentFields(initial: true) from here
    // We will call it in build after provider is ready
  }

  @override
  void dispose() {
    for (var c in _nameControllers) {
      c.dispose();
    }
    for (var c in _phoneControllers) {
      c.dispose();
    }
    for (var c in _notesControllers) {
      c.dispose();
    }
    for (var c in _feesControllers) {
      c.dispose();
    }
    for (var n in _nameFocusNodes) {
      n.dispose();
    }

    super.dispose();
  }

  void _addStudentFields({bool initial = false}) {
    if (_studentCount >= 10) return;

    // Get batch default fees
    final provider = context.read<EduTrackProvider>();
    final batch = provider.batches.firstWhere(
      (b) => b.name == widget.batchName,
      orElse: () => Batch(
          id: '', name: widget.batchName, studentClass: widget.studentClass),
    );
    final defaultFees = batch.defaultFees;

    setState(() {
      _nameControllers.add(TextEditingController());
      _phoneControllers.add(TextEditingController());
      _notesControllers.add(TextEditingController());
      _useDefaultFees.add(true); // Default to using batch default fees
      _feesControllers.add(TextEditingController(
        text: _formatAmount(defaultFees), // Always show the amount
      ));
      _nameFocusNodes.add(FocusNode());
      _studentCount++;
    });

    if (!initial) {
      Future.microtask(() {
        if (mounted) _nameFocusNodes.last.requestFocus();
      });
    }
  }

  void _removeStudentFields(int index) {
    if (_studentCount <= 1) return;
    setState(() {
      _nameControllers[index].dispose();
      _nameControllers.removeAt(index);
      _phoneControllers[index].dispose();
      _phoneControllers.removeAt(index);
      _notesControllers[index].dispose();
      _notesControllers.removeAt(index);
      _feesControllers[index].dispose();
      _feesControllers.removeAt(index);
      _useDefaultFees.removeAt(index); // Remove fee mode tracking
      _nameFocusNodes[index].dispose();
      _nameFocusNodes.removeAt(index);
      _studentCount--;
    });
  }

  Future<void> _saveStudentsFromAppBar() async {
    if (_formKey.currentState?.validate() != true) return;

    final provider = context.read<EduTrackProvider>();
    final navigator = Navigator.of(context);

    // Get batch default fees for fallback
    final batch = provider.batches.firstWhere(
      (b) => b.name == widget.batchName,
      orElse: () => Batch(
          id: '', name: widget.batchName, studentClass: widget.studentClass),
    );
    final defaultFees = batch.defaultFees;

    FocusScope.of(context).unfocus();

    for (int i = 0; i < _nameControllers.length; i++) {
      final name = _nameControllers[i].text.trim();
      if (name.isEmpty) continue;

      double monthlyFees;
      if (_feesControllers[i].text.trim().isEmpty) {
        monthlyFees = defaultFees;
      } else {
        monthlyFees = double.tryParse(_feesControllers[i].text.trim()) ?? 0.0;
      }

      final newStudent = Student(
        id: DateTime.now().microsecondsSinceEpoch.toString() + i.toString(),
        name: name,
        studentClass: widget.studentClass,
        batchName: widget.batchName,
        phoneNumber: _phoneControllers[i].text.trim().isEmpty
            ? null
            : _phoneControllers[i].text.trim(),
        notes: _notesControllers[i].text.trim().isEmpty
            ? null
            : _notesControllers[i].text.trim(),
        feesPaid: false,
        entryDate: DateTime.now(),
        monthlyFees: monthlyFees,
      );
      await provider.addStudent(newStudent);
    }

    // After saving, decide whether to show ad
    try {
      final settings = Hive.box('settings');
      final int prev = (settings.get(_interstitialCounterKey) as int?) ?? 0;
      final int next = prev + 1;
      await settings.put(_interstitialCounterKey, next);

      final bool shouldShowAd = (next % _showEvery == 0);

      if (shouldShowAd) {
        // Check centralized AdManager's reward-based blocking logic (12 hours)
        final allowed = await AdManager.instance.canShowInterstitial();
        if (allowed) {
          // Show interstitial via AdManager (it handles preload, dismissal, reload)
          await AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
            if (mounted) navigator.pop();
          });
          return;
        }
      }

      // No ad to show — directly navigate back
      if (mounted) navigator.pop();
    } catch (e) {
      // fallback: just pop
      if (mounted) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();

    // 1. Show loading if provider not ready
    if (provider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Initialize fields once provider is ready
    if (!_fieldsInitialized) {
      _fieldsInitialized = true;
      // Defer state update to next frame to avoid build-phase setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addStudentFields(initial: true);
      });
      // Show loading for this frame
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final appBarActionStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color.fromARGB(255, 26, 126, 207),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Add Students — ${widget.batchName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10),
            child: TextButton(
              style: appBarActionStyle,
              onPressed: _saveStudentsFromAppBar,
              child: const Text('Add Students',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                    '${provider.batchLabel}: ${widget.batchName}, ${provider.subLabel}: ${widget.studentClass}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 20),
                ...List.generate(_nameControllers.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Student ${index + 1}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall),
                                    if (_studentCount > 1)
                                      IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.red),
                                        onPressed: () =>
                                            _removeStudentFields(index),
                                      ),
                                  ]),
                              TextFormField(
                                controller: _nameControllers[index],
                                focusNode: _nameFocusNodes[index],
                                decoration: const InputDecoration(
                                    labelText: 'Student Name *'),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter student name';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                  controller: _phoneControllers[index],
                                  decoration: const InputDecoration(
                                      labelText: 'Phone (Optional)'),
                                  keyboardType: TextInputType.phone),
                              const SizedBox(height: 10),
                              // Fees Selection Dropdown
                              Builder(
                                builder: (context) {
                                  // Get batch default fees
                                  final provider =
                                      context.read<EduTrackProvider>();
                                  final batch = provider.batches.firstWhere(
                                    (b) => b.name == widget.batchName,
                                    orElse: () => Batch(
                                      id: '',
                                      name: widget.batchName,
                                      studentClass: widget.studentClass,
                                    ),
                                  );
                                  final defaultFees = batch.defaultFees;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      DropdownButtonFormField<bool>(
                                        initialValue: _useDefaultFees[index],
                                        decoration: const InputDecoration(
                                          labelText: 'Fees Option',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: true,
                                            child: Text(
                                              'Use Default Fees (${provider.currencySymbol}${_formatAmount(defaultFees)})',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                          const DropdownMenuItem(
                                            value: false,
                                            child: Text('Custom Amount'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          setState(() {
                                            _useDefaultFees[index] = value!;
                                            if (value) {
                                              // Reset to default fees
                                              _feesControllers[index].text =
                                                  _formatAmount(defaultFees);
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      TextFormField(
                                        controller: _feesControllers[index],
                                        enabled: !_useDefaultFees[index],
                                        decoration: InputDecoration(
                                          labelText:
                                              'Monthly Fees (${provider.currencySymbol})',
                                          hintText: _useDefaultFees[index]
                                              ? 'Using default fees'
                                              : 'Enter custom amount',
                                          border: const OutlineInputBorder(),
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Fees amount is required';
                                          }
                                          final num = double.tryParse(v.trim());
                                          if (num == null) {
                                            return 'Enter a valid number';
                                          }
                                          if (num < 0) {
                                            return 'Cannot be negative';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                  controller: _notesControllers[index],
                                  decoration: const InputDecoration(
                                      labelText: 'Notes (Optional)'),
                                  maxLines: 3),
                            ]),
                      ),
                    ),
                  );
                }),
                if (_studentCount < 10)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        onPressed: _addStudentFields,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Another Student')),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
