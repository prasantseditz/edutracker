import 'package:flutter/material.dart';
import '../widgets/responsive_container.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/edutrack_provider.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull
import '../models/student.dart';
import '../models/batch.dart';
import '../widgets/stylish_search_bar.dart';
import '../widgets/confirmation_dialog.dart';
import 'student_details_screen.dart';
import 'batch_details_screen.dart';
import 'package:page_transition/page_transition.dart';
import '../widgets/payment_warning_dialog.dart';
import '../widgets/fade_in.dart';
import 'dart:async';
import '../services/ad_manager.dart';

import 'yearly_history_screen.dart';

class HistoryScreen extends StatefulWidget {
  final DateTime? initialMonth;
  const HistoryScreen({super.key, this.initialMonth});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum HistorySortOption { byBatch, lastModified }

class _HistoryScreenState extends State<HistoryScreen> {
  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  late DateTime _month;
  // PageView Logic
  late PageController _pageController;
  final int _initialPage = 10000;
  late DateTime _pivotMonth; // The month corresponding to _initialPage

  String _query = '';
  final Map<String, bool> _expandedState = {};
  Timer? _adTimer;
  HistorySortOption _sortOption = HistorySortOption.byBatch;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = widget.initialMonth ?? DateTime(now.year, now.month);
    _pivotMonth = _month;
    _pageController = PageController(initialPage: _initialPage);
    _startAdTimer();
  }

  int _currentAdDelaySeconds = 35;

  void _startAdTimer() {
    _scheduleNextAd();
  }

  void _scheduleNextAd() {
    _adTimer?.cancel();
    _adTimer = Timer(Duration(seconds: _currentAdDelaySeconds), () {
      if (!mounted) return;

      AdManager.instance.showRewardedInterstitialAd(
        context: context,
        triggerAdBlocker: false, // Don't trigger 12h block for this periodic ad
        onUserEarnedReward: (_) {
          // Optional: Handle reward if needed
        },
        onAdClosed: () {
          _incrementDelayAndReschedule();
        },
        onFailedToLoad: (e) {
          // If ad fails to load, still reschedule for next time
          _incrementDelayAndReschedule();
        },
      );
    });
  }

  void _incrementDelayAndReschedule() {
    if (!mounted) return;
    setState(() {
      _currentAdDelaySeconds += 5;
    });
    _scheduleNextAd();
  }

  // ... (Ad Timer code remains, skipping lines 53-85) ...

