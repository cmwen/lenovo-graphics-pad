package com.cmwen.lenovo_graphics_pad;

/** Standalone test runner; intentionally has no Android/JUnit dependency. */
public final class PenProtocolTest {
    private static final class Axis {
        int logicalMin, logicalMax, physicalMin, physicalMax, exponent, unit, size, count;
    }

    private static void check(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }

    private static int u(byte b) { return b & 0xff; }

    private static int u16(byte[] b, int offset) { return u(b[offset]) | (u(b[offset + 1]) << 8); }

    private static void contains(byte[] bytes, int... pattern) {
        outer: for (int i = 0; i <= bytes.length - pattern.length; i++) {
            for (int j = 0; j < pattern.length; j++) if (u(bytes[i + j]) != pattern[j]) continue outer;
            return;
        }
        throw new AssertionError("Descriptor missing item sequence " + java.util.Arrays.toString(pattern));
    }

    private static int unsigned(byte[] bytes, int offset, int size) {
        int value = 0;
        for (int i = 0; i < size; i++) value |= u(bytes[offset + i]) << (8 * i);
        return value;
    }

    private static java.util.Map<Integer, Axis> parseAxes(byte[] descriptor) {
        java.util.Map<Integer, Axis> axes = new java.util.HashMap<>();
        java.util.Map<Integer, Integer> globals = new java.util.HashMap<>();
        globals.put(3, 0); // HID default physical minimum
        globals.put(4, 0); // HID default physical maximum
        globals.put(5, 0); // HID default unit exponent
        globals.put(6, 0); // HID default unit
        java.util.ArrayDeque<java.util.Map<Integer, Integer>> stack = new java.util.ArrayDeque<>();
        java.util.List<Integer> usages = new java.util.ArrayList<>();
        int reportBits = 0;
        for (int i = 0; i < descriptor.length;) {
            int prefix = u(descriptor[i++]);
            int sizeCode = prefix & 3;
            int size = sizeCode == 3 ? 4 : sizeCode;
            check(i + size <= descriptor.length, "complete descriptor item");
            int raw = unsigned(descriptor, i, size);
            i += size;
            int type = (prefix >>> 2) & 3;
            int tag = (prefix >>> 4) & 15;
            if (type == 2 && tag == 0) { // Local Usage
                usages.add(raw);
            } else if (type == 1) {
                switch (tag) {
                    case 0: case 1: case 2: case 3: case 4: case 6: case 7: case 8: case 9:
                        globals.put(tag, raw);
                        break;
                    case 5: globals.put(tag, raw & 0x0f); break;
                    case 10: stack.push(new java.util.HashMap<>(globals)); break;
                    case 11: globals = stack.pop(); break;
                    default: break;
                }
            } else if (type == 0 && tag == 8) { // Main Input
                int fieldSize = globals.getOrDefault(7, 0);
                int fieldCount = globals.getOrDefault(9, 0);
                reportBits += fieldSize * fieldCount;
                if (usages.size() == 1) {
                    int usage = usages.get(0);
                    if (usage == 0x30 || usage == 0x31) {
                        Axis axis = new Axis();
                        axis.logicalMin = globals.getOrDefault(1, -1);
                        axis.logicalMax = globals.getOrDefault(2, -1);
                        axis.physicalMin = globals.getOrDefault(3, -1);
                        axis.physicalMax = globals.getOrDefault(4, -1);
                        axis.exponent = globals.getOrDefault(5, -1);
                        axis.unit = globals.getOrDefault(6, -1);
                        axis.size = fieldSize;
                        axis.count = fieldCount;
                        axes.put((globals.getOrDefault(0, 0) << 8) | usage, axis);
                    }
                }
                usages.clear();
            }
        }
        check(stack.isEmpty(), "balanced HID global Push/Pop");
        check(reportBits == 56, "descriptor report body is seven bytes");
        return axes;
    }

