import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Shows a dialog whose scrim and contents share one full-screen
/// [PointerInterceptor].
///
/// On Flutter web a YouTube iframe is a platform view drawn above the canvas.
/// An interceptor sized only to the dialog leaves the scrim over that iframe,
/// so outside clicks reach YouTube. This helper sizes the interceptor to the
/// overlay. Inside it, the scrim is painted first and the dialog is painted
/// after, so buttons win hit testing.
///
/// On platforms without the web implementation, [PointerInterceptor] returns
/// its child and does not recreate a player.
///
/// [barrierDismissible] matches [showDialog]: only a dismissible dialog closes
/// when the scrim is tapped. The route keeps the same flag so Escape follows
/// that setting.
Future<T?> showYoutubeSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool useSafeArea = true,
  Color? barrierColor,
  String? barrierLabel,
}) {
  final Color resolvedBarrier = barrierColor ??
      DialogTheme.of(context).barrierColor ??
      Theme.of(context).dialogTheme.barrierColor ??
      Colors.black54;
  final String resolvedLabel =
      barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel;

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: resolvedLabel,
    // The visible scrim is inside the interceptor. A second route scrim would
    // sit outside that layer and would not receive iframe clicks.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      Widget dialog = Builder(builder: builder);
      if (useSafeArea) {
        dialog = SafeArea(child: dialog);
      }
      return PointerInterceptor(
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              ModalBarrier(
                dismissible: barrierDismissible,
                color: resolvedBarrier,
                semanticsLabel: barrierDismissible ? resolvedLabel : null,
              ),
              dialog,
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
