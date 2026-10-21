import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/studio_preview_clock.dart';

void main() {
  test('projects forward when reported currentTime stalls after start', () {
    final started = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final later = started.add(const Duration(seconds: 3));

    final projected = projectStudioPreviewTime(
      reportedSec: 10.0,
      startSec: 10.0,
      speed: 1.0,
      lastReportedSec: 10.0,
      lastReportedAt: started,
      anchorSec: 10.0,
      anchorAt: started,
      now: later,
    );

    expect(projected, greaterThanOrEqualTo(12.9));
    expect(
      studioPreviewReachedEnd(time: projected, startSec: 10, endSec: 12),
      isTrue,
    );
  });

  test('does not treat time before start as end', () {
    expect(
      studioPreviewReachedEnd(time: 1, startSec: 10, endSec: 20),
      isFalse,
    );
  });

  test('honors early-stop margin before endSec', () {
    expect(
      studioPreviewReachedEnd(time: 19.86, startSec: 10, endSec: 20),
      isTrue,
    );
    expect(
      studioPreviewReachedEnd(time: 19.0, startSec: 10, endSec: 20),
      isFalse,
    );
  });

  test('respects playback speed in projection', () {
    final started = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final later = started.add(const Duration(seconds: 2));
    final projected = projectStudioPreviewTime(
      reportedSec: 5.0,
      startSec: 5.0,
      speed: 2.0,
      lastReportedSec: 5.0,
      lastReportedAt: started,
      anchorSec: 5.0,
      anchorAt: started,
      now: later,
    );
    expect(projected, closeTo(9.0, 0.05));
  });

  test('1s segment reaches End from wall clock alone (stale currentTime)', () {
    // Mirrors Studio preview when iframe currentTime never advances past Start.
    final started = DateTime.utc(2026, 1, 1, 12, 0, 0);
    const start = 42.0;
    const end = 43.0;

    // ~0.9s later → earlyStop (end - 0.15) should fire without fresh samples.
    final nearEnd = started.add(const Duration(milliseconds: 900));
    final projected = projectStudioPreviewTime(
      reportedSec: start,
      startSec: start,
      speed: 1.0,
      lastReportedSec: start,
      lastReportedAt: started,
      anchorSec: start,
      anchorAt: started,
      now: nearEnd,
    );

    expect(projected, closeTo(42.9, 0.05));
    expect(
      studioPreviewReachedEnd(time: projected, startSec: start, endSec: end),
      isTrue,
    );
  });

  test('projection advances even when lastReportedAt is refreshed every tick', () {
    // Regression: calling project with reported==lastReported and now==lastAt
    // must still advance via play-start anchor (End monitor ticks do this).
    final started = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final tick = started.add(const Duration(milliseconds: 1000));
    final projected = projectStudioPreviewTime(
      reportedSec: 10.0,
      startSec: 10.0,
      speed: 1.0,
      lastReportedSec: 10.0,
      lastReportedAt: tick, // "fresh" sample timestamp every monitor tick
      anchorSec: 10.0,
      anchorAt: started,
      now: tick,
    );
    expect(projected, closeTo(11.0, 0.05));
    expect(
      studioPreviewReachedEnd(time: projected, startSec: 10, endSec: 11),
      isTrue,
    );
  });
}
