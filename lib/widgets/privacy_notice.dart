import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';
import '../utils/privacy_prefs.dart';

String privacyRecordingDisclaimer([BuildContext? context]) {
  final code = context == null
      ? 'ko'
      : EasyLocalization.of(context)?.locale.languageCode ?? 'ko';
  return code == 'en'
      ? kPrivacyRecordingDisclaimerEn
      : kPrivacyRecordingDisclaimerKo;
}

/// First-launch (or until acknowledged) privacy dialog.
Future<void> maybeShowPrivacyNoticeDialog(BuildContext context) async {
  final done = await isPrivacyAcknowledged();
  if (done || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('privacy.title'.tr()),
        content: SingleChildScrollView(
          child: Text(privacyRecordingDisclaimer(dialogContext)),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              await setPrivacyAcknowledged();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text('privacy.acknowledge'.tr()),
          ),
        ],
      );
    },
  );
}

/// Compact footer / settings copy for the recording privacy policy.
class PrivacyDisclaimerText extends StatelessWidget {
  const PrivacyDisclaimerText({
    super.key,
    this.textAlign = TextAlign.center,
    this.fontSize = 11,
  });

  final TextAlign textAlign;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      privacyRecordingDisclaimer(context),
      textAlign: textAlign,
      style: TextStyle(
        color: LoopiColors.textMuted(context),
        fontSize: fontSize,
        height: 1.35,
      ),
    );
  }
}

/// Login checkbox requiring acknowledgment before continuing.
class PrivacyAgreementCheckbox extends StatelessWidget {
  const PrivacyAgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        'privacy.login_checkbox'.tr(),
        style: TextStyle(
          color: LoopiColors.textMuted(context),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}