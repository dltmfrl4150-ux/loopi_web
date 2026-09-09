import 'package:flutter/material.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import 'practice_mode_screen.dart';
import 'practice_screen.dart';

class RoutinePlayerScreen extends StatefulWidget {
  const RoutinePlayerScreen({
    super.key,
    required this.routine,
    required this.library,
    this.onOpenInShell,
  });

  final SavedRoutine routine;
  final RoutineLibrary library;
  final ValueChanged<Widget>? onOpenInShell;

  @override
  State<RoutinePlayerScreen> createState() => _RoutinePlayerScreenState();
}

class _RoutinePlayerScreenState extends State<RoutinePlayerScreen> {
  final GlobalKey<PracticeModeScreenState> _playerKey = GlobalKey<PracticeModeScreenState>();

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
      MaterialPageRoute<void>(builder: (_) => practice),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.fitness_center, size: 18),
              label: const Text('연습하기'),
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
