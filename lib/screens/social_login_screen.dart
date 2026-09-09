import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../services/auth_service.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import '../widgets/app_logo.dart';
import 'home_dashboard_screen.dart';

class SocialLoginScreen extends StatefulWidget {
  const SocialLoginScreen({
    super.key,
    required this.library,
    this.userState,
    this.onContinueAsGuest,
    this.onAuthSuccess,
  });

  final RoutineLibrary library;
  final UserSubscriptionState? userState;

  /// Called when guest login should bypass Firebase (e.g. Firebase not ready).
  final Future<void> Function()? onContinueAsGuest;

  /// Optional hook after a successful social/guest Firebase sign-in.
  final void Function(AuthProviderKind provider)? onAuthSuccess;

  @override
  State<SocialLoginScreen> createState() => _SocialLoginScreenState();
}

class _SocialLoginScreenState extends State<SocialLoginScreen> {
  final _auth = AuthService();
  bool _loading = false;
  AuthProviderKind? _busyProvider;
  String? _error;

  Future<void> _runAuth(
    AuthProviderKind kind,
    Future<AuthResult> Function() action, {
    bool allowLocalGuestFallback = false,
  }) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _busyProvider = kind;
      _error = null;
    });

    if (!FirebaseBootstrap.initialized && allowLocalGuestFallback) {
      if (widget.onContinueAsGuest != null) {
        await widget.onContinueAsGuest!();
      } else {
        widget.userState?.setGuest();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => HomeDashboardScreen(
              library: widget.library,
              userState: widget.userState ?? UserSubscriptionState(),
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _busyProvider = null;
        });
      }
      return;
    }

    final result = await action();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _busyProvider = null;
    });

    if (!result.isSuccess) {
      setState(() => _error = result.errorMessage);
      return;
    }

    widget.userState?.applyFirebaseUser(
      userId: result.user!.uid,
      userEmail: result.user!.email ?? '',
      displayName: result.user!.displayName,
      provider: kind,
      anonymous: result.user!.isAnonymous,
    );
    widget.onAuthSuccess?.call(kind);
  }

  Future<void> _continueAsGuest() {
    return _runAuth(
      AuthProviderKind.guest,
      _auth.signInAnonymously,
      allowLocalGuestFallback: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background = LoopiColors.pageBackground(context);
    final panel = LoopiColors.card(context);
    final textPrimary = LoopiColors.text(context);
    final textMuted = LoopiColors.textMuted(context);
    final outline = LoopiColors.divider(context);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const AppLogo(height: 72),
                  const SizedBox(height: 16),
                  Text(
                    'social_login.title'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _SocialButton(
                    label: 'social_login.login_guest'.tr(),
                    backgroundColor: LoopiColors.deepPurple,
                    foregroundColor: Colors.white,
                    icon: Icons.person_outline_rounded,
                    loading: _loading && _busyProvider == AuthProviderKind.guest,
                    onPressed: _loading ? null : _continueAsGuest,
                  ),
                  const SizedBox(height: 12),
                  _SocialButton(
                    label: 'social_login.login_kakao'.tr(),
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: const Color(0xFF191600),
                    icon: Icons.chat_bubble,
                    loading: _loading && _busyProvider == AuthProviderKind.kakao,
                    onPressed: _loading
                        ? null
                        : () => _runAuth(AuthProviderKind.kakao, _auth.signInWithKakao),
                  ),
                  const SizedBox(height: 12),
                  _SocialButton(
                    label: 'social_login.login_google'.tr(),
                    backgroundColor: panel,
                    foregroundColor: textPrimary,
                    icon: Icons.g_mobiledata,
                    outlined: true,
                    outlineColor: outline,
                    loading: _loading && _busyProvider == AuthProviderKind.google,
                    onPressed: _loading
                        ? null
                        : () => _runAuth(AuthProviderKind.google, _auth.signInWithGoogle),
                  ),
                  const SizedBox(height: 12),
                  _SocialButton(
                    label: 'social_login.login_apple'.tr(),
                    backgroundColor: isLight ? Colors.black : panel,
                    foregroundColor: Colors.white,
                    icon: Icons.apple,
                    outlined: !isLight,
                    outlineColor: outline,
                    loading: _loading && _busyProvider == AuthProviderKind.apple,
                    onPressed: _loading
                        ? null
                        : () => _runAuth(AuthProviderKind.apple, _auth.signInWithApple),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'social_login.terms_agreement'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
    this.outlineColor,
    this.loading = false,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final Color? outlineColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: foregroundColor,
                ),
              )
            : Icon(icon, size: 23),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.7),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.7),
          elevation: 0,
          side: outlined ? BorderSide(color: outlineColor ?? const Color(0xFF35353E)) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
