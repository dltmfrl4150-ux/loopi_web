import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';

class AgeDeclarationScreen extends StatelessWidget {
  const AgeDeclarationScreen({
    super.key,
    required this.onAdult,
    required this.onUnder14,
    required this.onSignOut,
  });

  final VoidCallback onAdult;
  final VoidCallback onUnder14;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoopiColors.pageBackground(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('profile.age_title'.tr(), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('profile.age_body'.tr()),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAdult, child: Text('profile.age_adult'.tr())),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onUnder14, child: Text('profile.age_under'.tr())),
            TextButton(onPressed: onSignOut, child: Text('profile.logout'.tr())),
          ],
        ),
      ),
    );
  }
}

class AccountRecoveryScreen extends StatelessWidget {
  const AccountRecoveryScreen({
    super.key,
    required this.purgeStarted,
    required this.anonymous,
    required this.onRestore,
    required this.onSignOut,
  });

  final bool purgeStarted;
  final bool anonymous;
  final VoidCallback? onRestore;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final title = purgeStarted ? 'profile.recovery_blocked_title'.tr() : 'profile.recovery_title'.tr();
    final body = purgeStarted ? 'profile.recovery_blocked_body'.tr() : 'profile.recovery_body'.tr();
    return Scaffold(
      backgroundColor: LoopiColors.pageBackground(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(body),
            if (anonymous && !purgeStarted) ...[
              const SizedBox(height: 12),
              Text('profile.recovery_guest'.tr()),
            ],
            const SizedBox(height: 24),
            if (!purgeStarted && onRestore != null)
              FilledButton(onPressed: onRestore, child: Text('profile.recovery_restore'.tr())),
            TextButton(onPressed: onSignOut, child: Text('profile.logout'.tr())),
          ],
        ),
      ),
    );
  }
}

class AccountStatusMessageScreen extends StatelessWidget {
  const AccountStatusMessageScreen({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoopiColors.pageBackground(context),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: Text('profile.retry'.tr())),
                TextButton(onPressed: onSignOut, child: Text('profile.logout'.tr())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
