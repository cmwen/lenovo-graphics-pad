import 'package:flutter_test/flutter_test.dart';
import 'package:lenovo_graphics_pad/pen_report.dart';

void main() {
  test('encodes report ID, flags and little-endian fields', () {
    expect(
      PenReport.encode(
        tip: true,
        inRange: true,
        barrel: true,
        x: 0x1234,
        y: 0x5678,
        pressure: 0x09ab,
      ),
      [1, 7, 0x34, 0x12, 0x78, 0x56, 0xab, 0x09],
    );
  });

  test('released pen has all-up flags and zero pressure', () {
    expect(
      PenReport.encode(
        tip: false,
        inRange: true,
        barrel: false,
        x: 12,
        y: 34,
        pressure: 9000,
      ),
      [1, 2, 12, 0, 34, 0, 0, 0],
    );
  });

  test('out of range clears tip and barrel flags and pressure', () {
    expect(
      PenReport.encode(
        tip: true,
        inRange: false,
        barrel: true,
        x: 100,
        y: 200,
        pressure: 800,
      ),
      [1, 0, 100, 0, 200, 0, 0, 0],
    );
  });

  test('clamps coordinates and pressure to report bounds', () {
    expect(
      PenReport.encode(
        tip: true,
        inRange: true,
        barrel: false,
        x: -8,
        y: 50000,
        pressure: 9000,
      ),
      [1, 3, 0, 0, 0xff, 0x7f, 0xff, 0x0f],
    );
  });
}
