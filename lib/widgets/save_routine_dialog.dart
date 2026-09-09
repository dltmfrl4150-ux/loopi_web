import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../models/routine_category.dart';
import '../theme/loopi_colors.dart';
import 'category_filter_chips.dart';

String defaultRoutineName([DateTime? now]) {
  final date = now ?? DateTime.now();
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d Routine';
}

class SaveRoutineDialogResult {
  const SaveRoutineDialogResult({
    required this.name,
    this.overwrite = false,
    this.category = RoutineCategory.dance,
  });

  final String name;
  final bool overwrite;
  final String category;
}

/// Shows the Save Routine Preset modal.
/// Returns [SaveRoutineDialogResult], or null if closed.
Future<SaveRoutineDialogResult?> showSaveRoutineDialog(
  BuildContext context, {
  String? initialName,
  bool allowOverwrite = false,
  String? initialCategory,
}) {
  return showDialog<SaveRoutineDialogResult>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) {
      return PointerInterceptor(
        child: SaveRoutineDialog(
          dialogContext: dialogContext,
          initialName: initialName,
          allowOverwrite: allowOverwrite,
          initialCategory: initialCategory,
        ),
      );
    },
  );
}

class SaveRoutineDialog extends StatefulWidget {
  const SaveRoutineDialog({
    super.key,
    this.dialogContext,
    this.initialName,
    this.allowOverwrite = false,
    this.initialCategory,
  });

  final BuildContext? dialogContext;
  final String? initialName;
  final bool allowOverwrite;
  final String? initialCategory;

  @override
  State<SaveRoutineDialog> createState() => _SaveRoutineDialogState();
}

class _SaveRoutineDialogState extends State<SaveRoutineDialog> {
  late final String _suggestedName;
  late final TextEditingController _routineNameController;
  late final FocusNode _focusNode;
  bool _clearedOnFirstFocus = false;
  late String _category;

  BuildContext get _dialogContext => widget.dialogContext ?? context;

  @override
  void initState() {
    super.initState();
    _suggestedName = (widget.initialName != null && widget.initialName!.trim().isNotEmpty)
        ? widget.initialName!.trim()
        : defaultRoutineName();
    _routineNameController = TextEditingController(text: _suggestedName);
    _focusNode = FocusNode();
    _category = RoutineCategory.normalize(widget.initialCategory);
    // Keep existing name when editing; only clear default date names on focus for new routines.
    if (!widget.allowOverwrite) {
      _focusNode.addListener(_onFocusChange);
    } else {
      _clearedOnFirstFocus = true;
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && !_clearedOnFirstFocus) {
      _clearedOnFirstFocus = true;
      _routineNameController.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _routineNameController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(_dialogContext).pop();
  }

  void _submit({required bool overwrite}) {
    final typed = _routineNameController.text.trim();
    Navigator.of(_dialogContext).pop(
      SaveRoutineDialogResult(
        name: typed.isEmpty ? _suggestedName : typed,
        overwrite: overwrite,
        category: _category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            widget.allowOverwrite ? 'studio.save_dialog_title'.tr() : 'studio.save_dialog_title'.tr(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: LoopiColors.ink,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.allowOverwrite
                      ? 'studio.save_overwrite_hint'.tr()
                      : 'studio.save_name_hint'.tr(),
                  style: const TextStyle(color: LoopiColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _routineNameController,
                  focusNode: _focusNode,
                  enabled: true,
                  autofocus: false,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [LengthLimitingTextInputFormatter(80)],
                  onChanged: (value) => setDialogState(() {}),
                  onSubmitted: (_) => _submit(overwrite: false),
                  decoration: InputDecoration(
                    labelText: 'Routine name',
                    hintText: _suggestedName,
                    filled: true,
                    fillColor: LoopiColors.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: LoopiColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: LoopiColors.purple, width: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'category.label'.tr(),
                  style: const TextStyle(
                    color: LoopiColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                CategoryChoiceChips(
                  selected: _category,
                  onSelected: (value) => setDialogState(() => _category = value),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: _close,
              style: OutlinedButton.styleFrom(
                foregroundColor: LoopiColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                side: const BorderSide(color: LoopiColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('common.close'.tr()),
            ),
            if (widget.allowOverwrite)
              FilledButton(
                onPressed: () => _submit(overwrite: true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('studio.overwrite'.tr()),
              ),
            FilledButton(
              onPressed: () => _submit(overwrite: false),
              style: FilledButton.styleFrom(
                backgroundColor: LoopiColors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('studio.save'.tr()),
            ),
          ],
        );
      },
    );
  }
}
