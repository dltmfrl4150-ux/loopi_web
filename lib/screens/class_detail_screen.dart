import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/class_models.dart';
import '../models/routine_category.dart';
import '../services/class_catalog.dart';
import '../theme/loopi_colors.dart';
import '../widgets/cached_remote_image.dart';
import 'class_player_screen.dart';

class ClassDetailScreen extends StatelessWidget {
  const ClassDetailScreen({
    super.key,
    required this.course,
    this.isOwn = false,
  });

  final ClassCourse course;
  final bool isOwn;

  String _priceLabel(ClassCourse c) {
    if (c.isFree) return 'class.badge_free'.tr();
    return 'class.price_won'.tr(namedArgs: {'price': _formatPrice(c.price)});
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ClassCatalog.instance;
    final live = catalog.byId(course.id) ?? course;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(live.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: live.thumbnailUrl != null && live.thumbnailUrl!.isNotEmpty
                  ? CachedRemoteImage(url: live.thumbnailUrl!, fit: BoxFit.cover)
                  : ColoredBox(
                      color: LoopiColors.purple.withValues(alpha: 0.12),
                      child: const Center(
                        child: Icon(Icons.school_outlined, size: 48, color: LoopiColors.purple),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: live.isFree
                      ? LoopiColors.purple.withValues(alpha: 0.14)
                      : LoopiColors.deepPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _priceLabel(live),
                  style: TextStyle(
                    color: live.isFree ? LoopiColors.deepPurple : LoopiColors.deepPurple,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                RoutineCategory.labelKey(live.category).tr(),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            live.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: LoopiColors.purple.withValues(alpha: 0.15),
                backgroundImage: live.instructorAvatarUrl != null &&
                        live.instructorAvatarUrl!.isNotEmpty
                    ? NetworkImage(live.instructorAvatarUrl!)
                    : null,
                child: live.instructorAvatarUrl == null || live.instructorAvatarUrl!.isEmpty
                    ? Text(
                        live.instructorName.isNotEmpty ? live.instructorName[0] : '?',
                        style: const TextStyle(
                          color: LoopiColors.deepPurple,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  live.instructorName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade700),
              const SizedBox(width: 2),
              Text(live.rating.toStringAsFixed(1)),
              const SizedBox(width: 10),
              Text('class.student_count'.tr(namedArgs: {'count': '${live.studentCount}'})),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            live.description,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 22),
          Text(
            'class.lessons'.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < live.units.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: LoopiColors.purple.withValues(alpha: 0.14),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: LoopiColors.deepPurple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(live.units[i].unitTitle),
                subtitle: Text(
                  'class.unit_sections'.tr(
                    namedArgs: {'count': '${live.units[i].practiceSegmentCount}'},
                  ),
                ),
                trailing: const Icon(Icons.play_circle_fill, color: LoopiColors.purple),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ClassPlayerScreen(
                        course: live,
                        initialUnitIndex: i,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () {
              if (!catalog.isEnrolled(live.id)) {
                catalog.enroll(live.id);
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ClassPlayerScreen(course: live),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              isOwn
                  ? 'class.open_as_instructor'.tr()
                  : (catalog.isEnrolled(live.id)
                      ? 'class.continue_learning'.tr()
                      : 'class.enroll_and_start'.tr()),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: LoopiColors.deepPurple,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}
