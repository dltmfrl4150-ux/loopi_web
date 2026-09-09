/// Formats a duration in seconds as `mm:ss`.
String formatMmSs(double seconds) {
  final total = seconds.round().clamp(0, 99 * 60 + 59);
  final minutes = total ~/ 60;
  final secs = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

/// Parses `mm:ss`, `m:ss`, `hh:mm:ss`, digit strings like `0100`, or a
/// seconds value into total seconds.
///
/// Digit-only input is treated as `MMSS` (not raw seconds): `0100` → 60,
/// `0219` → 139. Seconds past 59 roll over into minutes.
double? parseTimeInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  if (text.contains(':')) {
    final parts = text.split(':');
    if (parts.length != 2 && parts.length != 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      if (part.isEmpty) return null;
      final n = int.tryParse(part);
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    if (parts.length == 2) {
      return _minutesAndSeconds(numbers[0], numbers[1]);
    }
    return _hoursMinutesSeconds(numbers[0], numbers[1], numbers[2]);
  }

  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final padded = digits.length >= 4 ? digits : digits.padLeft(4, '0');
  final minutes = int.tryParse(padded.substring(0, padded.length - 2)) ?? 0;
  final seconds = int.tryParse(padded.substring(padded.length - 2)) ?? 0;
  return _minutesAndSeconds(minutes, seconds);
}

double _minutesAndSeconds(int minutes, int seconds) {
  final totalSeconds = (minutes * 60) + seconds;
  if (totalSeconds < 0) return 0;
  return totalSeconds.toDouble();
}

double _hoursMinutesSeconds(int hours, int minutes, int seconds) {
  return _minutesAndSeconds(hours * 60 + minutes, seconds);
}
