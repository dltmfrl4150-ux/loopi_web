import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/routine_models.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/storage_quota.dart';

/// Saved routine presets, backed by SharedPreferences and optionally Firestore.
class RoutineLibrary extends ChangeNotifier {
  static const String _routineStorageKey = 'loopi_saved_routines';
  static const String _groupStorageKey = 'loopi_saved_groups';
  static const String _practiceStorageKey = 'loopi_practice_results';

  RoutineLibrary({DatabaseService? database}) : _database = database ?? DatabaseService();

  final DatabaseService _database;
  String? _uid;
  bool _storageQuotaPending = false;

  final List<SavedRoutine> _routines = [];
  final List<RoutineGroup> _groups = [];
  final List<PracticeResult> _practiceResults = [];

  List<SavedRoutine> get routines => List.unmodifiable(_routines);
  List<RoutineGroup> get groups => List.unmodifiable(_groups);
  List<PracticeResult> get practiceResults => List.unmodifiable(_practiceResults);
  List<SavedRoutine> get favoriteRoutines => _routines.where((routine) => routine.isFavorite).toList();

  /// True once after a local persist fails due to storage quota.
  bool get hasStorageQuotaWarning => _storageQuotaPending;

  /// Returns true once when a quota failure should be shown in the UI.
  bool consumeStorageQuotaWarning() {
    if (!_storageQuotaPending) return false;
    _storageQuotaPending = false;
    return true;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoutines = prefs.getStringList(_routineStorageKey) ?? const <String>[];
    final savedGroups = prefs.getStringList(_groupStorageKey) ?? const <String>[];
    final savedPracticeResults = prefs.getStringList(_practiceStorageKey) ?? const <String>[];

    _routines
      ..clear()
      ..addAll(
        savedRoutines
            .map(_decodePrefsMap)
            .whereType<Map<String, dynamic>>()
            .map((json) {
              json.remove('localDataBytes');
              return SavedRoutine.fromJson(json);
            })
            .toList(),
      );

    _groups
      ..clear()
      ..addAll(
        savedGroups
            .map(_decodePrefsMap)
            .whereType<Map<String, dynamic>>()
            .map(RoutineGroup.fromJson)
            .toList(),
      );
    _practiceResults
      ..clear()
      ..addAll(
        savedPracticeResults
            .map(_decodePrefsMap)
            .whereType<Map<String, dynamic>>()
            .map((json) {
              json.remove('recordedDataBytes');
              return PracticeResult.fromJson(json);
            }),
      );
    notifyListeners();
    // Migrate any legacy prefs that still contain base64/blob payloads.
    unawaited(_persistLocal());
  }

  Map<String, dynamic>? _decodePrefsMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> attachUser(String uid) async {
    _uid = uid;
    if (!FirebaseBootstrap.initialized) return;
    try {
      final cloud = await _database.fetchLibrary(uid);
      if (cloud.routines.isEmpty && cloud.groups.isEmpty && cloud.practiceResults.isEmpty) {
        if (_routines.isNotEmpty || _groups.isNotEmpty || _practiceResults.isNotEmpty) {
          await _syncCloud();
        }
        return;
      }
      _routines
        ..clear()
        ..addAll(cloud.routines);
      _groups
        ..clear()
        ..addAll(cloud.groups);
      // Practice recordings stay local-first. Do not replace in-session blobs
      // with cloud metadata that has no playable file.
      if (_practiceResults.isEmpty && cloud.practiceResults.isNotEmpty) {
        _practiceResults.addAll(cloud.practiceResults);
      }
      notifyListeners();
      await _persistLocal();
    } catch (error) {
      debugPrint('attachUser error: $error');
    }
  }

  void detachUser() {
    _uid = null;
  }

  Future<void> _persist() async {
    await _persistLocal();
    unawaited(_syncCloud());
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    // Metadata only — never write base64 / blob / data: media into prefs.
    final routinePayload =
        _routines.map((routine) => jsonEncode(routine.toPrefsJson())).toList();
    final groupPayload =
        _groups.map((group) => jsonEncode(group.toJson())).toList();
    final practicePayload =
        _practiceResults.map((result) => jsonEncode(result.toLocalJson())).toList();

    try {
      await prefs.setStringList(_routineStorageKey, routinePayload);
      await prefs.setStringList(_groupStorageKey, groupPayload);
      await prefs.setStringList(_practiceStorageKey, practicePayload);
    } catch (error) {
      debugPrint(
        '[LOOPI] SharedPreferences QuotaExceeded/persist failed: $error — '
        'rewriting metadata-only library',
      );
      try {
        await prefs.remove(_routineStorageKey);
        await prefs.remove(_groupStorageKey);
        await prefs.remove(_practiceStorageKey);
        await prefs.setStringList(_routineStorageKey, routinePayload);
        await prefs.setStringList(_groupStorageKey, groupPayload);
        await prefs.setStringList(_practiceStorageKey, practicePayload);
      } catch (retryError) {
        debugPrint('[LOOPI] SharedPreferences recovery failed: $retryError');
        _storageQuotaPending = true;
        notifyListeners();
        throw StorageQuotaExceededException(retryError);
      }
      if (StorageQuotaExceededException.matches(error)) {
        _storageQuotaPending = true;
        notifyListeners();
        // Recovered after wipe — still nudge so the user can free space.
        // Do not throw; data was rewritten successfully.
      }
    }
  }

