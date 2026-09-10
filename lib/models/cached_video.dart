import 'package:cloud_firestore/cloud_firestore.dart';

import 'routine_models.dart';

/// Firestore `cached_videos/{videoId}` document — avoids repeat YouTube Data API
/// metadata fetches and stores practice section windows for a video.
class CachedVideo {
  const CachedVideo({
    required this.videoId,
    required this.title,
    required this.duration,
    required this.thumbnailUrl,
    required this.sections,
    this.updatedAt,
  });

  final String videoId;
  final String title;
  final double duration;
  final String thumbnailUrl;
  final List<RoutineSegment> sections;
  final DateTime? updatedAt;

  bool get hasSections => sections.isNotEmpty;

  factory CachedVideo.fromFirestore(String videoId, Map<String, dynamic> data) {
    final rawSections = data['sections'];
    final sections = <RoutineSegment>[];
    if (rawSections is List) {
      for (var i = 0; i < rawSections.length; i++) {
        final item = rawSections[i];
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        // Accept both startSec/endSec and start/end keys.
        final start = (map['startSec'] as num?)?.toDouble() ??
            (map['start'] as num?)?.toDouble() ??
            0.0;
        final endRaw = (map['endSec'] as num?)?.toDouble() ??
            (map['end'] as num?)?.toDouble();
        final end = (endRaw != null && endRaw > start) ? endRaw : start;
        sections.add(
          RoutineSegment(
            id: map['id'] as String? ?? 'seg_$i',
            startSec: start,
            endSec: end,
            speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
            loopCount: (map['loopCount'] as num?)?.toInt() ?? 1,
            delaySec: (map['delaySec'] as num?)?.toInt() ?? 0,
            isHighlight: map['isHighlight'] == true,
          ),
        );
      }
    }

    final updatedRaw = data['updatedAt'];
    DateTime? updatedAt;
    if (updatedRaw is Timestamp) {
      updatedAt = updatedRaw.toDate();
    } else if (updatedRaw is DateTime) {
      updatedAt = updatedRaw;
    } else if (updatedRaw is String) {
      updatedAt = DateTime.tryParse(updatedRaw);
    }

    return CachedVideo(
      videoId: videoId,
      title: (data['title'] as String?)?.trim() ?? '',
      duration: (data['duration'] as num?)?.toDouble() ?? 0,
      thumbnailUrl: (data['thumbnailUrl'] as String?)?.trim() ?? '',
      sections: List<RoutineSegment>.unmodifiable(sections),
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'videoId': videoId,
        'title': title,
        'duration': duration,
        'thumbnailUrl': thumbnailUrl,
        'sections': sections
            .map(
              (s) => {
                'id': s.id,
                'startSec': s.startSec,
                'endSec': s.endSec,
                'start': s.startSec,
                'end': s.endSec,
                'speed': s.speed,
                'loopCount': s.loopCount,
                'delaySec': s.delaySec,
                'isHighlight': s.isHighlight,
              },
            )
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
