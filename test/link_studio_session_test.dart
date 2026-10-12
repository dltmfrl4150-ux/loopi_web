import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/models/routine_models.dart';
import 'package:loopi_web/state/link_studio_session.dart';

void main() {
  group('sectionLabelForIndex', () {
    test('uses A-Z then AA, AB…', () {
      expect(sectionLabelForIndex(0), 'A');
      expect(sectionLabelForIndex(25), 'Z');
      expect(sectionLabelForIndex(26), 'AA');
      expect(sectionLabelForIndex(27), 'AB');
      expect(sectionLabelForIndex(51), 'AZ');
      expect(sectionLabelForIndex(52), 'BA');
    });
  });

  group('LinkStudioSession.addSegment', () {
    test('duplicates selected section and inserts after it', () {
      final session = LinkStudioSession(initialDuration: 60);
      session.updateRangeAt(0, const RangeValues(5, 15));
      session.setSpeed(0, 0.8);
      session.addSegment();
      session.updateRangeAt(1, const RangeValues(20, 30));
      session.selectSegment(0);
      session.addSegment();

      expect(session.segments.length, 3);
      expect(session.selectedIndex, 1);
      expect(session.segments[0].startSec, 5);
      expect(session.segments[1].startSec, 5);
      expect(session.segments[1].endSec, 15);
      expect(session.segments[1].speed, 0.8);
      expect(session.segments[2].startSec, 20);
      expect(sectionLabelForIndex(0), 'A');
      expect(sectionLabelForIndex(1), 'B');
      expect(sectionLabelForIndex(2), 'C');
    });
  });

  group('LinkStudioSession.generateTenSecondSections', () {
    test('splits duration into 10s chunks at 0.7x and selects A', () {
      final session = LinkStudioSession(initialDuration: 25);
      session.generateTenSecondSections(duration: 25);

      expect(session.segments.length, 3);
      expect(session.selectedIndex, 0);
      expect(session.segments[0].startSec, 0);
      expect(session.segments[0].endSec, 10);
      expect(session.segments[1].startSec, 10);
      expect(session.segments[1].endSec, 20);
      expect(session.segments[2].startSec, 20);
      expect(session.segments[2].endSec, 25);
      expect(session.segments.every((s) => s.speed == 0.7), isTrue);
    });
  });

  group('LinkStudioSession default end', () {
    test('initial section A ends at full video duration', () {
      final session = LinkStudioSession(initialDuration: 240);
      expect(session.segments.single.startSec, 0);
      expect(session.segments.single.endSec, 240);
    });

    test('metadata duration updates stretch the single default section', () {
      final session = LinkStudioSession(initialDuration: 180);
      expect(session.segments.single.endSec, 180);
      session.setVideoDuration(312);
      expect(session.segments.single.endSec, 312);
      expect(session.videoDuration, 312);
    });

    test('legacy 30s placeholder expands when duration is already known', () {
      final session = LinkStudioSession(initialDuration: 100);
      session.updateRangeAt(0, const RangeValues(0, 30));
      session.setVideoDuration(100);
      expect(session.segments.single.endSec, 100);
    });
  });
}
