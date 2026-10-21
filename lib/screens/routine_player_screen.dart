import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../utils/routine_share_location.dart';
import '../utils/routine_share_pending.dart';
import '../utils/routine_share_url.dart';
import 'practice_mode_screen.dart';
import 'practice_screen.dart';

class RoutinePlayerScreen extends StatefulWidget {
  const RoutinePlayerScreen({
    super.key,
    required this.routine,
    required this.library,
    this.communityPostId,
    this.onOpenInShell,
  });

  final SavedRoutine routine;
  final RoutineLibrary library;

  /// Firestore `community_routines` document id. When set, the share control
  /// copies `/r/{id}` and the browser path stays on that route while open.
  final String? communityPostId;
  final ValueChanged<Widget>? onOpenInShell;

  @override
  State<RoutinePlayerScreen> createState() => _RoutinePlayerScreenState();
}

class _RoutinePlayerScreenState extends State<RoutinePlayerScreen> {
  final GlobalKey<PracticeModeScreenState> _playerKey = GlobalKey<PracticeModeScreenState>();

  String? get _sharePostId {
    final id = widget.communityPostId?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  @override
  void initState() {
    super.initState();
    final id = _sharePostId;
    if (id != null) {
      RoutineSharePending.capture(id);
      setCommunityRoutineSharePath(id);
    }
  }

  void _leavePlayer() {
    // Only clear the share path when the user leaves. Clearing in dispose also
    // ran when AuthGate remounted home and wiped `/r/{id}` on cold open.
    if (_sharePostId != null) {
      RoutineSharePending.clear();
      clearCommunityRoutineSharePath();
    }
    Navigator.of(context).pop();
  }

  Future<void> _openPractice() async {
    await _playerKey.currentState?.pausePlayback();
    if (!mounted) return;
    final practice = PracticeScreen(
      library: widget.library,
      selectedRoutine: widget.routine,
      onOpenInShell: widget.onOpenInShell,
    );
    if (widget.onOpenInShell != null) {
      widget.onOpenInShell!(practice);
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => practice,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _copyShareLink() async {
    final id = _sharePostId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = communityRoutineShareUrl(id);
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('player.link_copied'.tr())),
      );
    } catch (error) {
      debugPrint('copy share link failed: $error');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('player.link_copy_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShare = _sharePostId != null;
    return Scaffold(
      backgroundColor: const Color(0xFF120F1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF120F1C),
        foregroundColor: Colors.white,
        title: Text(
          widget.routine.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leavePlayer,
        ),
        actions: [
          if (canShare)
            IconButton(
              tooltip: 'player.copy_link'.tr(),
              icon: const Icon(Icons.link),
              onPressed: _copyShareLink,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.fitness_center, size: 18),
              label: Text('player.practice'.tr()),
              onPressed: _openPractice,
            ),
          ),
        ],
      ),
      body: PracticeModeScreen(
        key: _playerKey,
        routine: widget.routine,
        library: widget.library,
        embedded: true,
      ),
    );
  }
}