  Future<void> _syncCloud() async {
    final uid = _uid;
    if (uid == null || !FirebaseBootstrap.initialized) return;
    await _database.saveLibrary(
      uid: uid,
      routines: _routines,
      groups: _groups,
      practiceResults: const [],
    );
  }

  SavedRoutine? byId(String id) {
    for (final routine in _routines) {
      if (routine.id == id) return routine;
    }
    return null;
  }

  List<SavedRoutine> routinesForGroup(RoutineGroup group) {
    return group.routineIds
        .map((id) => byId(id))
        .whereType<SavedRoutine>()
        .toList();
  }

  Set<String> get groupedRoutineIds {
    return {
      for (final group in _groups) ...group.routineIds,
    };
  }

  List<SavedRoutine> get ungroupedRoutines {
    final grouped = groupedRoutineIds;
    return _routines.where((routine) => !grouped.contains(routine.id)).toList();
  }

  Future<void> save(SavedRoutine routine) async {
    _routines.insert(0, routine);
    notifyListeners();
    await _persist();
  }

  Future<void> update(SavedRoutine routine) async {
    final index = _routines.indexWhere((item) => item.id == routine.id);
    if (index < 0) {
      await save(routine);
      return;
    }
    _routines[index] = routine;
    notifyListeners();
    await _persist();
  }

  Future<void> setFavorite(String id, bool value) async {
    final index = _routines.indexWhere((routine) => routine.id == id);
    if (index < 0 || _routines[index].isFavorite == value) return;
    _routines[index] = _routines[index].copyWith(isFavorite: value);
    notifyListeners();
    Future.delayed(Duration.zero, () {
      unawaited(_persist());
    });
  }

  Future<void> savePracticeResult(PracticeResult result) async {
    // Single-section takes: replace prior take for the same routine+section.
    final section = result.recordedSectionIndex;
    if (section != null) {
      _practiceResults.removeWhere(
        (existing) =>
            existing.routineId == result.routineId &&
            existing.recordedSectionIndex == section,
      );
    }
    _practiceResults.insert(0, result);
    notifyListeners();
    await _persistLocal();
  }

  /// Latest take per section index for a routine (independent section recordings).
  Map<int, PracticeResult> latestPracticeTakesBySection(String routineId) {
    final out = <int, PracticeResult>{};
    for (final result in _practiceResults) {
      if (result.routineId != routineId) continue;
      final idx = result.recordedSectionIndex;
      if (idx == null) continue;
      final prev = out[idx];
      if (prev == null || result.createdAt.isAfter(prev.createdAt)) {
        out[idx] = result;
      }
    }
    return out;
  }

  bool? toggleFavoriteOptimistic(String id) {
    final index = _routines.indexWhere((routine) => routine.id == id);
    if (index < 0) return null;
    final next = !_routines[index].isFavorite;
    setFavorite(id, next);
    return next;
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _routines.removeWhere((routine) => idSet.contains(routine.id));
    final nextGroups = <RoutineGroup>[];
    for (final group in _groups) {
      final remaining = group.routineIds.where((id) => !idSet.contains(id)).toList();
      if (remaining.isNotEmpty) {
        nextGroups.add(group.copyWith(routineIds: remaining));
      }
    }
    _groups
      ..clear()
      ..addAll(nextGroups);
    notifyListeners();
    await _persist();
  }

  Future<void> deletePracticeResult(String id) async {
    _practiceResults.removeWhere((result) => result.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> deleteManyPracticeResults(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _practiceResults.removeWhere((result) => idSet.contains(result.id));
    notifyListeners();
    await _persist();
  }

  Future<void> createGroup({required String name, required List<String> routineIds}) async {
    final unique = routineIds.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return;
    final nextGroups = <RoutineGroup>[];
    for (final group in _groups) {
      final remaining = group.routineIds.where((id) => !unique.contains(id)).toList();
      if (remaining.isNotEmpty) {
        nextGroups.add(group.copyWith(routineIds: remaining));
      }
    }
    nextGroups.add(
      RoutineGroup(
        id: 'grp_${DateTime.now().microsecondsSinceEpoch}',
        title: name.trim().isEmpty ? '새 폴더' : name.trim(),
        routineIds: unique,
      ),
    );
    _groups
      ..clear()
      ..addAll(nextGroups);
    notifyListeners();
    await _persist();
  }

  Future<void> deleteGroup(String groupId, {bool keepRoutines = true}) async {
    final groupIndex = _groups.indexWhere((group) => group.id == groupId);
    if (groupIndex < 0) return;
    final group = _groups.removeAt(groupIndex);
    if (!keepRoutines) {
      await deleteMany(group.routineIds);
      return;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> renameGroup(String groupId, String title) async {
    final index = _groups.indexWhere((group) => group.id == groupId);
    if (index < 0) return;
    _groups[index] = _groups[index].copyWith(title: title.trim().isEmpty ? '새 폴더' : title.trim());
    notifyListeners();
    await _persist();
  }
}
