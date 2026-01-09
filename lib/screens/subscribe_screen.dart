import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:collection/collection.dart'; // Import collection for firstWhereOrNull
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher
import '../widgets/responsive_container.dart';

class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  final TextEditingController _transactionIdController =
      TextEditingController();
  bool _isLoading = false;

  final String _upiId = '8436316793@upi'; // Your UPI ID
  // ignore: unused_field
  final String _amount = '₹159'; // You can specify amount or keep it flexible

  @override
  void dispose() {
    _transactionIdController.dispose();
    super.dispose();
  }

  Future<void> _submitPaymentRequest() async {
    final txId = _transactionIdController.text.trim();
    if (txId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Transaction ID')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Save request to Firestore
      await FirebaseFirestore.instance.collection('subscription_requests').add({
        'userId': user.uid,
        'userEmail': user.email,
        'transactionId': txId,
        'pending': true,
        'approved': false,
        'timestamp': FieldValue.serverTimestamp(),
        'method': 'upi_manual',
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request Submitted'),
          content: const Text(
              'Thank you! Your payment verification request has been submitted. '
              'Premium features will be unlocked once the admin verifies your transaction (usually within 24 hours).'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to previous screen
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to user's latest subscription request
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please login')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Premium'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('subscription_requests')
            .where('userId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          // Check if there is ANY approved request
          final activeSub = docs.firstWhereOrNull((d) => d['approved'] == true);

          // Check if there is a pending request (not approved)
          final pendingSub =
              docs.firstWhereOrNull((d) => d['approved'] != true);

          if (activeSub != null) {
            return _buildActiveSubscriptionView(activeSub);
          } else if (pendingSub != null) {
            return _buildPendingRequestView(pendingSub);
          } else {
            return _buildNewRequestForm(context); // Original Form
          }
        },
      ),
    );
  }

  Widget _buildActiveSubscriptionView(DocumentSnapshot doc) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified, size: 80, color: Colors.green),
          const SizedBox(height: 20),
          const Text('Premium Active',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('Transaction ID: ${doc['transactionId']}',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 30),
          const Text('Enjoy unlimited features & Ads Free experience!',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPendingRequestView(DocumentSnapshot doc) {
    final txId = doc['transactionId'];
    final docId = doc.id;

    return ResponsiveContainer(
      maxWidth: 800,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.pending_actions, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text('Verification Pending',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Your payment is being verified by the admin.',
                textAlign: TextAlign.center),
            const SizedBox(height: 30),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt),
                title: const Text('Transaction ID'),
                subtitle: Text(txId),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit ID'),
                  onPressed: () => _showEditDialog(docId, txId),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () => _confirmDelete(docId),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _showEditDialog(String docId, String currentId) {
    final controller = TextEditingController(text: currentId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Transaction ID'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Transaction ID'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newId = controller.text.trim();
              if (newId.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('subscription_requests')
                    .doc(docId)
                    .update({'transactionId': newId});
                // ignore: use_build_context_synchronously
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Request?'),
        content: const Text(
            'Are you sure you want to delete this verification request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // proper deletion with error handling
      try {
        await FirebaseFirestore.instance
            .collection('subscription_requests')
            .doc(docId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Widget _buildNewRequestForm(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return ResponsiveContainer(
      maxWidth: 800,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.indigoAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.deepPurple.withAlpha(80), // Using withAlpha(int)
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Icon(Icons.workspace_premium, size: 60, color: Colors.amber),
                  SizedBox(height: 10),
                  Text(
                    'Unlock Premium Features',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '• No Ads anywhere\n'
                    '• Unlimited Batches & Students\n'
                    '• Modify Batch Names\n'
                    '• Priority Support',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 16, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Payment Instructions
            Text(
              'Step 1: Pay via UPI',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  // QR Code Placeholder
                  Container(
                    height: 200,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/qr_code.jpeg', // User will provide this image
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, _, __) => const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code_2,
                                  size: 50, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('QR Code',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'UPI ID:',
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    _upiId,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // PAY NOW BUTTON
                  const Text(
                    'Select Payment App:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildAppButton('GPay', Colors.blue,
                          'tez://upi/pay?pa=$_upiId&pn=Edutracker&am=159.00&cu=INR'),
                      _buildAppButton('PhonePe', Colors.deepPurple,
                          'phonepe://pay?pa=$_upiId&pn=Edutracker&am=159.00&cu=INR'),
                      _buildAppButton('Paytm', Colors.indigo,
                          'paytmmp://pay?pa=$_upiId&pn=Edutracker&am=159.00&cu=INR'),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(26), // 0.1 opacity
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.amber.withAlpha(128)), // 0.5 opacity
                    ),
                    child: const Text(
                      '⚠️ If buttons don\'t work:\n1. Take a screenshot of this QR Code.\n2. Open any UPI App (GPay/PhonePe/Paytm).\n3. Scan the screenshot.\n4. Pay and enter Transaction ID below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Verification Input
            Text(
              'Step 2: Enter Transaction Details',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _transactionIdController,
              decoration: InputDecoration(
                labelText: 'Transaction ID / UTR Number',
                hintText: 'e.g., 3456xxxxxx',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.receipt_long),
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: _isLoading ? null : _submitPaymentRequest,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.deepPurple.withAlpha(100),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Submit Verification Request',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Note: This is a manual verification process. Please allow some time for activation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppButton(String label, Color color, String uriString) {
    return ElevatedButton(
      onPressed: () => _launchSpecificURI(uriString),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(label),
    );
  }

  Future<void> _launchSpecificURI(String uriString) async {
    final uri = Uri.parse(uriString);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $uriString';
      }
    } catch (e) {
      if (!mounted) return;
      // Fallback to generic UPI if specific scheme fails? Or just show error as requested by user ("jodi egulo na khole")
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not open app. Please use the QR Code screenshot method.')),
      );
    }
  }
}
