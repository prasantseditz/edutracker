import 'package:flutter/material.dart';
import '../widgets/responsive_container.dart';
import 'package:provider/provider.dart';
import '../models/student.dart';
import '../providers/edutrack_provider.dart';
import '../widgets/confirmation_dialog.dart';
import 'edit_student_screen.dart';
import 'package:page_transition/page_transition.dart';
import '../widgets/payment_warning_dialog.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../services/ad_manager.dart';

class StudentDetailsScreen extends StatefulWidget {
  final Student student;
  const StudentDetailsScreen({super.key, required this.student});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();
    final currentStudent =
        provider.students.firstWhere((s) => s.id == widget.student.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentStudent.name),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit_student') {
                AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                  Navigator.of(context).push(
                    PageTransition(
                      type: PageTransitionType.rightToLeft,
                      child: EditStudentScreen(student: currentStudent),
                    ),
                  );
                });
              } else if (value == 'delete_student') {
                AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                  _confirmDeleteStudent(context, provider);
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit_student',
                child: Text('Edit Student'),
              ),
              const PopupMenuItem<String>(
                value: 'delete_student',
                child:
                    Text('Delete Student', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 800,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student Name: ${currentStudent.name}',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text('${provider.batchLabel} Name: ${currentStudent.batchName}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text('${provider.subLabel}: ${currentStudent.studentClass}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(
                  'Monthly Fees: ${provider.currencySymbol}${_formatAmount(currentStudent.monthlyFees)}',
                  style: Theme.of(context).textTheme.titleMedium),
              if (currentStudent.admissionFees > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Admission Fees:',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 10),
                    Text(
                      '${provider.currencySymbol}${_formatAmount(currentStudent.admissionFees)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 15),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: currentStudent.isAdmissionPaid
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          final newStatus = currentStudent.isAdmissionPaid
                              ? 'Unpaid'
                              : 'Paid';
                          final bool? confirmed = await showConfirmationDialog(
                            context,
                            'Mark Admission as $newStatus?',
                          );
                          if (confirmed == true) {
                            provider.toggleAdmissionStatus(currentStudent.id);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(0, 30),
                        ),
                        child: Text(
                          currentStudent.isAdmissionPaid ? 'Paid' : 'Due',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text('Phone Number: ${currentStudent.phoneNumber ?? "N/A"}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text('Notes: ${currentStudent.notes ?? "N/A"}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(
                  'From: ${DateFormat('dd MMMM yyyy, hh:mm a').format(currentStudent.entryDate)}',
                  style: Theme.of(context).textTheme.titleMedium),
              if (currentStudent.siblingId != null) ...[
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final sibling = provider.students.firstWhereOrNull(
                      (s) => s.id == currentStudent.siblingId);
                  if (sibling == null) return const SizedBox.shrink();
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        PageTransition(
                          type: PageTransitionType.fade,
                          child: StudentDetailsScreen(student: sibling),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.people,
                            color: Colors.purple, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Sibling: ${sibling.name}',
                          style: const TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Payment Status:',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: currentStudent.feesPaid
                          ? Colors.green
                          : Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        AdManager.instance.showInterstitialIfAllowed(
                            onAdComplete: () async {
                          if (currentStudent.feesPaid) {
                            final bool? confirmed =
                                await showConfirmationDialog(
                              context,
                              'Mark this student as Due for this month?',
                            );
                            if (confirmed == true) {
                              provider.togglePaymentStatusForMonth(
                                  currentStudent.id, DateTime.now());
                            }
                          } else {
                            // Check for earlier dues
                            final earliestDue = provider
                                .getEarliestUnpaidMonth(currentStudent.id);

                            final result = await showDialog<String>(
                              context: context,
                              builder: (ctx) => PaymentWarningDialog(
                                studentName: currentStudent.name,
                                targetMonth: DateTime.now(),
                                earliestDueMonth: earliestDue,
                              ),
                            );

                            if (result == 'confirm') {
                              await provider.togglePaymentStatusForMonth(
                                  currentStudent.id, DateTime.now());
                            } else if (result == 'pay_from_earliest' &&
                                earliestDue != null) {
                              await provider.payDuesInRange(currentStudent.id,
                                  earliestDue, DateTime.now());
                            }
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        shadowColor: Colors.transparent,
                      ),
                      child: Text(currentStudent.feesPaid ? 'Paid' : 'Due'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Payment History:',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  // Fetch payments directly from provider (Source of Truth)
                  final allPayments = provider.payments
                      .where((p) => p.studentId == currentStudent.id)
                      .toList();

                  // Sort by paymentDate descending (nulls last)
                  allPayments.sort((a, b) {
                    if (a.paymentDate == null && b.paymentDate == null) {
                      return 0;
                    }
                    if (a.paymentDate == null) return 1;
                    if (b.paymentDate == null) return -1;
                    return b.paymentDate!.compareTo(a.paymentDate!);
                  });

                  if (allPayments.isEmpty) {
                    return const Text('No payment history yet.');
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: allPayments.length,
                    itemBuilder: (context, index) {
                      final record = allPayments[index];
                      return ListTile(
                        leading: const Icon(Icons.receipt),
                        title: Text(
                          '${DateFormat('MMMM yyyy').format(record.month)} — ${record.isPaid ? (record.paymentDate != null ? 'Paid on ${DateFormat('dd MMMM yyyy, hh:mm a').format(record.paymentDate!)}' : 'Paid') : 'Due'}',
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteStudent(BuildContext context, EduTrackProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Student'),
          content: Text(
              'Are you sure you want to delete ${widget.student.name}? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                provider.deleteStudent(
                    widget.student.id); // Will implement this method next
                Navigator.of(context).pop(); // Dismiss the dialog
                Navigator.of(context).pop(); // Go back to previous screen
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
