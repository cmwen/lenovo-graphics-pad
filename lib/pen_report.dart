/// Encodes the starter's USB HID digitizer report payload.
///
/// The payload format is report ID, flags, X (u16 LE), Y (u16 LE), and
/// pressure (u16 LE). This encoder does not communicate with any device.
class PenReport {
  const PenReport._();

  static const int maxCoordinate = 32767;
  static const int maxPressure = 4095;

  static List<int> encode({
    required bool tip,
    required bool inRange,
    required bool barrel,
    required int x,
    required int y,
    required int pressure,
  }) {
    final tipDown = tip && inRange;
    final barrelDown = barrel && inRange;
    final flags = (tipDown ? 1 : 0) | (inRange ? 2 : 0) | (barrelDown ? 4 : 0);
    final boundedX = x.clamp(0, maxCoordinate).toInt();
    final boundedY = y.clamp(0, maxCoordinate).toInt();
    final boundedPressure = (tipDown ? pressure : 0)
        .clamp(0, maxPressure)
        .toInt();
    return [
      1,
      flags,
      boundedX & 0xff,
      (boundedX >> 8) & 0xff,
      boundedY & 0xff,
      (boundedY >> 8) & 0xff,
      boundedPressure & 0xff,
      (boundedPressure >> 8) & 0xff,
    ];
  }
}
