import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../providers/edutrack_provider.dart';
import 'history_screen.dart';
import 'due_details_screen.dart';
import '../widgets/fade_in.dart';
import 'package:page_transition/page_transition.dart';
import '../services/ad_manager.dart';

class YearlyHistoryScreen extends StatefulWidget {
  const YearlyHistoryScreen({super.key});

  @override
  State<YearlyHistoryScreen> createState() => _YearlyHistoryScreenState();
}

class _YearlyHistoryScreenState extends State<YearlyHistoryScreen> {
  int _selectedYear = DateTime.now().year;

  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();
    final currency = provider.currencySymbol;

    // 1. Calculate stats per month for the selected year
    // We want to show months that have EITHER payments OR dues (conceptually active months)
    // But the prompt says "jegulo te records ache" (where records exist).
    // Usually "records" means payment records.
    // However, it also asks for "due koto taka". Due exists if students are active.
    // So we should check if there are students active in that month.

    final Map<int, Map<String, double>> monthStats = {};

    // Initialize months 1..12
    for (int m = 1; m <= 12; m++) {
      monthStats[m] = {'paid': 0.0, 'due': 0.0, 'hasData': 0.0};
    }

    // Calculate Paid
    for (final p in provider.payments) {
      if (p.month.year == _selectedYear && p.isPaid) {
        monthStats[p.month.month]!['paid'] =
            (monthStats[p.month.month]!['paid'] ?? 0) + p.amount;
        monthStats[p.month.month]!['hasData'] = 1.0;
      }
    }

    // Calculate Due (Approximate based on historical eligibility)
    // This is expensive if we do it for every month, but feasible for 12 months.
    for (int m = 1; m <= 12; m++) {
      final monthDate = DateTime(_selectedYear, m);
      // Skip future months if needed? Or show them as 0 due?
      // Usually dues are relevant up to current month.
      if (monthDate.isAfter(DateTime.now())) continue;

      double dueForMonth = 0.0;
      for (final s in provider.students) {
        // Check eligibility
        final ed = s.entryDate;
        final eligible = ed.year < _selectedYear ||
            (ed.year == _selectedYear && ed.month <= m);
        if (!eligible) continue;

        // Match batch to check postponed status
        final batch =
            provider.batches.firstWhereOrNull((b) => b.name == s.batchName);
        if (batch != null && batch.postponed) continue; // Skip postponed

        final cycle = batch?.feesCycle ?? 'monthly';

        // Check given month payment status logic
        // We reuse logic similar to isPaidForCycle but derived for historical snap
        if (!provider.isPaidForCycle(s.id, monthDate, cycle)) {
          dueForMonth += s.monthlyFees;
          if (s.monthlyFees > 0) {
            monthStats[m]!['hasData'] = 1.0;
          }
        } else {
          // even if paid, it counts as "has data" (handled by payment loop above mostly,
          // but what if paid 0? anyway payment loop handles actual payments)
        }
      }
      monthStats[m]!['due'] = dueForMonth;
    }

    // Filter months that have data
    final activeMonths =
        monthStats.entries.where((e) => e.value['hasData']! > 0).toList();

    // Sort descending by month (latest first)
    activeMonths.sort((a, b) => b.key.compareTo(a.key));

    // Calculate Yearly Totals
    double totalYearlyPaid = 0;
    double totalYearlyDue = 0;
    for (var entry in activeMonths) {
      totalYearlyPaid += entry.value['paid']!;
      totalYearlyDue += entry.value['due']!;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yearly Summary'),
        actions: [
          // Year Selector
          DropdownButton<int>(
            value: _selectedYear,
            dropdownColor: Theme.of(context).primaryColor,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            iconEnabledColor: Colors.white,
            underline: Container(),
            items: List.generate(5, (index) {
              final y = DateTime.now().year - index;
              return DropdownMenuItem(value: y, child: Text(y.toString()));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedYear = val);
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Grand Summary Section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withAlpha(50),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildGrandTotalItem(
                  context,
                  'Total Paid',
                  totalYearlyPaid,
                  Colors.green,
                  currency,
                ),
                Container(
                  height: 40,
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                _buildGrandTotalItem(
                  context,
                  'Total Due',
                  totalYearlyDue,
                  Colors.orange,
                  currency,
                ),
              ],
            ),
          ),
          Expanded(
            child: activeMonths.isEmpty
                ? Center(
                    child: Text(
                      'No records for $_selectedYear',
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: activeMonths.length,
                    itemBuilder: (context, index) {
                      final entry = activeMonths[index];
                      final monthNum = entry.key;
                      final stats = entry.value;
                      final paid = stats['paid']!;
                      final due = stats['due']!;
                      final monthName = DateFormat('MMMM')
                          .format(DateTime(_selectedYear, monthNum));

                      // Improved Card Design
                      return FadeIn(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(20),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color:
                                  Theme.of(context).dividerColor.withAlpha(50),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Month Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey[800]
                                      : Colors.deepPurple.shade50,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16)),
                                ),
                                child: Text(
                                  monthName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.deepPurple,
                                      ),
                                ),
                              ),
                              Row(
                                children: [
                                  // Collected Section
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(16)),
                                        onTap: () {
                                          AdManager.instance
                                              .showInterstitialIfAllowed(
                                                  onAdComplete: () {
                                            Navigator.of(context).push(
                                              PageTransition(
                                                type: PageTransitionType
                                                    .rightToLeft,
                                                child: HistoryScreen(
                                                  initialMonth: DateTime(
                                                      _selectedYear, monthNum),
                                                ),
                                              ),
                                            );
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: _buildStatItem(
                                            context,
                                            label: 'Collected',
                                            amount:
                                                '$currency${_formatAmount(paid)}',
                                            color: Colors.green,
                                            icon: Icons.check_circle_outline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Divider
                                  Container(
                                    width: 1,
                                    height: 60,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  // Due Section
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: const BorderRadius.only(
                                            bottomRight: Radius.circular(16)),
                                        onTap: () {
                                          AdManager.instance
                                              .showInterstitialIfAllowed(
                                                  onAdComplete: () {
                                            Navigator.of(context).push(
                                              PageTransition(
                                                type: PageTransitionType
                                                    .rightToLeft,
                                                child: DueDetailsScreen(
                                                  initialMonth: DateTime(
                                                      _selectedYear, monthNum),
                                                ),
                                              ),
                                            );
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: _buildStatItem(
                                            context,
                                            label: 'Due',
                                            amount:
                                                '$currency${_formatAmount(due)}',
                                            color: Colors.orange,
                                            icon: Icons.pending_actions,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context,
      {required String label,
      required String amount,
      required Color color,
      required IconData icon}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildGrandTotalItem(BuildContext context, String label, double amount,
      Color color, String currency) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$currency${_formatAmount(amount)}',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
