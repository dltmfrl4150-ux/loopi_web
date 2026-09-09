import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import 'home_dashboard_screen.dart';
import 'social_login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.library,
    required this.userState,
  });

  final RoutineLibrary library;
  final UserSubscriptionState userState;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  final DatabaseService _database = DatabaseService();
  bool _localGuest = false;
  bool _loadingLibrary = false;
  String? _boundUid;

  Future<void> _bindUser(User user, {AuthProviderKind? provider}) async {
    if (_boundUid == user.uid && !_loadingLibrary) return;
    _boundUid = user.uid;
    final kind = provider ?? _providerFromUser(user);
    widget.userState.applyFirebaseUser(
      userId: user.uid,
      userEmail: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      provider: kind,
      anonymous: user.isAnonymous,
      preserveNickname: true,
    );
    setState(() => _loadingLibrary = true);
    final nickname = await _database.ensureUserProfile(
      uid: user.uid,
      email: user.email,
      authDisplayName: user.isAnonymous ? '게스트' : user.displayName,
    );
    widget.userState.setNickname(nickname);
    final photoUrl = await _database.fetchUserPhotoUrl(user.uid);
    if (photoUrl != null && photoUrl.isNotEmpty) {
      widget.userState.setPhotoUrl(photoUrl);
    }
    await widget.library.attachUser(user.uid);
    if (mounted) setState(() => _loadingLibrary = false);
  }

  AuthProviderKind _providerFromUser(User user) {
    if (user.isAnonymous) return AuthProviderKind.guest;
    for (final info in user.providerData) {
      switch (info.providerId) {
        case 'google.com':
          return AuthProviderKind.google;
        case 'apple.com':
          return AuthProviderKind.apple;
        case 'oidc.kakao':
          return AuthProviderKind.kakao;
      }
    }
    return AuthProviderKind.guest;
  }

  Future<void> _enterLocalGuest() async {
    widget.userState.setGuest();
    widget.library.detachUser();
    if (mounted) setState(() => _localGuest = true);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    widget.library.detachUser();
    widget.userState.setGuest();
    _boundUid = null;
    if (mounted) setState(() => _localGuest = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_localGuest) {
      return HomeDashboardScreen(
        library: widget.library,
        userState: widget.userState,
        onSignedOut: _signOut,
      );
    }

    if (!FirebaseBootstrap.initialized) {
      return SocialLoginScreen(
        library: widget.library,
        userState: widget.userState,
        onContinueAsGuest: _enterLocalGuest,
      );
    }

    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const _AuthLoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          return SocialLoginScreen(
            library: widget.library,
            userState: widget.userState,
            onContinueAsGuest: _enterLocalGuest,
          );
        }

        if (_boundUid != user.uid || _loadingLibrary) {
          if (_boundUid != user.uid) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _bindUser(user);
            });
          }
          return const _AuthLoadingScreen();
        }

        return HomeDashboardScreen(
          library: widget.library,
          userState: widget.userState,
          onSignedOut: _signOut,
        );
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoopiColors.pageBackground(context),
      body: const Center(
        child: CircularProgressIndicator(color: LoopiColors.purple),
      ),
    );
  }
}
