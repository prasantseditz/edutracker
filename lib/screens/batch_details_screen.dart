import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/batch.dart';
import '../models/student.dart';
import '../providers/edutrack_provider.dart';
import '../widgets/confirmation_dialog.dart';
import 'student_details_screen.dart';
import 'edit_batch_screen.dart';
import 'add_students_to_batch_screen.dart';
import 'package:page_transition/page_transition.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../services/ad_manager.dart';
import '../widgets/payment_warning_dialog.dart';

class BatchDetailsScreen extends StatefulWidget {
  final Batch batch;
  const BatchDetailsScreen({super.key, required this.batch});

  @override
  State<BatchDetailsScreen> createState() => _BatchDetailsScreenState();
}

class _BatchDetailsScreenState extends State<BatchDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();
    final currentBatch =
        provider.batches.firstWhereOrNull((b) => b.id == widget.batch.id) ??
            widget.batch;

    final studentsInBatch = provider.students
        .where((s) => s.batchName == currentBatch.name)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(currentBatch.name),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              // Handle menu item selection
              if (value == 'edit_batch') {
                AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                  Navigator.of(context).push(
                    PageTransition(
                      type: PageTransitionType.rightToLeft,
                      child: EditBatchScreen(batch: currentBatch),
                    ),
                  );
                });
              } else if (value == 'postpone_batch') {
                final isPostponed = currentBatch.postponed;
                final action = isPostponed ? 'Resume' : 'Postpone';
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('$action ${provider.batchLabel}'),
                    content: Text(
                        'Are you sure you want to ${action.toLowerCase()} this ${provider.batchLabel.toLowerCase()}? '
                        '${isPostponed ? "It will appear in due lists again." : "It will be hidden from monthly due lists and history."}'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          provider.toggleBatchPostponed(
                              currentBatch.id, !isPostponed);
                          Navigator.of(ctx).pop();
                        },
                        child: Text(action),
                      ),
                    ],
                  ),
                );
              } else if (value == 'delete_batch') {
                AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                  _confirmDeleteBatch(context, provider);
                });
              } else if (value == 'add_student') {
                AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                  Navigator.of(context).push(
                    PageTransition(
                      type: PageTransitionType.rightToLeft,
                      child: AddStudentsToBatchScreen(
                        batchName: currentBatch.name,
                        studentClass: currentBatch.studentClass,
                      ),
                    ),
                  );
                });
              } else if (value == 'remove_student') {
                AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                  _showRemoveStudentDialog(context, provider, studentsInBatch);
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit_batch',
                child: Text('Edit ${provider.batchLabel}'),
              ),
              PopupMenuItem<String>(
                value: 'postpone_batch',
                child: Text(currentBatch.postponed
                    ? 'Resume ${provider.batchLabel}'
                    : 'Postpone ${provider.batchLabel}'),
              ),
              PopupMenuItem<String>(
                value: 'delete_batch',
                child: Text('Delete ${provider.batchLabel}',
                    style: TextStyle(color: Colors.red)),
              ),
              const PopupMenuItem<String>(
                value: 'add_student',
                child: Text('Add Student'),
              ),
              const PopupMenuItem<String>(
                value: 'remove_student',
                child: Text('Remove Student'),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${provider.batchLabel} Name: ${currentBatch.name}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text('${provider.subLabel}: ${currentBatch.studentClass}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                DateTime? createdDate;
                try {
                  createdDate = DateTime.fromMillisecondsSinceEpoch(
                      int.parse(currentBatch.id));
                } catch (_) {}
                if (createdDate != null) {
                  // Import intl if not already imported, but I see it's not imported in the file.
                  // I should probably add the import or use basic formatting.
                  // Let's assume I can add the import or use simple string interpolation.
                  // Wait, I can't add import here easily without multi_replace.
                  // I'll check imports. 'intl' is NOT imported.
                  // I'll use a simple helper or just basic string for now, or better, add the import.
                  // Actually, I'll just use a simple format: YYYY-MM-DD
                  return Text(
                      'Created: ${createdDate.day}/${createdDate.month}/${createdDate.year}',
                      style: Theme.of(context).textTheme.titleMedium);
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 20),
            Text('Students in this ${provider.batchLabel}:',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            if (studentsInBatch.isEmpty)
              Text(
                  'No students in this ${provider.batchLabel.toLowerCase()} yet.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: studentsInBatch.length,
                itemBuilder: (context, index) {
                  final student = studentsInBatch[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: Text(student.name),
                      subtitle:
                          Text('Status: ${student.feesPaid ? "Paid" : "Due"}'),
                      trailing: ElevatedButton(
                        onPressed: () {
                          AdManager.instance.showInterstitialIfAllowed(
                              onAdComplete: () async {
                            if (student.feesPaid) {
                              // Standard toggle to Due
                              final bool? confirmed =
                                  await showConfirmationDialog(
                                context,
                                'Mark this student as Due for this month?',
                              );
                              if (confirmed == true) {
                                provider.togglePaymentStatusForMonth(
                                    student.id, DateTime.now());
                              }
                            } else {
                              // Check for earlier dues
                              final earliestDue =
                                  provider.getEarliestUnpaidMonth(student.id);

                              final result = await showDialog<String>(
                                context: context,
                                builder: (ctx) => PaymentWarningDialog(
                                  studentName: student.name,
                                  targetMonth: DateTime.now(),
                                  earliestDueMonth: earliestDue,
                                ),
                              );

                              if (result == 'confirm') {
                                await provider.togglePaymentStatusForMonth(
                                    student.id, DateTime.now());
                              } else if (result == 'pay_from_earliest' &&
                                  earliestDue != null) {
                                await provider.payDuesInRange(
                                    student.id, earliestDue, DateTime.now());
                              }
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              student.feesPaid ? Colors.green : Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(student.feesPaid ? 'Paid' : 'Due'),
                      ),
                      onTap: () {
                        AdManager.instance.showInterstitialIfAllowed(
                            onAdComplete: () {
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              child: StudentDetailsScreen(student: student),
                            ),
                          );
                        });
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteBatch(BuildContext context, EduTrackProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Batch'),
          content: Text(
              'Are you sure you want to delete the batch "${widget.batch.name}" and all its students? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                provider.deleteBatch(widget.batch.id);
                Navigator.of(context).pop(); // Dismiss the dialog
                Navigator.of(context)
                    .pop(); // Go back to previous screen (BatchesScreen)
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showRemoveStudentDialog(BuildContext context, EduTrackProvider provider,
      List<Student> studentsInBatch) {
    Student? selectedStudent;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Remove Student from Batch'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Select a student to remove from "${widget.batch.name}":'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<Student>(
                    initialValue: selectedStudent,
                    decoration:
                        const InputDecoration(labelText: 'Select Student'),
                    items: studentsInBatch.map((student) {
                      return DropdownMenuItem<Student>(
                        value: student,
                        child: Text(student.name),
                      );
                    }).toList(),
                    onChanged: (Student? newValue) {
                      setState(() {
                        selectedStudent = newValue;
                      });
                    },
                    validator: (v) =>
                        (v == null) ? 'Please select a student' : null,
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Dismiss the dialog
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (selectedStudent != null) {
                      provider.deleteStudent(selectedStudent!
                          .id); // Assuming deleteStudent removes from the global list
                      Navigator.of(context).pop(); // Dismiss the dialog
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
