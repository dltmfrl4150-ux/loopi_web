import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

enum PlanType { free, pro }

/// Holds the signed-in user's profile and subscription/plan status.
class UserSubscriptionState extends ChangeNotifier {
  UserSubscriptionState({
    this.email = '',
    this.nickname = '루피 댄서',
    this.socialProvider = 'Guest',
    this.photoUrl,
  });

  String email;
  String nickname;
  String socialProvider;
  String? photoUrl;
  String? uid;
  bool isGuest = true;

  PlanType currentPlan = PlanType.free;
  DateTime? nextBillingDate;
  String paymentMethod = '';

  bool get isPro => currentPlan == PlanType.pro;

  void applyFirebaseUser({
    required String userId,
    required String userEmail,
    String? displayName,
    String? photoUrl,
    AuthProviderKind? provider,
    bool anonymous = false,
    /// When true, keep the existing Loopi nickname instead of overwriting
    /// with the social provider display name.
    bool preserveNickname = false,
  }) {
    uid = userId;
    email = userEmail;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      this.photoUrl = photoUrl;
    }
    if (!preserveNickname) {
      if (displayName != null && displayName.isNotEmpty) {
        nickname = displayName;
      } else if (anonymous) {
        nickname = '게스트';
      }
    } else if (anonymous && (nickname.isEmpty || nickname == '루피 댄서')) {
      nickname = '게스트';
    }
    isGuest = anonymous || provider == AuthProviderKind.guest;
    socialProvider = switch (provider) {
      AuthProviderKind.google => 'Google',
      AuthProviderKind.apple => 'Apple',
      AuthProviderKind.kakao => 'Kakao',
      AuthProviderKind.guest || null => anonymous ? 'Guest' : socialProvider,
    };
    notifyListeners();
  }

  void setNickname(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == nickname) return;
    nickname = trimmed;
    notifyListeners();
  }

  void setPhotoUrl(String? value) {
    final next = value?.trim();
    if (next == photoUrl) return;
    photoUrl = (next == null || next.isEmpty) ? null : next;
    notifyListeners();
  }

  void setGuest() {
    uid = null;
    isGuest = true;
    socialProvider = 'Guest';
    email = '';
    nickname = '게스트';
    photoUrl = null;
    notifyListeners();
  }

  void upgradeToPro(String planTerm) {
    currentPlan = PlanType.pro;
    final months = planTerm == 'yearly' ? 12 : 1;
    nextBillingDate = DateTime.now().add(Duration(days: 30 * months));
    paymentMethod = '카카오페이 / 45**-****';
    notifyListeners();
  }

  void cancelSubscription() {
    currentPlan = PlanType.free;
    nextBillingDate = null;
    paymentMethod = '';
    notifyListeners();
  }
}
