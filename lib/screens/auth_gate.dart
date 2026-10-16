import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../account/account_policy.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import 'account_gate_screens.dart';
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

enum _AccountHold { none, age, pending, blocked, unread }

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  final DatabaseService _database = DatabaseService();
  bool _localGuest = false;
  bool _loadingLibrary = false;
  String? _boundUid;
  _AccountHold _hold = _AccountHold.none;
  bool _anonymous = false;

  Future<void> _bindUser(User user, {AuthProviderKind? provider}) async {
    if (_boundUid == user.uid) return;
    _boundUid = user.uid;
    _anonymous = user.isAnonymous;
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
    final account = await _database.fetchPrivateAccount(user.uid);
    if (!mounted || _boundUid != user.uid) return;
    if (account.readFailed) {
      setState(() {
        _hold = _AccountHold.unread;
        _loadingLibrary = false;
      });
      return;
    }
    if (account.isPurgeStarted) {
      setState(() {
        _hold = _AccountHold.blocked;
        _loadingLibrary = false;
      });
      return;
    }
    if (account.isPendingDeletion) {
      setState(() {
        _hold = _AccountHold.pending;
        _loadingLibrary = false;
      });
      return;
    }
    if (requiresAgeDeclaration(
      isAnonymous: user.isAnonymous,
      hasAdultDeclaration: account.hasAdultDeclaration,
    )) {
      setState(() {
        _hold = _AccountHold.age;
        _loadingLibrary = false;
      });
      return;
    }
    await _enterHome(user);
  }

  Future<void> _enterHome(User user) async {
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
    if (!mounted) return;
    setState(() {
      _hold = _AccountHold.none;
      _loadingLibrary = false;
    });
  }

  Future<void> _declareAdult(User user) async {
    final ok = await _database.declareAdult(user.uid);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.age_failed'.tr())),
      );
      return;
    }
    setState(() => _loadingLibrary = true);
    await _enterHome(user);
  }

  Future<void> _stopUnder14(User user) async {
    if (_auth.currentUser?.uid == user.uid) {
      await _auth.deleteCurrentUser();
    }
    await _signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('profile.age_under_result'.tr())),
    );
  }

  Future<void> _restore(User user) async {
    final decision = await _database.restoreAccount(user.uid);
    if (!mounted) return;
    if (decision != RestoreDecision.allow) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('profile.recovery_failed'.tr())),
      );
      if (decision == RestoreDecision.purgeStarted) {
        setState(() => _hold = _AccountHold.blocked);
      }
      return;
    }
    setState(() {
      _boundUid = null;
      _hold = _AccountHold.none;
      _loadingLibrary = true;
    });
    await _bindUser(user);
  }

  Future<void> _onDeletionRequested() async {
    if (!mounted) return;
    setState(() => _hold = _AccountHold.pending);
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
    await widget.library.detachUser();
    if (mounted) {
      setState(() {
        _localGuest = true;
        _hold = _AccountHold.none;
        _boundUid = null;
      });
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    await widget.library.detachUser();
    widget.userState.setGuest();
    _boundUid = null;
    if (mounted) {
      setState(() {
        _localGuest = false;
        _hold = _AccountHold.none;
        _anonymous = false;
      });
    }
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

        if (_hold == _AccountHold.age) {
          return AgeDeclarationScreen(
            onAdult: () => _declareAdult(user),
            onUnder14: () => _stopUnder14(user),
            onSignOut: _signOut,
          );
        }
        if (_hold == _AccountHold.pending || _hold == _AccountHold.blocked) {
          return AccountRecoveryScreen(
            purgeStarted: _hold == _AccountHold.blocked,
            anonymous: _anonymous,
            onRestore: _hold == _AccountHold.pending ? () => _restore(user) : null,
            onSignOut: _signOut,
          );
        }
        if (_hold == _AccountHold.unread) {
          return AccountStatusMessageScreen(
            message: 'profile.read_failed'.tr(),
            onRetry: () {
              setState(() => _boundUid = null);
              _bindUser(user);
            },
            onSignOut: _signOut,
          );
        }

        return HomeDashboardScreen(
          library: widget.library,
          userState: widget.userState,
          onSignedOut: _signOut,
          onDeletionRequested: _onDeletionRequested,
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
