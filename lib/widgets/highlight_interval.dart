import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';

const Color kHighlightGold = Color(0xFFFFC107);
const Color kHighlightPink = Color(0xFFFF1493);

class HighlightCrown extends StatelessWidget {
  const HighlightCrown({super.key, this.size = 13});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text('👑', style: TextStyle(fontSize: size, height: 1));
  }
}

class IntervalChipLabel extends StatelessWidget {
  const IntervalChipLabel({
    super.key,
    required this.label,
    this.isHighlight = false,
  });

  final String label;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (isHighlight) ...[
          const SizedBox(width: 4),
          const HighlightCrown(size: 12),
        ],
      ],
    );
  }
}

class ChorusContainsBadge extends StatelessWidget {
  const ChorusContainsBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: kHighlightGold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kHighlightGold.withValues(alpha: 0.7)),
      ),
      child: Text(
        'common.contains_chorus'.tr(),
        style: TextStyle(
          color: LoopiColors.deepPurple,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
