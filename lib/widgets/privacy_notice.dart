import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/legal_texts.dart';
import '../theme/loopi_colors.dart';

Future<void> showTermsOfServiceDialog(BuildContext context) {
  final lang = context.locale.languageCode;
  return _showScrollableLegalDialog(
    context: context,
    title: LegalTexts.termsTitle(lang),
    body: LegalTexts.termsOfServiceBody(lang),
  );
}

Future<void> showPrivacyPolicyDialog(BuildContext context) {
  final lang = context.locale.languageCode;
  return _showScrollableLegalDialog(
    context: context,
    title: LegalTexts.privacyTitle(lang),
    body: LegalTexts.privacyPolicyBody(lang),
  );
}

Future<void> _showScrollableLegalDialog({
  required BuildContext context,
  required String title,
  required String body,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _LegalTextScrollBody(body: body),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('common.close'.tr()),
        ),
      ],
    ),
  );
}

/// Owns a shared [ScrollController] so [Scrollbar] and [SingleChildScrollView]
/// stay in sync (avoids Web "no ScrollPosition attached" assertions).
class _LegalTextScrollBody extends StatefulWidget {
  const _LegalTextScrollBody({required this.body});

  final String body;

  @override
  State<_LegalTextScrollBody> createState() => _LegalTextScrollBodyState();
}

class _LegalTextScrollBodyState extends State<_LegalTextScrollBody> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: SelectableText(
          widget.body,
          style: const TextStyle(height: 1.5, fontSize: 13.5),
        ),
      ),
    );
  }
}

/// Muted caption under social login buttons with tappable legal links.
class LoginAuthLegalCaption extends StatefulWidget {
  const LoginAuthLegalCaption({super.key});

  @override
  State<LoginAuthLegalCaption> createState() => _LoginAuthLegalCaptionState();
}

class _LoginAuthLegalCaptionState extends State<LoginAuthLegalCaption> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = _openTerms;
    _privacyTap = TapGestureRecognizer()..onTap = _openPrivacy;
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _openTerms() => showTermsOfServiceDialog(context);

  void _openPrivacy() => showPrivacyPolicyDialog(context);

  @override
  Widget build(BuildContext context) {
    final muted = LoopiColors.textMuted(context);
    final linkStyle = TextStyle(
      color: LoopiColors.deepPurple,
      fontSize: 11,
      height: 1.4,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: LoopiColors.deepPurple.withValues(alpha: 0.6),
    );
    final baseStyle = TextStyle(color: muted, fontSize: 11, height: 1.4);

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: 'social_login.auth_consent_prefix'.tr()),
          TextSpan(text: 'social_login.terms_link'.tr(), style: linkStyle, recognizer: _termsTap),
          TextSpan(text: 'social_login.auth_consent_middle'.tr()),
          TextSpan(text: 'social_login.privacy_link'.tr(), style: linkStyle, recognizer: _privacyTap),
          TextSpan(text: 'social_login.auth_consent_suffix'.tr()),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
