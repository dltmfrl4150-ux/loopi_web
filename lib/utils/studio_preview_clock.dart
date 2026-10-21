/// Projects playback time for Studio "루틴 재생" when iframe `currentTime` stalls.
///
/// Used only by link-studio preview monitoring — not by saved-routine Practice Mode.
double projectStudioPreviewTime({
  required double reportedSec,
  required double startSec,
  required double speed,
  required double lastReportedSec,
  required DateTime? lastReportedAt,
  required double anchorSec,
  required DateTime? anchorAt,
  required DateTime now,
}) {
  final rate = speed <= 0 ? 1.0 : speed;
  var lastSec = lastReportedSec;
  var lastAt = lastReportedAt;
  if (reportedSec >= startSec - 0.05) {
    lastSec = reportedSec;
    lastAt = now;
  }

  var projected = reportedSec;
  if (lastAt != null) {
    final age = now.difference(lastAt).inMilliseconds / 1000.0;
    final fromSample = lastSec + age * rate;
    if (fromSample > projected) projected = fromSample;
  }
  if (anchorAt != null) {
    final wall = anchorSec + now.difference(anchorAt).inMilliseconds / 1000.0 * rate;
    if (wall > projected) projected = wall;
  }
  return projected;
}

/// True when preview playback should treat [time] as having reached [endSec].
///
/// Stops slightly early so a late pause command cannot leak past End into the
/// rest of the source video.
bool studioPreviewReachedEnd({
  required double time,
  required double startSec,
  required double endSec,
  double earlyStopSec = 0.15,
}) {
  if (endSec <= startSec) return false;
  if (time < startSec - 0.1) return false;
  return time + 0.001 >= endSec - earlyStopSec;
}