  void _shiftMonth(int delta) {
    _pageController.animateToPage(
      _pageController.page!.round() + delta,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    super.dispose();
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
          title: const Text('Payment History'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
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
      body: ResponsiveContainer(
        maxWidth: 800,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            // ...
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
                    _month =
                        DateTime(_pivotMonth.year, _pivotMonth.month + diff);
                  });
                },
                itemBuilder: (context, index) {
                  final diff = index - _initialPage;
                  final pageMonth =
                      DateTime(_pivotMonth.year, _pivotMonth.month + diff);

                  return _sortOption == HistorySortOption.byBatch
                      ? _buildBatchWiseList(provider, pageMonth)
                      : _buildLastModifiedList(provider, pageMonth);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildLastModifiedList(EduTrackProvider provider, DateTime month) {
    final allPayments = provider.payments;
    final q = _query.trim().toLowerCase();

    // 1. Gather all paid students for this month
    List<Student> paidStudents = [];
    for (final s in provider.students) {
      // Check eligibility by entry date
      final ed = s.entryDate;
      final eligible = ed.year < month.year ||
          (ed.year == month.year && ed.month <= month.month);
      if (!eligible) continue;

      // Check if paid this month
      final payment = allPayments.firstWhereOrNull((p) =>
          p.studentId == s.id &&
          p.month.year == month.year &&
          p.month.month == month.month);

      if (payment != null && payment.isPaid) {
        paidStudents.add(s);
      }
    }

    // 2. Apply Search Filter
    if (q.isNotEmpty) {
      paidStudents = paidStudents.where((s) {
        final nameMatch = s.name.toLowerCase().contains(q);
        final classMatch = s.studentClass.toLowerCase().contains(q);
        final batchMatch = s.batchName.toLowerCase().contains(q);
        return nameMatch || classMatch || batchMatch;
      }).toList();
    }

    if (paidStudents.isEmpty) {
      return const Center(child: Text('No paid students found for this month'));
    }

    // 3. Sort by Payment Date (Newest First)
    paidStudents.sort((a, b) {
      final pA = allPayments.firstWhereOrNull((p) =>
          p.studentId == a.id &&
          p.month.year == month.year &&
          p.month.month == month.month);
      final pB = allPayments.firstWhereOrNull((p) =>
          p.studentId == b.id &&
          p.month.year == month.year &&
          p.month.month == month.month);

      final dateA = pA?.paymentDate ?? DateTime(0);
      final dateB = pB?.paymentDate ?? DateTime(0);
      return dateB.compareTo(dateA); // Descending
    });

    // 4. Group consecutive students from same batch
    final List<List<Student>> groupedStudents = [];
    if (paidStudents.isNotEmpty) {
      List<Student> currentGroup = [paidStudents.first];
      for (int i = 1; i < paidStudents.length; i++) {
        final s = paidStudents[i];
        if (s.batchName == currentGroup.last.batchName) {
          currentGroup.add(s);
        } else {
          groupedStudents.add(currentGroup);
          currentGroup = [s];
        }
      }
      groupedStudents.add(currentGroup);
    }

    return ListView.builder(
      itemCount: groupedStudents.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryHeader(paidStudents.length, provider);
        }

        final group = groupedStudents[index - 1];
        final batchName = group.first.batchName;

        // Always show as a Batch Card with header, even for single students
        return FadeIn(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$batchName (${group.length} students)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...group.map((student) => _buildStudentTile(
                      student, provider, month,
                      showBatchName: false)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentTile(
      Student student, EduTrackProvider provider, DateTime month,
      {required bool showBatchName}) {
    final allPayments = provider.payments;
    final payment = allPayments.firstWhereOrNull((p) =>
        p.studentId == student.id &&
        p.month.year == month.year &&
        p.month.month == month.month);

    String paymentInfo = 'Not Paid';
    if (payment != null && payment.isPaid) {
      if (payment.paymentDate != null) {
        paymentInfo =
            'Paid on: ${DateFormat('dd MMM, hh:mm a').format(payment.paymentDate!)}';
      } else {
        paymentInfo = 'Paid';
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      title: Text(student.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showBatchName)
          Text('${provider.batchLabel}: ${student.batchName}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black54)),
        Text('${provider.currencySymbol}${_formatAmount(student.monthlyFees)}'),
        const SizedBox(height: 4),
        Text(
          paymentInfo,
          style: TextStyle(
            color:
                (payment != null && payment.isPaid) ? Colors.green : Colors.red,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ]),
      onTap: () {
        Navigator.of(context).push(PageTransition(
            type: PageTransitionType.rightToLeft,
            child: StudentDetailsScreen(student: student)));
      },
      trailing: ElevatedButton(
        onPressed: () async {
          final isPaid = payment != null && payment.isPaid;
          if (isPaid) {
            // Toggling back to Due
            final confirmed = await showConfirmationDialog(
              context,
              'Are you sure you want to mark ${student.name} as Due for ${DateFormat('MMMM yyyy').format(_month)}?',
            );
            if (confirmed == true) {
              await _togglePaymentStatus(student.id, month, provider);
              if (mounted) setState(() {});
            }
          } else {
            // Check for earlier dues
            final earliestDue = provider.getEarliestUnpaidMonth(student.id);

            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => PaymentWarningDialog(
                studentName: student.name,
                targetMonth: month,
                earliestDueMonth: earliestDue,
              ),
            );

            if (result == 'confirm') {
              await _togglePaymentStatus(student.id, month, provider);
              if (mounted) setState(() {});
            } else if (result == 'pay_from_earliest' && earliestDue != null) {
              await provider.payDuesInRange(student.id, earliestDue, month);
              if (mounted) setState(() {});
            }
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: (payment != null && payment.isPaid)
              ? Colors.green
              : Colors.orange, // Yellow/Orange for Due
        ),
        child: Text(
          (payment != null && payment.isPaid) ? 'Paid' : 'Due',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(int totalPaidStudents, EduTrackProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$totalPaidStudents student${totalPaidStudents != 1 ? 's' : ''} paid this month',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w500,
              color: Colors.green.shade700,
            ),
          ),
          // Only show sort option if there are paid students
          if (totalPaidStudents > 0)
            PopupMenuButton<HistorySortOption>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort By',
              onSelected: (HistorySortOption result) {
                setState(() {
                  _sortOption = result;
                });
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<HistorySortOption>>[
                PopupMenuItem<HistorySortOption>(
                  value: HistorySortOption.byBatch,
                  child: Builder(builder: (context) {
                    final p = context.read<EduTrackProvider>();
                    return Text('By ${p.batchLabel}');
                  }),
                ),
                const PopupMenuItem<HistorySortOption>(
                  value: HistorySortOption.lastModified,
                  child: Text('Last Modified'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBatchWiseList(EduTrackProvider provider, DateTime month) {
    final allPayments = provider.payments;
    final Map<Batch, List<Student>> map = {};
    final q = _query.trim().toLowerCase();
    int totalPaidStudents = 0;

    // For each batch, first get students that belong to the batch and are eligible by entryDate,
    // THEN apply the search filter (if any) to that subset. This prevents students from other batches
    // matching the query and being shown under unrelated batches.
    for (final b in provider.batches) {
      // students that actually belong to this batch and eligible by entryDate
      var studentsInBatch = provider.students.where((s) {
        final ed = s.entryDate;
        final eligible = ed.year < month.year ||
            (ed.year == month.year && ed.month <= month.month);
        return s.batchName == b.name && eligible;
      }).toList();

      if (studentsInBatch.isEmpty) continue;

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

      // Calculate paid students for summary and filtering
      for (final s in studentsInBatch) {
        final payment = allPayments.firstWhereOrNull((p) =>
            p.studentId == s.id &&
            p.month.year == month.year &&
            p.month.month == month.month);
        if (payment != null && payment.isPaid) {
          totalPaidStudents++;
        }
      }

      // If viewing current month: keep only students who have a paid record for this month.
      final now = DateTime.now();
      final isViewingCurrentMonth =
          now.year == month.year && now.month == month.month;

      if (isViewingCurrentMonth) {
        final paidThisMonth = <Student>[];
        for (final s in studentsInBatch) {
          final payment = allPayments.firstWhereOrNull((p) =>
              p.studentId == s.id &&
              p.month.year == month.year &&
              p.month.month == month.month);
          if (payment != null && payment.isPaid) paidThisMonth.add(s);
        }
        if (paidThisMonth.isNotEmpty) map[b] = paidThisMonth;
      } else {
        // other months: include the (possibly search-filtered) studentsInBatch
        map[b] = studentsInBatch;
      }
    }

    if (map.isEmpty) {
      return const Center(child: Text('No students found'));
    }

    final batchList = map.keys.toList();

    return ListView.builder(
      itemCount: batchList.length + 1, // +1 for summary text
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryHeader(totalPaidStudents, provider);
        }

        final batch = batchList[index - 1];
        final students = map[batch]!;
        final isExpanded = _expandedState[batch.id] ?? false;

        // Show first 3 items by default (unless expanded). This keeps layout compact.
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
                    // Use Column with limited ListView height (avoid large trailing space)
                    Column(
                      children: [
                        ...visibleStudents.map((student) {
                          return _buildStudentTile(student, provider, month,
                              showBatchName: false);
                        }),
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
