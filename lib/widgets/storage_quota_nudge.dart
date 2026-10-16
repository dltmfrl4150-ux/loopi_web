import 'package:flutter/material.dart';

import '../utils/storage_quota.dart';
import 'youtube_safe_dialog.dart';

/// Shows the friendly local-storage-full nudge.
Future<void> showStorageQuotaNudge(BuildContext context) {
  return showYoutubeSafeDialog<void>(
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