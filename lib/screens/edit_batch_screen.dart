import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/batch.dart';
import '../providers/edutrack_provider.dart';

class EditBatchScreen extends StatefulWidget {
  final Batch batch;
  const EditBatchScreen({super.key, required this.batch});

  @override
  State<EditBatchScreen> createState() => _EditBatchScreenState();
}

class _EditBatchScreenState extends State<EditBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _classController;
  late TextEditingController _defaultFeesController;
  String _feesCycle = 'monthly';

  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.batch.name);
    _classController = TextEditingController(text: widget.batch.studentClass);
    _defaultFeesController = TextEditingController(
      text: widget.batch.defaultFees > 0
          ? _formatAmount(widget.batch.defaultFees)
          : '',
    );
    _feesCycle = widget.batch.feesCycle;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    _defaultFeesController.dispose();
    super.dispose();
  }

  Future<void> _saveBatch() async {
    if (_formKey.currentState!.validate()) {
      final provider = context.read<EduTrackProvider>();
      final newDefaultFees =
          double.tryParse(_defaultFeesController.text.trim()) ?? 0.0;
      final oldDefaultFees = widget.batch.defaultFees;

      // Check if fees changed
      String updateMode = 'none';
      if (newDefaultFees != oldDefaultFees && newDefaultFees > 0) {
        // Show dialog to ask if user wants to apply to all students
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Update Student Fees?'),
            content: Text(
              'Do you want to apply this fee to all students in this ${provider.batchLabel.toLowerCase()}, or only update the default for new students?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('default'),
                child: const Text('Only Default'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop('all'),
                child: const Text('Apply to All'),
              ),
            ],
          ),
        );
        if (result != null) {
          updateMode = result;
        }
      }

      final updatedBatch = Batch(
        id: widget.batch.id,
        name: _nameController.text,
        studentClass: _classController.text,
        students: widget.batch.students,
        defaultFees: newDefaultFees,
        feesCycle: _feesCycle,
      );

      // Use the new method to handle fee updates + dashboard sync
      await provider.updateBatchWithFees(
          updatedBatch, newDefaultFees, updateMode, oldDefaultFees);

      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${provider.batchLabel}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration:
                    InputDecoration(labelText: '${provider.batchLabel} Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a ${provider.batchLabel.toLowerCase()} name';
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
                    return 'Please enter a ${provider.subLabel.toLowerCase()}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _defaultFeesController,
                decoration: InputDecoration(
                  labelText:
                      'Default Monthly Fees (${provider.currencySymbol})',
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _feesCycle,
                decoration: const InputDecoration(
                  labelText: 'Fees Payment Cycle',
                  prefixIcon: Icon(Icons.sync),
                ),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
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
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saveBatch,
                child: const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
