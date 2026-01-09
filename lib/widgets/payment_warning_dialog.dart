import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PaymentWarningDialog extends StatelessWidget {
  final String studentName;
  final DateTime targetMonth;
  final DateTime? earliestDueMonth;

  const PaymentWarningDialog({
    super.key,
    required this.studentName,
    required this.targetMonth,
    this.earliestDueMonth,
  });

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM yyyy').format(targetMonth);
    final earliestMonthName = earliestDueMonth != null
        ? DateFormat('MMMM yyyy').format(earliestDueMonth!)
        : '';
    final hasEarlierDues =
        earliestDueMonth != null && earliestDueMonth!.isBefore(targetMonth);

    return AlertDialog(
      title: Text('$studentName - Payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mark $studentName as Paid for $monthName?'),
          if (hasEarlierDues) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Dues from $earliestMonthName',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You are paying directly for a later month while earlier fees are still due.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        if (hasEarlierDues)
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('pay_from_earliest'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Pay from $earliestMonthName'),
          ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop('confirm'),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
