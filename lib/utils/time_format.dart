/// Formats a duration in seconds as total minutes:seconds (`MMM:SS`).
///
/// Minutes are not capped at 99, so long videos format as e.g. `124:57`.
String formatMmSs(double seconds) {
  final totalSeconds = seconds.round().clamp(0, 0x7fffffff);
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final secs = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$secs';
}

/// Parses typed time into total seconds.
///
/// Non-digits are stripped first (`111:44` → `11144`), then the string is
/// read from the rear:
/// - 1–2 digits → seconds (`5` → 5, `20` → 20)
/// - 3+ digits → last 2 are seconds, leading digits are minutes
///   (`120` → 80, `1144` → 704, `11144` → 6704)
double? parseTimeInput(String raw) {
  final digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;

  final total = digits.length <= 2
      ? int.parse(digits)
      : int.parse(digits.substring(0, digits.length - 2)) * 60 +
          int.parse(digits.substring(digits.length - 2));
  if (total < 0) return 0;
  return total.toDouble();
}
