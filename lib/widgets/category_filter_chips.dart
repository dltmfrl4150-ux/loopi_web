import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/routine_category.dart';
import '../theme/loopi_colors.dart';

class CategoryFilterBar extends StatelessWidget {
  const CategoryFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    const chips = <String>[
      RoutineCategory.all,
      RoutineCategory.dance,
      RoutineCategory.language,
      RoutineCategory.other,
    ];

    // Avoid a fixed short height — Material FilterChips were vertically clipped at 48px.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Builder(
              builder: (context) {
                final id = chips[i];
                final isSelected = selected == id;
                return FilterChip(
                  label: Text(RoutineCategory.labelKey(id).tr()),
                  selected: isSelected,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  selectedColor: LoopiColors.purple.withValues(alpha: 0.18),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: isSelected ? LoopiColors.purple : LoopiColors.line,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? LoopiColors.deepPurple : LoopiColors.ink,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  onSelected: (_) => onSelected(id),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class CategoryChoiceChips extends StatelessWidget {
  const CategoryChoiceChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in RoutineCategory.values)
          ChoiceChip(
            label: Text(RoutineCategory.labelKey(id).tr()),
            selected: selected == id,
            selectedColor: LoopiColors.purple.withValues(alpha: 0.18),
            labelStyle: TextStyle(
              color: selected == id ? LoopiColors.deepPurple : LoopiColors.ink,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (_) => onSelected(id),
          ),
      ],
    );
  }
}
