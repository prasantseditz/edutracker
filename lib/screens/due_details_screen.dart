import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../providers/edutrack_provider.dart';
import '../models/student.dart';
import '../models/batch.dart';
import '../widgets/stylish_search_bar.dart';
import '../widgets/confirmation_dialog.dart';
import 'student_details_screen.dart';
import 'batch_details_screen.dart';
import 'package:page_transition/page_transition.dart';
import '../widgets/payment_warning_dialog.dart';
import '../widgets/fade_in.dart';
import '../services/ad_manager.dart';
import 'yearly_history_screen.dart';

class DueDetailsScreen extends StatefulWidget {
  final DateTime? initialMonth;
  const DueDetailsScreen({super.key, this.initialMonth});

  @override
  State<DueDetailsScreen> createState() => _DueDetailsScreenState();
}

class _DueDetailsScreenState extends State<DueDetailsScreen> {
  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  late DateTime _month;
  late PageController _pageController;
  final int _initialPage = 10000;
  late DateTime _pivotMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = widget.initialMonth ?? DateTime(now.year, now.month);
    _pivotMonth = _month;
    _pageController = PageController(initialPage: _initialPage);
  }

  String _query = '';
  final Map<String, bool> _expandedState = {};

  void _shiftMonth(int delta) {
    _pageController.animateToPage(
      _pageController.page!.round() + delta,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _togglePaymentStatus(
      String studentId, DateTime month, EduTrackProvider provider) async {
    await provider.togglePaymentStatusForMonth(studentId, month);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();

    if (provider.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Due Details'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Due Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Yearly Summary',
            onPressed: () {
              AdManager.instance.showInterstitialIfAllowed(onAdComplete: () {
                Navigator.of(context).push(
                  PageTransition(
                    type: PageTransitionType.rightToLeft,
                    child: const YearlyHistoryScreen(),
                  ),
                );
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left)),
            Text(DateFormat('MMMM yyyy').format(_month),
                style: Theme.of(context).textTheme.titleMedium),
            IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          StylishSearchBar(
            hintText: 'Search students...',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                final diff = index - _initialPage;
                setState(() {
                  _month = DateTime(_pivotMonth.year, _pivotMonth.month + diff);
                });
              },
              itemBuilder: (context, index) {
                final diff = index - _initialPage;
                final pageMonth =
                    DateTime(_pivotMonth.year, _pivotMonth.month + diff);
                return _buildBatchWiseList(provider, pageMonth);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBatchWiseList(EduTrackProvider provider, DateTime month) {
    final Map<Batch, List<Student>> map = {};
    final q = _query.trim().toLowerCase();
    int totalDueStudents = 0;

    // For each batch, get students that are eligible by entryDate and have not paid
    for (final b in provider.batches) {
      // students that belong to this batch and eligible by entryDate
      var studentsInBatch = provider.students.where((s) {
        final ed = s.entryDate;
        final eligible = ed.year < month.year ||
            (ed.year == month.year && ed.month <= month.month);
        return s.batchName == b.name && eligible;
      }).toList();

      if (studentsInBatch.isEmpty) continue;

      if (b.postponed) continue; // Skip postponed batches

      if (q.isNotEmpty) {
        // filter only within this batch
        studentsInBatch = studentsInBatch.where((s) {
          final nameMatch = s.name.toLowerCase().contains(q);
          final classMatch = s.studentClass.toLowerCase().contains(q);
          final batchMatch = b.name.toLowerCase().contains(q);
          return nameMatch || classMatch || batchMatch;
        }).toList();
      }

      if (studentsInBatch.isEmpty) continue;

      // Keep only students who have NOT paid for this month (or cycle)
      final dueThisMonth = <Student>[];
      for (final s in studentsInBatch) {
        final cycle = b.feesCycle;
        if (!provider.isPaidForCycle(s.id, month, cycle)) {
          dueThisMonth.add(s);
          totalDueStudents++;
        }
      }
      if (dueThisMonth.isNotEmpty) map[b] = dueThisMonth;
    }

    if (map.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: Colors.green.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              'No dues for ${DateFormat('MMMM yyyy').format(month)}! 🎉',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final batchList = map.keys.toList();

    return ListView.builder(
      itemCount: batchList.length + 1, // +1 for summary text
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '$totalDueStudents student${totalDueStudents != 1 ? 's have' : ' has'} dues this month',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: Colors.orange.shade700,
              ),
            ),
          );
        }

        final batch = batchList[index - 1];
        final students = map[batch]!;
        final isExpanded = _expandedState[batch.id] ?? false;

        // Show first 3 items by default (unless expanded)
        final visibleCount = isExpanded
            ? students.length
            : (students.length > 3 ? 3 : students.length);
        final visibleStudents = students.take(visibleCount).toList();

        return FadeIn(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          PageTransition(
                            type: PageTransitionType.rightToLeft,
                            child: BatchDetailsScreen(batch: batch),
                          ),
                        );
                      },
                      child: Text(
                        '${batch.name} (${students.length} students)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: [
                        ...visibleStudents.map((student) {
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 0.0),
                            title: Text(student.name),
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${provider.currencySymbol}${_formatAmount(student.monthlyFees)}'),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${provider.subLabel}: ${student.studentClass}'),
                                ]),
                            onTap: () {
                              Navigator.of(context).push(PageTransition(
                                  type: PageTransitionType.rightToLeft,
                                  child:
                                      StudentDetailsScreen(student: student)));
                            },
                            trailing: ElevatedButton(
                              onPressed: () async {
                                // Check for earlier dues
                                final earliestDue =
                                    provider.getEarliestUnpaidMonth(student.id);

                                final result = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => PaymentWarningDialog(
                                    studentName: student.name,
                                    targetMonth: month,
                                    earliestDueMonth: earliestDue,
                                  ),
                                );

                                if (result == 'confirm') {
                                  await _togglePaymentStatus(
                                      student.id, month, provider);
                                  if (mounted) setState(() {});
                                } else if (result == 'pay_from_earliest' &&
                                    earliestDue != null) {
                                  await provider.payDuesInRange(
                                      student.id, earliestDue, month);
                                  if (mounted) setState(() {});
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange),
                              child: const Text('Due'),
                            ),
                          );
                          // ignore: unnecessary_to_list_in_spreads
                        }).toList(),
                      ],
                    ),

                    // Show View All / View Less if more than 3 students
                    if (students.length > 3)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _expandedState[batch.id] = !isExpanded;
                            });
                          },
                          child: Text(isExpanded ? 'View Less' : 'View All'),
                        ),
                      ),
                  ]),
            ),
          ),
        );
      },
    );
  }
}
