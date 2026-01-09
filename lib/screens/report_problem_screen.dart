import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final TextEditingController _bodyController = TextEditingController();
  final String _supportEmail = 'tokjhalhasi@gmail.com';
  bool _sending = false;

  static const MethodChannel _channel = MethodChannel('com.edutracker/mail');

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<bool> _openGmailNative({
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      final bool result = await _channel.invokeMethod<bool>(
            'composeEmail',
            <String, dynamic>{
              'to': to,
              'subject': subject,
              'body': body,
            },
          ) ??
          false;
      return result;
    } on PlatformException catch (e) {
      debugPrint('PlatformException while opening mail: $e');
      return false;
    } catch (e) {
      debugPrint('Unknown error while calling native mail: $e');
      return false;
    }
  }

  Future<void> _sendReport() async {
    if (!mounted) return;
    final text = _bodyController.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the problem before sending.')),
      );
      return;
    }

    final subject = 'EduTrack Report — App Version: (auto-detected)';
    final to = _supportEmail;
    final body = text;

    setState(() => _sending = true);
    final opened = await _openGmailNative(to: to, subject: subject, body: body);

    if (!mounted) return;
    setState(() => _sending = false);

    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening email app...')),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: 'To: $to\nSubject: $subject\n\n$body'));
      if (!mounted) return;

      unawaited(showDialog(
        context: context,
        builder: (ctx) {
          if (!mounted) return const SizedBox.shrink();
          return AlertDialog(
            title: const Text('Could not open mail app'),
            content: const Text(
              'We could not open the email app on your device.\n\n'
              'The report content has been copied to your clipboard.\n\n'
              'Please open your email app, paste the copied text, and send it to the support email.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ));
    }
  }

  Future<void> _copyEmailToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Support email copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Report a Problem')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Describe the problem here',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _bodyController,
                maxLines: null,
                expands: true,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText:
                      'Please write details of the issue, steps to reproduce, device info, and screenshots (if any)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Support email: $_supportEmail',
                      style: const TextStyle(fontSize: 14)),
                ),
                ElevatedButton.icon(
                  onPressed: _copyEmailToClipboard,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy email'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _sendReport,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Send Report (open email app)'),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
