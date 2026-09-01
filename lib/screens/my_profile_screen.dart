import 'package:flutter/material.dart';

import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import 'paywall_screen.dart';
import 'social_login_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, required this.userState, required this.library});

  final UserSubscriptionState userState;
  final RoutineLibrary library;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  UserSubscriptionState get _userState => widget.userState;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _openSubscriptionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: _userState,
        builder: (context, _) {
          final isPro = _userState.isPro;
          return AlertDialog(
            title: const Text('나의 구독'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: isPro
                  ? [
                      const Text('루피 Pro 이용 중', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 12),
                      _infoRow('다음 결제일', _userState.nextBillingDate != null ? _formatDate(_userState.nextBillingDate!) : '-'),
                      const SizedBox(height: 6),
                      _infoRow('결제 수단', _userState.paymentMethod),
                    ]
                  : [
                      const Text('현재 Free 플랜 이용 중', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Text('Pro로 업그레이드하고 무제한 기능을 사용해보세요.', style: TextStyle(color: LoopiColors.muted)),
                    ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('닫기')),
              if (isPro)
                TextButton(
                  onPressed: () => _confirmCancelSubscription(dialogContext),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: const Text('구독 해제'),
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
                  child: const Text('Pro 플랜 업그레이드'),
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
        title: const Text('구독을 해제할까요?'),
        content: const Text('구독을 해제하면 다음 결제일부터 Free 플랜으로 전환됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('아니오')),
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('구독 해제'),
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
        title: const Text('1:1 문의'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '문의 내용', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('문의가 접수되었습니다. 빠르게 답변드릴게요!')),
              );
            },
            child: const Text('문의 보내기'),
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
        title: const Text('로그아웃 하시겠어요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('로그아웃')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => SocialLoginScreen(library: widget.library)),
        (route) => false,
      );
    }
  }

  Future<void> _confirmWithdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('정말 탈퇴하시겠어요?'),
        content: const Text('탈퇴 시 저장된 루틴과 연습 기록이 모두 삭제되며 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('회원 탈퇴가 접수되었습니다.')));
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
          backgroundColor: LoopiColors.canvas,
          appBar: AppBar(
            title: const Text('내 정보'),
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
              _sectionLabel('계정 & 구독'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Text('👤', style: TextStyle(fontSize: 20)),
                      title: const Text('로그인 정보'),
                      subtitle: Text('${_userState.email} · ${_userState.socialProvider} 연동됨'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Text('💳', style: TextStyle(fontSize: 20)),
                      title: const Text('나의 구독'),
                      subtitle: Text(isPro ? 'Pro 이용 중' : 'Free 플랜 이용 중'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openSubscriptionDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('고객 지원'),
              Card(
                child: Column(
                  children: [
                    _faqTile('영상 백업은 어떻게 되나요?', 'Pro 플랜은 녹화 영상을 클라우드에 자동 백업해 기기 간 동기화됩니다. Free 플랜은 기기 내부에만 저장돼요.'),
                    const Divider(height: 1),
                    _faqTile('구독 취소 시 기존 영상은 유지되나요?', '네, 이미 저장된 영상과 루틴은 삭제되지 않습니다. 다만 Pro 전용 기능은 다음 결제일부터 이용할 수 없어요.'),
                    const Divider(height: 1),
                    _faqTile('오프라인에서도 연습 가능한가요?', '이미 기기에 저장된 루틴과 영상은 오프라인 상태에서도 연습 모드로 재생할 수 있습니다.'),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Text('✉️', style: TextStyle(fontSize: 20)),
                      title: const Text('1:1 문의'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openContactDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    TextButton(onPressed: _confirmLogout, child: Text('로그아웃', style: TextStyle(color: LoopiColors.muted))),
                    TextButton(
                      onPressed: _confirmWithdraw,
                      child: const Text('회원탈퇴', style: TextStyle(color: Colors.redAccent)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LoopiColors.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: LoopiColors.purple.withValues(alpha: 0.15),
            child: Icon(Icons.person, size: 36, color: LoopiColors.purple),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userState.nickname, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 6),
                _PlanBadge(isPro: isPro),
              ],
            ),
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
