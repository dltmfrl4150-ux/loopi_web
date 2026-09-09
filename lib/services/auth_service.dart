import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Tracks whether [Firebase.initializeApp] completed successfully.
class FirebaseBootstrap {
  static bool initialized = false;
}

enum AuthProviderKind { guest, google, apple, kakao }

class AuthResult {
  const AuthResult.success(this.user, {this.provider}) : errorMessage = null;
  const AuthResult.failure(this.errorMessage) : user = null, provider = null;

  final User? user;
  final String? errorMessage;
  final AuthProviderKind? provider;

  bool get isSuccess => user != null;
}

class AuthService {
  AuthService({FirebaseAuth? auth}) : _authOverride = auth;

  final FirebaseAuth? _authOverride;

  /// Firebase Console → Authentication → Sign-in method → OpenID Connect
  /// provider id for Kakao (configure as `oidc.kakao`).
  static const String kakaoOidcProviderId = 'oidc.kakao';

  FirebaseAuth? get _auth {
    if (!FirebaseBootstrap.initialized) return null;
    return _authOverride ?? FirebaseAuth.instance;
  }

  User? get currentUser => _auth?.currentUser;

  Stream<User?> authStateChanges() {
    final auth = _auth;
    if (auth == null) return const Stream<User?>.empty();
    return auth.authStateChanges();
  }

  Future<AuthResult> signInAnonymously() async {
    final auth = _auth;
    if (auth == null) {
      return const AuthResult.failure(_firebaseNotReadyMessage);
    }
    try {
      final credential = await auth.signInAnonymously();
      final user = credential.user;
      if (user == null) {
        return const AuthResult.failure('게스트 로그인에 실패했습니다. 다시 시도해 주세요.');
      }
      return AuthResult.success(user, provider: AuthProviderKind.guest);
    } on FirebaseAuthException catch (error) {
      return AuthResult.failure(_messageForCode(error.code));
    } catch (error) {
      debugPrint('Anonymous sign-in error: $error');
      return const AuthResult.failure('게스트 로그인 중 오류가 발생했습니다.');
    }
  }

  Future<AuthResult> signInWithGoogle() async {
    return _signInWithFederated(
      provider: GoogleAuthProvider()..addScope('email')..setCustomParameters({'prompt': 'select_account'}),
      kind: AuthProviderKind.google,
      failureFallback: 'Google 로그인에 실패했습니다.',
    );
  }

  Future<AuthResult> signInWithApple() async {
    final apple = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return _signInWithFederated(
      provider: apple,
      kind: AuthProviderKind.apple,
      failureFallback: 'Apple 로그인에 실패했습니다.',
    );
  }

  /// Kakao via Firebase OpenID Connect provider (`oidc.kakao`).
  /// Configure Kakao as an OIDC provider in Firebase Console, or replace this
  /// with a Cloud Function that exchanges a Kakao token for a custom token.
  Future<AuthResult> signInWithKakao() async {
    final kakao = OAuthProvider(kakaoOidcProviderId);
    return _signInWithFederated(
      provider: kakao,
      kind: AuthProviderKind.kakao,
      failureFallback: '카카오 로그인에 실패했습니다. Firebase OIDC(oidc.kakao) 설정을 확인해 주세요.',
    );
  }

  Future<AuthResult> signInWithKakaoCustomToken(String customToken) async {
    final auth = _auth;
    if (auth == null) {
      return const AuthResult.failure(_firebaseNotReadyMessage);
    }
    try {
      final credential = await auth.signInWithCustomToken(customToken);
      final user = credential.user;
      if (user == null) {
        return const AuthResult.failure('카카오 로그인에 실패했습니다.');
      }
      return AuthResult.success(user, provider: AuthProviderKind.kakao);
    } on FirebaseAuthException catch (error) {
      return AuthResult.failure(_messageForCode(error.code));
    } catch (error) {
      debugPrint('Kakao custom-token sign-in error: $error');
      return const AuthResult.failure('카카오 로그인 중 오류가 발생했습니다.');
    }
  }

  Future<bool> updatePhotoUrl(String photoUrl) async {
    final user = currentUser;
    if (user == null || photoUrl.trim().isEmpty) return false;
    try {
      await user.updatePhotoURL(photoUrl.trim());
      return true;
    } catch (error) {
      debugPrint('AuthService.updatePhotoUrl error: $error');
      return false;
    }
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) return;
    try {
      await auth.signOut();
    } catch (error) {
      debugPrint('Sign-out error: $error');
    }
  }

  Future<AuthResult> _signInWithFederated({
    required AuthProvider provider,
    required AuthProviderKind kind,
    required String failureFallback,
  }) async {
    final auth = _auth;
    if (auth == null) {
      return const AuthResult.failure(_firebaseNotReadyMessage);
    }
    try {
      final UserCredential credential;
      if (kIsWeb) {
        credential = await auth.signInWithPopup(provider);
      } else {
        credential = await auth.signInWithProvider(provider);
      }
      final user = credential.user;
      if (user == null) {
        return AuthResult.failure(failureFallback);
      }
      return AuthResult.success(user, provider: kind);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' || error.code == 'cancelled-popup-request') {
        return const AuthResult.failure('로그인이 취소되었습니다.');
      }
      return AuthResult.failure(_messageForCode(error.code));
    } catch (error) {
      debugPrint('Federated sign-in ($kind) error: $error');
      return AuthResult.failure(failureFallback);
    }
  }

  static const String _firebaseNotReadyMessage =
      'Firebase가 초기화되지 않았습니다. flutterfire configure를 실행해 주세요.';

  String _messageForCode(String code) {
    switch (code) {
      case 'operation-not-allowed':
        return '이 로그인 방식이 Firebase에서 활성화되어 있지 않습니다.';
      case 'account-exists-with-different-credential':
        return '같은 이메일로 다른 로그인 방식이 이미 연결되어 있습니다.';
      case 'user-disabled':
        return '비활성화된 계정입니다.';
      case 'too-many-requests':
        return '시도 횟수가 너무 많습니다. 잠시 후 다시 시도해 주세요.';
      case 'network-request-failed':
        return '네트워크 연결을 확인해 주세요.';
      case 'unauthorized-domain':
        return '이 도메인은 Firebase Auth에 허용되지 않았습니다.';
      default:
        debugPrint('Unhandled FirebaseAuthException: $code');
        return '로그인에 실패했습니다. ($code)';
    }
  }
}
