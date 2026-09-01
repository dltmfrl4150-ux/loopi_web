import 'package:flutter/foundation.dart';

enum PlanType { free, pro }

/// Holds the signed-in user's profile and subscription/plan status.
class UserSubscriptionState extends ChangeNotifier {
  UserSubscriptionState({
    this.email = 'dancer_loopi@gmail.com',
    this.nickname = '루피 댄서',
    this.socialProvider = 'Google',
  });

  final String email;
  final String nickname;
  final String socialProvider;

  PlanType currentPlan = PlanType.free;
  DateTime? nextBillingDate;
  String paymentMethod = '';

  bool get isPro => currentPlan == PlanType.pro;

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
