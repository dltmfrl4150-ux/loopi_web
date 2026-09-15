import 'package:flutter/material.dart';

import '../utils/storage_quota.dart';

/// Shows the friendly local-storage-full nudge.
Future<void> showStorageQuotaNudge(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('저장 공간 부족'),
        content: const Text(kStorageQuotaNudgeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      );
    },
  );
}

void showStorageQuotaSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(kStorageQuotaNudgeMessage)),
  );
}