import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import '../widgets/cached_remote_image.dart';
import 'paywall_screen.dart';
import 'social_login_screen.dart';
import 'user_profile_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    required this.userState,
    required this.library,
    this.onSignedOut,
    this.onOpenUserFeed,
  });

  final UserSubscriptionState userState;
  final RoutineLibrary library;
  final Future<void> Function()? onSignedOut;
  final void Function(String authorId, String authorName)? onOpenUserFeed;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final DatabaseService _database = DatabaseService();
  final AuthService _auth = AuthService();
  bool _uploadingPhoto = false;
  UserSubscriptionState get _userState => widget.userState;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _userState.nickname);
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('profile.nickname_title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: 'profile.nickname_hint'.tr(),
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('common.cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || !mounted) return;
    final uid = _userState.uid;
    if (uid == null || uid.isEmpty || _userState.isGuest) {
      _userState.setNickname(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.nickname_updated'.tr())),
      );
      return;
    }
    final ok = await _database.updateUserNickname(uid: uid, nickname: next);
    if (!mounted) return;
    if (ok) {
      _userState.setNickname(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.nickname_saved'.tr())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.nickname_failed'.tr())),
      );
    }
  }

  Future<void> _pickProfilePhoto() async {
    final uid = _userState.uid;
    if (uid == null || uid.isEmpty || _userState.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.photo_login'.tr())),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 50,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw StateError('empty image');
      final url = await StorageService.uploadAvatar(userId: uid, bytes: bytes);
      if (url == null) throw StateError('upload failed');
      await _auth.updatePhotoUrl(url);
      final ok = await _database.updateUserPhotoUrl(uid: uid, photoUrl: url);
      if (!mounted) return;
      if (ok) {
        _userState.setPhotoUrl(url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile.photo_updated'.tr())),
        );
      } else {
        throw StateError('profile write failed');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile.photo_failed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _openLanguageDialog() async {
    final current = context.locale;
    final selected = await showDialog<Locale>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings.language'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(current.languageCode == 'ko' ? Icons.check_circle : Icons.circle_outlined, color: LoopiColors.purple),
              title: Text('settings.korean'.tr()),
              onTap: () => Navigator.pop(dialogContext, const Locale('ko')),
            ),
            ListTile(
              leading: Icon(current.languageCode == 'en' ? Icons.check_circle : Icons.circle_outlined, color: LoopiColors.purple),
              title: Text('settings.english'.tr()),
              onTap: () => Navigator.pop(dialogContext, const Locale('en')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('common.cancel'.tr())),
        ],
      ),
    );
    if (selected == null || !mounted || selected == current) return;
    await context.setLocale(selected);
  }

  Future<void> _openOwnFeed() async {
    final uid = _userState.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.feed_login'.tr())),
      );
      return;
    }
    if (widget.onOpenUserFeed != null) {
      widget.onOpenUserFeed!(uid, _userState.nickname);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          authorId: uid,
          authorName: _userState.nickname,
          library: widget.library,
          userState: widget.userState,
        ),
      ),
    );
  }

  Future<void> _openSubscriptionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: _userState,
        builder: (context, _) {
          final isPro = _userState.isPro;
          return AlertDialog(
            title: Text('profile.my_subscription'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: isPro
                  ? [
                      Text('profile.plan_pro'.tr(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 12),
                      _infoRow('profile.next_billing'.tr(), _userState.nextBillingDate != null ? _formatDate(_userState.nextBillingDate!) : '-'),
                      const SizedBox(height: 6),
                      _infoRow('profile.payment_method'.tr(), _userState.paymentMethod),
                    ]
                  : [
                      Text('profile.plan_free'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Text('profile.upgrade_hint'.tr(), style: TextStyle(color: LoopiColors.muted)),
                    ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('common.close'.tr())),
              if (isPro)
                TextButton(
                  onPressed: () => _confirmCancelSubscription(dialogContext),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: Text('profile.cancel_subscription'.tr()),
                )
              else
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => ProUpgradeScreen(userState: _userState)),
                    );
                  },
                  style: FilledButton.styleFrom(backgroundColor: LoopiColors.deepPurple),
                  child: Text('profile.upgrade'.tr()),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmCancelSubscription(BuildContext dialogContext) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (confirmContext) => AlertDialog(
        title: Text('profile.cancel_subscription_title'.tr()),
        content: Text('profile.cancel_subscription_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: Text('common.no'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('profile.cancel_subscription'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _userState.cancelSubscription();
      if (dialogContext.mounted) Navigator.pop(dialogContext);
    }
  }

  Future<void> _openContactDialog() async {
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('profile.contact'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: InputDecoration(labelText: 'profile.contact_subject'.tr()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: InputDecoration(labelText: 'profile.contact_message'.tr(), alignLabelWithHint: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('common.cancel'.tr())),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('profile.contact_sent'.tr())),
              );
            },
            child: Text('profile.contact_send'.tr()),
          ),
        ],
      ),
    );
    subjectController.dispose();
    messageController.dispose();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('profile.logout_confirm'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('common.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('profile.logout'.tr())),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (widget.onSignedOut != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        await widget.onSignedOut!();
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => SocialLoginScreen(library: widget.library, userState: widget.userState),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _confirmWithdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('profile.delete_account_title'.tr()),
        content: Text('profile.delete_account_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('common.cancel'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('profile.delete_account_action'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('profile.delete_account_done'.tr())));
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: LoopiColors.muted)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _userState,
      builder: (context, _) {
        final isPro = _userState.isPro;
        return Scaffold(
          backgroundColor: LoopiColors.pageBackground(context),
          appBar: AppBar(
            title: Text('profile.title'.tr()),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.of(context).pop();
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _profileCard(isPro),
              const SizedBox(height: 24),
              _sectionLabel('profile.section_account'.tr()),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Text('👤', style: TextStyle(fontSize: 20)),
                      title: Text('profile.login_info'.tr()),
                      subtitle: Text('profile.login_linked'.tr(namedArgs: {
                        'email': _userState.email,
                        'provider': _userState.socialProvider,
                      })),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.grid_view_rounded, color: LoopiColors.purple),
                      title: Text('profile.my_feed'.tr()),
                      subtitle: Text('profile.my_feed_subtitle'.tr()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openOwnFeed,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Text('💳', style: TextStyle(fontSize: 20)),
                      title: Text('profile.my_subscription'.tr()),
                      subtitle: Text(isPro ? 'profile.plan_pro_short'.tr() : 'profile.plan_free_short'.tr()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openSubscriptionDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('settings.title'.tr()),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.language, color: LoopiColors.purple),
                  title: Text('settings.language'.tr()),
                  subtitle: Text(
                    '${'settings.language_subtitle'.tr()} · ${context.locale.languageCode == 'ko' ? 'settings.korean'.tr() : 'settings.english'.tr()}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openLanguageDialog,
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('profile.section_faqs'.tr()),
              Card(
                child: Column(
                  children: [
                    _faqTile('profile.faq_backup_q'.tr(), 'profile.faq_backup_a'.tr()),
                    const Divider(height: 1),
                    _faqTile('profile.faq_cancel_q'.tr(), 'profile.faq_cancel_a'.tr()),
                    const Divider(height: 1),
                    _faqTile('profile.faq_offline_q'.tr(), 'profile.faq_offline_a'.tr()),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('profile.section_support'.tr()),
              Card(
                child: ListTile(
                  leading: const Text('✉️', style: TextStyle(fontSize: 20)),
                  title: Text('profile.contact'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openContactDialog,
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    TextButton(onPressed: _confirmLogout, child: Text('profile.logout'.tr(), style: TextStyle(color: LoopiColors.muted))),
                    TextButton(
                      onPressed: _confirmWithdraw,
                      child: Text('profile.delete_account'.tr(), style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text, style: TextStyle(color: LoopiColors.muted, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }

  Widget _faqTile(String question, String answer) {
    return ExpansionTile(
      leading: const Text('❓', style: TextStyle(fontSize: 20)),
      title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(answer, style: TextStyle(color: LoopiColors.muted, height: 1.4)),
      ],
    );
  }

  Widget _profileCard(bool isPro) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LoopiColors.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LoopiColors.divider(context)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'profile.photo_upload'.tr(),
            child: GestureDetector(
            onTap: _uploadingPhoto ? null : _pickProfilePhoto,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: LoopiColors.purple.withValues(alpha: 0.15),
                  child: _uploadingPhoto
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: LoopiColors.purple),
                        )
                      : ClipOval(
                          child: _userState.photoUrl == null || _userState.photoUrl!.isEmpty
                              ? const Icon(Icons.person, size: 36, color: LoopiColors.purple)
                              : CachedRemoteImage(
                                  url: _userState.photoUrl!,
                                  width: 64,
                                  height: 64,
                                  memCacheWidth: 128,
                                ),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: LoopiColors.deepPurple, shape: BoxShape.circle),
                  child: const Icon(Icons.photo_camera, size: 12, color: Colors.white),
                ),
              ],
            ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userState.nickname, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  'profile.nickname_display'.tr(namedArgs: {'name': _userState.nickname}),
                  style: TextStyle(color: LoopiColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                _PlanBadge(isPro: isPro),
              ],
            ),
          ),
          IconButton(
            tooltip: 'profile.nickname_edit'.tr(),
            onPressed: _editNickname,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isPro ? null : LoopiColors.line,
        gradient: isPro
            ? const LinearGradient(colors: [Color(0xFFFF3D9A), LoopiColors.purple])
            : null,
      ),
      child: Text(
        isPro ? 'PRO' : 'FREE',
        style: TextStyle(
          color: isPro ? Colors.white : LoopiColors.muted,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
