import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';

/// Asks whether to reuse Firestore-cached practice sections for a YouTube video.
///
/// Returns `true` to load the cached routine, `false` to start fresh,
/// or `null` if the dialog was dismissed.
Future<bool?> showLoadCachedRoutineDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('저장된 루틴 불러오기'),
        content: const Text(
          '이 영상에 이미 설정된 연습 구간(루틴)이 있습니다. 그대로 가져오시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('새로 설정'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LoopiColors.deepPurple),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('가져오기'),
          ),
        ],
      );
    },
  );
}
