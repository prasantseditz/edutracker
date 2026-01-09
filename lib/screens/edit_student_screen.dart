import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../models/student.dart';
import '../providers/edutrack_provider.dart';

class EditStudentScreen extends StatefulWidget {
  final Student student;
  const EditStudentScreen({super.key, required this.student});

  @override
  State<EditStudentScreen> createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends State<EditStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _classController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;
  late TextEditingController _monthlyFeesController;
  late TextEditingController _admissionFeesController;
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
    _nameController = TextEditingController(text: widget.student.name);
    _classController = TextEditingController(text: widget.student.studentClass);
    _phoneController = TextEditingController(text: widget.student.phoneNumber);
    _notesController = TextEditingController(text: widget.student.notes);
    _monthlyFeesController = TextEditingController(
      text: widget.student.monthlyFees > 0
          ? _formatAmount(widget.student.monthlyFees)
          : '',
    );
    _admissionFeesController = TextEditingController(
      text: widget.student.admissionFees > 0
          ? _formatAmount(widget.student.admissionFees)
          : '',
    );
    _selectedSiblingId = widget.student.siblingId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _monthlyFeesController.dispose();
    _admissionFeesController.dispose();
    super.dispose();
  }

  void _saveStudent() {
    if (_formKey.currentState!.validate()) {
      final provider = context.read<EduTrackProvider>();
      final monthlyFees =
          double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
      final admissionFees =
          double.tryParse(_admissionFeesController.text.trim()) ?? 0.0;
      final updatedStudent = Student(
        id: widget.student.id,
        name: _nameController.text,
        batchName:
            widget.student.batchName, // Batch name cannot be changed here
        studentClass: _classController.text,
        phoneNumber: _phoneController.text,
        notes: _notesController.text,
        feesPaid: widget.student.feesPaid,
        entryDate: widget.student.entryDate,
        monthlyFees: monthlyFees,
        admissionFees: admissionFees,
        isAdmissionPaid: widget.student.isAdmissionPaid,
        siblingId: _selectedSiblingId,
        paymentHistory: widget.student.paymentHistory,
      );
      provider.updateStudent(updatedStudent);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Student'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Student Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter student name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _classController,
                decoration: InputDecoration(labelText: provider.subLabel),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter ${provider.subLabel.toLowerCase()}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration:
                    const InputDecoration(labelText: 'Phone Number (Optional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration:
                    const InputDecoration(labelText: 'Notes (Optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _monthlyFeesController,
                decoration: InputDecoration(
                  labelText: 'Monthly Fees (${provider.currencySymbol})',
                  hintText: 'Single month fees amount',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // Optional
                  final num = double.tryParse(v.trim());
                  if (num == null) return 'Enter a valid number';
                  if (num < 0) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _admissionFeesController,
                decoration: InputDecoration(
                  labelText: 'Admission Fees (${provider.currencySymbol})',
                  hintText: '0',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // Optional
                  final num = double.tryParse(v.trim());
                  if (num == null) return 'Enter a valid number';
                  if (num < 0) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
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
                            fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedSiblingId == null)
                        Autocomplete<Student>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<Student>.empty();
                            }
                            return provider.students
                                .where((s) => s.id != widget.student.id)
                                .where((Student s) {
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
                        Builder(builder: (context) {
                          final sibling = provider.students.firstWhereOrNull(
                              (s) => s.id == _selectedSiblingId);
                          final name = sibling?.name ??
                              _selectedSiblingName ??
                              'Unknown';
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.purple,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(name),
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
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saveStudent,
                child: const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
