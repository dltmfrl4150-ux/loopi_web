import 'package:flutter/material.dart';

/// Opens [page] with no slide.
///
/// CanvasKit crashes with a shader compilation error when a [MaterialPageRoute]
/// animation is composited over a YouTube iframe (`HtmlElementView`).
PageRouteBuilder<T> instantPlayerRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}
