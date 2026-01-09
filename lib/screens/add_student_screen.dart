import 'package:flutter/material.dart';
import '../widgets/responsive_container.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../providers/edutrack_provider.dart';
import '../models/student.dart';
import '../models/batch.dart';

class AddStudentScreen extends StatefulWidget {
  const AddStudentScreen({super.key});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  final _monthlyFees = TextEditingController();
  final _admissionFees = TextEditingController();
  final _batchController = TextEditingController();
  final _classController = TextEditingController();

  Batch? _selectedBatch;
  bool _useDefaultFees = true;
  bool _isCreatingNewBatch = false;
  bool _isAdmissionPaid = false;
  String? _selectedSiblingId;
  String? _selectedSiblingName;

  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  @override
  void initState() {
    super.initState();
    _batchController.addListener(_onBatchNameChanged);
  }

  void _onBatchNameChanged() {
    final text = _batchController.text;
    if (_selectedBatch != null &&
        _selectedBatch!.name.toLowerCase() != text.toLowerCase()) {
      setState(() {
        _selectedBatch = null;
        _classController.clear();
        _isCreatingNewBatch = true;
        _useDefaultFees = false; // New batch implies custom fees initially
      });
    } else if (_selectedBatch == null) {
      // Check if it matches any existing batch
      final provider = context.read<EduTrackProvider>();
      final match = provider.batches
          .firstWhereOrNull((b) => b.name.toLowerCase() == text.toLowerCase());
      if (match != null) {
        setState(() {
          _selectedBatch = match;
          _classController.text = match.studentClass;
          _isCreatingNewBatch = false;
          _useDefaultFees = true;
          _monthlyFees.text = _formatAmount(match.defaultFees);
        });
      } else {
        if (!_isCreatingNewBatch) {
          setState(() {
            _isCreatingNewBatch = true;
            _classController.clear();
            _useDefaultFees = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _batchController.removeListener(_onBatchNameChanged);
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _monthlyFees.dispose();
    _admissionFees.dispose();
    _batchController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _createStudentFromAppBar() async {
    if (_formKey.currentState?.validate() != true) return;

    final provider = context.read<EduTrackProvider>();
    final navigator = Navigator.of(context);

    final batchNameInput = _batchController.text.trim();
    final classNameInput = _classController.text.trim();

    // Find or create batch
    Batch? batch = _selectedBatch;
    batch ??= provider.batches.firstWhereOrNull(
      (b) => b.name.toLowerCase() == batchNameInput.toLowerCase(),
    );

    // If still null, it's a new batch
    if (batch == null) {
      if (classNameInput.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Please enter a ${provider.subLabel} for the new ${provider.batchLabel.toLowerCase()}')),
        );
        return;
      }
      // We don't need to explicitly create the batch here,
      // provider.addStudent will create it if it doesn't exist.
      // But we need to ensure the student object has the correct class.
    }

    // Get monthly fees
    double monthlyFees;
    if (_useDefaultFees && batch != null) {
      monthlyFees = batch.defaultFees;
    } else {
      if (_monthlyFees.text.trim().isEmpty) {
        // If custom amount is selected but empty, default to 0 or batch default
        monthlyFees = batch?.defaultFees ?? 0.0;
      } else {
        monthlyFees = double.tryParse(_monthlyFees.text.trim()) ?? 0.0;
      }
    }

    final newStudent = Student(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      studentClass:
          batch?.studentClass ?? classNameInput, // Use input class if new batch
      batchName: batchNameInput, // Use input name
      phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      feesPaid: false,
      entryDate: DateTime.now(),
      monthlyFees: monthlyFees,
      admissionFees: double.tryParse(_admissionFees.text.trim()) ?? 0.0,
      isAdmissionPaid: _isAdmissionPaid,
      siblingId: _selectedSiblingId,
    );

    await provider.addStudent(newStudent);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student added successfully!')),
      );
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();

    if (provider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final batches = provider.batches;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Student'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color.fromARGB(255, 12, 156, 175), // Teal
                    Color.fromARGB(255, 62, 93, 179), // Dark Blue
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withAlpha(51),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _createStudentFromAppBar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text(
                  'SAVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 600,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Student Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Autocomplete<Batch>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Batch>.empty();
                    }
                    return batches.where((Batch option) {
                      return option.name
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  displayStringForOption: (Batch option) => option.name,
                  fieldViewBuilder: (context, textEditingController, focusNode,
                      onFieldSubmitted) {
                    // Sync the internal controller with the Autocomplete controller
                    if (textEditingController.text != _batchController.text) {
                      textEditingController.text = _batchController.text;
                      textEditingController.selection =
                          TextSelection.fromPosition(TextPosition(
                              offset: _batchController.text.length));
                    }

                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      onChanged: (val) {
                        _batchController.text = val;
                      },
                      decoration: InputDecoration(
                        labelText: '${provider.batchLabel} Name',
                        hintText: 'Select existing or type new',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.group),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Required'
                              : null,
                    );
                  },
                  onSelected: (Batch selection) {
                    setState(() {
                      _selectedBatch = selection;
                      _batchController.text = selection.name;
                      _classController.text = selection.studentClass;
                      _isCreatingNewBatch = false;
                      _useDefaultFees = true;
                      _monthlyFees.text = _formatAmount(selection.defaultFees);
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classController,
                  enabled:
                      _isCreatingNewBatch, // Only enabled if creating new batch
                  decoration: InputDecoration(
                    labelText: provider.subLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.school),
                  ),
                  validator: (value) {
                    if (_isCreatingNewBatch &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Required for new ${provider.batchLabel.toLowerCase()}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
                const SizedBox(height: 24),

                // Fees Selection
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<bool>(
                        initialValue: _useDefaultFees,
                        decoration: const InputDecoration(
                          labelText: 'Fees Mode',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 15),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: true,
                            child: Text(
                              _selectedBatch != null
                                  ? 'Default (${provider.currencySymbol}${_formatAmount(_selectedBatch!.defaultFees)})'
                                  : 'Default (${provider.currencySymbol}0)',
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const DropdownMenuItem(
                            value: false,
                            child: Text('Custom Amount',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _useDefaultFees = value!;
                            if (value && _selectedBatch != null) {
                              _monthlyFees.text =
                                  _formatAmount(_selectedBatch!.defaultFees);
                            } else if (value && _selectedBatch == null) {
                              _monthlyFees.text = '0';
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _monthlyFees,
                        enabled: !_useDefaultFees,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          hintText: 'Single month fees amount',
                          border: const OutlineInputBorder(),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Text(
                              provider.currencySymbol,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        validator: (value) {
                          if (!_useDefaultFees &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Required';
                          }
                          final num = double.tryParse(value ?? '');
                          if (!_useDefaultFees && num == null) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                if (provider.appMode == 'org') ...[
                  // Admission Fees Section (Premium Card Style)
                  Card(
                    elevation: 0,
                    color: Colors.blue.withAlpha(13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.blue.withAlpha(51)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _admissionFees,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  'Admission Fees (${provider.currencySymbol})',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.assignment),
                              hintText: 'One-time fee',
                            ),
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            title: const Text('Admission Paid?'),
                            value: _isAdmissionPaid,
                            onChanged: (val) {
                              setState(() => _isAdmissionPaid = val ?? false);
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                ],

                // Sibling Management Section
                Card(
                  elevation: 0,
                  color: Colors.purple.withAlpha(13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.purple.withAlpha(51)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sibling Management (Optional)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedSiblingId == null)
                          Autocomplete<Student>(
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<Student>.empty();
                              }
                              return provider.students.where((Student s) {
                                return s.name.toLowerCase().contains(
                                    textEditingValue.text.toLowerCase());
                              });
                            },
                            displayStringForOption: (Student s) => s.name,
                            fieldViewBuilder: (context, controller, focusNode,
                                onFieldSubmitted) {
                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Search Sibling Name',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.people_outline),
                                  hintText: 'Type to search...',
                                ),
                              );
                            },
                            onSelected: (Student selection) {
                              setState(() {
                                _selectedSiblingId = selection.id;
                                _selectedSiblingName = selection.name;
                              });
                            },
                          )
                        else
                          ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.purple,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(_selectedSiblingName ?? 'Unknown'),
                            subtitle: const Text('Linked as Sibling'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _selectedSiblingId = null;
                                  _selectedSiblingName = null;
                                });
                              },
                            ),
                            tileColor: Colors.purple.withAlpha(26),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
