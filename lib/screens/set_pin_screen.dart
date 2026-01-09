import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/lock_service.dart';
import '../app_globals.dart';

class SetPinScreen extends StatefulWidget {
  static const routeName = '/set-pin';
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    // Screen খোলার সাথে সাথেই keyboard উঠানোর ব্যবস্থা
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pinFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    setState(() {
      _errorText = null;
    });

    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() {
        _errorText = 'PIN must be exactly 4 digits.';
      });
      return;
    }
    if (pin != confirm) {
      setState(() {
        _errorText = 'PIN and confirmation do not match.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await LockService.setPin(pin);
      await LockService.setUseDeviceLock(false);

      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('4-digit PIN saved successfully.')),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Failed to save PIN: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final isReset = args is Map && args['isReset'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(isReset ? 'Set new PIN' : 'Set 4-digit PIN'),
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              focusNode: _pinFocusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            if (_errorText != null)
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isSaving ? null : _savePin,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save PIN'),
            ),
            const SizedBox(height: 12),
            if (!isReset)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('Cancel'),
              ),
          ],
        ),
      ),
    );
  }
}
