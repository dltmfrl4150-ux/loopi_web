import 'package:shared_preferences/shared_preferences.dart';

const String kPrivacyAckKey = 'loopi_privacy_acknowledged_v1';

const String kPrivacyRecordingDisclaimerKo =
    '본 서비스는 사용자의 댄스 연습 녹화 영상을 기기 내부에서만 처리하며, '
    '외부 서버로 절대 수집하거나 전송하지 않습니다.';

const String kPrivacyRecordingDisclaimerEn =
    'This service processes your recorded dance practice videos only on your '
    'local device and never collects or transmits them to external servers.';

Future<bool> isPrivacyAcknowledged() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kPrivacyAckKey) ?? false;
}

Future<void> setPrivacyAcknowledged({bool value = true}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kPrivacyAckKey, value);
}