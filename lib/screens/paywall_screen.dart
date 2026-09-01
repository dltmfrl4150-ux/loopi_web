import 'package:flutter/material.dart';

import '../state/user_state.dart';
import '../theme/loopi_colors.dart';

/// Pro upgrade paywall: benefit list, monthly/yearly plan picker, and CTA.
class ProUpgradeScreen extends StatefulWidget {
  const ProUpgradeScreen({super.key, required this.userState});

  final UserSubscriptionState userState;

  @override
  State<ProUpgradeScreen> createState() => _ProUpgradeScreenState();
}

class _ProUpgradeScreenState extends State<ProUpgradeScreen> {
  String _planTerm = 'yearly';

  static const _benefits = [
    ('☁️', '무제한 고화질 클라우드 영상 보관', '기기 간 자동 동기화로 언제 어디서든 이어서 연습하세요.'),
    ('⏱️', '0.25x 정밀 슬로모션 & 오버레이 비교', '동작 하나하나를 놓치지 않는 초정밀 분석 모드.'),
    ('📱', '1초 숏폼 릴스/틱톡 규격 내보내기', '워터마크 커스텀까지 가능한 즉시 공유용 영상.'),
  ];

  Future<void> _startPro() async {
    widget.userState.upgradeToPro(_planTerm);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('루피 Pro가 활성화되었습니다!')),
    );
    Navigator.of(context).pop();
  }

  void _restorePurchase() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('복원할 구매 내역이 없습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoopiColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (Navigator.canPop(context)) Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  Text(
                    '루피 Pro로\n한계 없는 연습을 시작하세요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  for (final benefit in _benefits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(benefit.$1, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(benefit.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(benefit.$3, style: TextStyle(color: LoopiColors.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    selected: _planTerm == 'monthly',
                    title: '월간 플랜',
                    price: '월 4,900원',
                    onTap: () => setState(() => _planTerm = 'monthly'),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    selected: _planTerm == 'yearly',
                    title: '연간 플랜',
                    badge: '인기 · 25% 할인',
                    price: '연 45,000원 (월 3,750원 꼴)',
                    onTap: () => setState(() => _planTerm = 'yearly'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _startPro,
                      style: FilledButton.styleFrom(
                        backgroundColor: LoopiColors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('루피 Pro 시작하기', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  TextButton(
                    onPressed: _restorePurchase,
                    child: Text('구매 복원', style: TextStyle(color: LoopiColors.muted)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.selected,
    required this.title,
    required this.price,
    required this.onTap,
    this.badge,
  });

  final bool selected;
  final String title;
  final String price;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? LoopiColors.purple.withValues(alpha: 0.08) : Colors.white,
          border: Border.all(color: selected ? LoopiColors.purple : LoopiColors.line, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? LoopiColors.purple : LoopiColors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: LoopiColors.purple,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(price, style: TextStyle(color: LoopiColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
