import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';

class FavoriteButton extends StatefulWidget {
  const FavoriteButton({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.tooltip,
  });

  final bool initialValue;
  final FutureOr<void> Function(bool value) onChanged;
  final String? tooltip;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  late bool _isFavorite = widget.initialValue;

  @override
  void didUpdateWidget(covariant FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _isFavorite = widget.initialValue;
    }
  }

  void _toggle() {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    
    // UI(보라색 하트)가 즉각적으로 먼저 렌더링되도록 실행 순서를 다음 프레임으로 양보
    Future.delayed(Duration.zero, () {
      widget.onChanged(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _toggle,
      tooltip: widget.tooltip ?? (_isFavorite ? '즐겨찾기 해제' : '즐겨찾기'),
      color: _isFavorite ? LoopiColors.purple : null,
      icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border),
    );
  }
}
