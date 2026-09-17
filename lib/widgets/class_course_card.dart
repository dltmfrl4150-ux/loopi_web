import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/class_models.dart';
import '../theme/loopi_colors.dart';
import '../widgets/cached_remote_image.dart';

class ClassCourseCard extends StatelessWidget {
  const ClassCourseCard({
    super.key,
    required this.course,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.showOwnerActions = false,
  });

  final ClassCourse course;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showOwnerActions;

  String _priceLabel() {
    if (course.isFree) return 'class.badge_free'.tr();
    final s = course.price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return 'class.price_won'.tr(namedArgs: {'price': buf.toString()});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  course.thumbnailUrl != null && course.thumbnailUrl!.isNotEmpty
                      ? CachedRemoteImage(url: course.thumbnailUrl!, fit: BoxFit.cover)
                      : ColoredBox(
                          color: LoopiColors.purple.withValues(alpha: 0.12),
                          child: const Icon(Icons.school_outlined, color: LoopiColors.purple),
                        ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _priceLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.25),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    course.instructorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.view_week_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'class.section_count'.tr(namedArgs: {'count': '${course.sectionCount}'}),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                      ),
                      const Spacer(),
                      if (showOwnerActions) ...[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'common.save'.tr(),
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'common.delete'.tr(),
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
