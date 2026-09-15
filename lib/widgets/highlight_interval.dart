import 'package:flutter/material.dart';

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
    // Visual badge retired from list cards; keep widget for compatibility.
    // Underlying isHighlight / hasHighlight data and logic are unchanged.
    return const SizedBox.shrink();
  }
}
