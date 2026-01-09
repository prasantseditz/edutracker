import 'package:flutter/material.dart';

Future<bool?> showConfirmationDialog(
  BuildContext context,
  String message, {
  String confirmText = 'Yes',
  String cancelText = 'No',
  bool isDestructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Confirmation'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: Text(cancelText),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            style: isDestructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
}
