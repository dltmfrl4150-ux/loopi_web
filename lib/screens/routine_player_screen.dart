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
  });

  final SavedRoutine routine;
  final RoutineLibrary library;

  @override
  State<RoutinePlayerScreen> createState() => _RoutinePlayerScreenState();
}

class _RoutinePlayerScreenState extends State<RoutinePlayerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routine.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.fitness_center),
            label: const Text('연습하기'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PracticeScreen(
                    library: widget.library,
                    selectedRoutine: widget.routine,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: PracticeModeScreen(
        routine: widget.routine,
        library: widget.library,
      ),
    );
  }
}