    public static void main(String[] args) {
        check(PenProtocol.REPORT_ID == 1 && PenProtocol.BODY_SIZE == 7 && PenProtocol.REPORT_SIZE == 8,
                "report ID/body/total size contract");
        byte[] descriptor = PenProtocol.DESCRIPTOR;
        contains(descriptor, 0x05, 0x0d, 0x09, 0x01, 0xa1, 0x01); // Digitizer application
        contains(descriptor, 0x09, 0x20, 0xa1, 0x00); // Pen with Stylus physical collection
        contains(descriptor, 0x09, 0x42, 0x09, 0x32, 0x09, 0x44, 0x09, 0x3c, 0x09, 0x45);
        contains(descriptor, 0x75, 0x01, 0x95, 0x05); // five one-bit flags
        contains(descriptor, 0x75, 0x03, 0x95, 0x01); // three padding bits
        contains(descriptor, 0x26, 0xff, 0x7f); // X/Y maximum 32767
        contains(descriptor, 0x26, 0xff, 0x0f); // pressure maximum 4095

        byte[] encoded = PenProtocol.encode(1, 0.5, 1, true, true, true, true, false);
        check(encoded.length == PenProtocol.BODY_SIZE, "body excludes ID");
        check(u(encoded[0]) == 0x0f, "tip, in-range, barrel and invert flags");
        check(u16(encoded, 1) == 32767 && u16(encoded, 3) == 16384, "normalized little-endian X/Y");
        check(u16(encoded, 5) == 4095, "maximum pressure");

        encoded = PenProtocol.encode(-2, 4, 0.5, true, true, false, false, false);
        check(u16(encoded, 1) == 0 && u16(encoded, 3) == 32767, "coordinate clamping");
        check(u16(encoded, 5) == 2048, "pressure quantization");
        encoded = PenProtocol.encode(0.25, 0.75, 1, true, false, true, true, false);
        check(u(encoded[0]) == 0 && u16(encoded, 5) == 0, "outside range forces no contact and zero pressure");
        encoded = PenProtocol.encode(0.5, 0.5, 0.5, false, true, false, false, true);
        check(u(encoded[0]) == 0x12 && u16(encoded, 5) == 2048, "eraser contact sets range and eraser, without tip switch");
        encoded = PenProtocol.encode(0.5, 0.5, 1, false, true, false, true, false);
        check(u(encoded[0]) == 0x0a && u16(encoded, 5) == 0, "eraser hover reports invert and range without contact");
        byte[] up = PenProtocol.allUp();
        check(up.length == 7, "all-up body size");
        for (byte value : up) check(value == 0, "all-up body is zero-filled");

        byte[] measured = PenProtocol.descriptor(2400, 1350);
        java.util.Map<Integer, Axis> axes = parseAxes(measured);
        Axis x = axes.get((0x01 << 8) | 0x30);
        Axis y = axes.get((0x01 << 8) | 0x31);
        Axis pressure = axes.get((0x0d << 8) | 0x30);
        check(x != null && y != null, "factory emits X and Y fields");
        check(x.logicalMin == 0 && x.logicalMax == 32767 && x.physicalMin == 0 && x.physicalMax == 2400,
                "X logical and measured physical ranges");
        check(y.logicalMin == 0 && y.logicalMax == 32767 && y.physicalMin == 0 && y.physicalMax == 1350,
                "Y logical and measured physical ranges");
        check(x.exponent == 0x0e && y.exponent == 0x0e && x.unit == 0x11 && y.unit == 0x11,
                "X/Y use SI centimeters with exponent -2");
        check(x.size == 16 && x.count == 1 && y.size == 16 && y.count == 1,
                "independent 16-bit X and Y fields");
        check(pressure != null && pressure.logicalMin == 0 && pressure.logicalMax == 4095 &&
                pressure.physicalMax == 0 && pressure.exponent == 0 && pressure.unit == 0,
                "pressure has no inherited axis dimensions or units: " + (pressure == null ? "missing" :
                        pressure.logicalMin + "," + pressure.logicalMax + "," + pressure.physicalMax + "," + pressure.exponent + "," + pressure.unit));
        java.util.Map<Integer, Axis> boundaryAxes = parseAxes(PenProtocol.descriptor(1, 32767));
        check(boundaryAxes.get(0x0130).physicalMax == 1 && boundaryAxes.get(0x0131).physicalMax == 32767,
                "physical dimensions accept inclusive bounds");
        expectInvalidDimension(0, 1);
        expectInvalidDimension(1, 32768);
        expectInvalidDimension(32768, 1);

        double[][] corners = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
        double[][][] expectedCorners = {
            {{0, 0}, {1, 0}, {0, 1}, {1, 1}},
            {{1, 0}, {1, 1}, {0, 0}, {0, 1}},
            {{1, 1}, {0, 1}, {1, 0}, {0, 0}},
            {{0, 1}, {0, 0}, {1, 1}, {1, 0}},
        };
        int[] rotations = {0, 90, 180, 270};
        for (int r = 0; r < rotations.length; r++) {
            for (int c = 0; c < corners.length; c++) {
                double[] actual = PenProtocol.map(corners[c][0], corners[c][1], 1, 1, rotations[r], false);
                close(actual[0], expectedCorners[r][c][0], "rotation " + rotations[r] + " X corner " + c);
                close(actual[1], expectedCorners[r][c][1], "rotation " + rotations[r] + " Y corner " + c);
            }
        }
        double[] mirrored = PenProtocol.map(0.2, 0.3, 1, 1, 90, true);
        close(mirrored[0], 0.7, "mirror is applied before rotation X");
        close(mirrored[1], 0.8, "mirror is applied before rotation Y");

        close(PenProtocol.map(0.25, 0.25, 0.5, 0.5, 0, false)[0], 0.0, "centered active-area left edge");
        close(PenProtocol.map(0.5, 0.5, 0.5, 0.5, 0, false)[0], 0.5, "centered active-area center");
        close(PenProtocol.map(0.75, 0.75, 0.5, 0.5, 0, false)[0], 1.0, "centered active-area right edge");
        close(PenProtocol.map(-1, -1, 0.5, 0.5, 0, false)[0], 0.0, "active-area coordinate clamps low");
        close(PenProtocol.map(2, 2, 0.5, 0.5, 0, false)[1], 1.0, "active-area coordinate clamps high");
        expectInvalidMap(Double.NaN, 0.5, 1, 1, 0);
        expectInvalidMap(0.5, Double.POSITIVE_INFINITY, 1, 1, 0);
        expectInvalidMap(0.5, 0.5, Double.NaN, 1, 0);
        expectInvalidMap(0.5, 0.5, 0.09, 1, 0);
        expectInvalidMap(0.5, 0.5, 1, 1.01, 0);
        expectInvalidMap(0.5, 0.5, 1, 1, 45);
        System.out.println("PenProtocol checks passed");
    }

    private static void close(double actual, double expected, String message) {
        check(Math.abs(actual - expected) < 1e-12, message + ": expected " + expected + " got " + actual);
    }

    private static void expectInvalidDimension(int width, int height) {
        try {
            PenProtocol.descriptor(width, height);
            throw new AssertionError("invalid physical dimensions must be rejected");
        } catch (IllegalArgumentException expected) { }
    }

    private static void expectInvalidMap(double x, double y, double activeW, double activeH, int rotation) {
        try {
            PenProtocol.map(x, y, activeW, activeH, rotation, false);
            throw new AssertionError("invalid map inputs must be rejected");
        } catch (IllegalArgumentException expected) { }
    }
}
