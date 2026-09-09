import 'package:flutter/material.dart';

/// Provides a close callback for screens shown inside the home shell
/// (bottom navigation stays visible).
class ShellCloseScope extends InheritedWidget {
  const ShellCloseScope({
    super.key,
    required this.close,
    required super.child,
  });

  final VoidCallback close;

  static VoidCallback? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellCloseScope>()?.close;
  }

  @override
  bool updateShouldNotify(ShellCloseScope oldWidget) => close != oldWidget.close;
}

void closeShellOrPop(BuildContext context) {
  final close = ShellCloseScope.maybeOf(context);
  if (close != null) {
    close();
    return;
  }
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}
