package com.cmwen.lenovo_graphics_pad;

/** Standard external pen report body. USB callers prepend REPORT_ID; Android Bluetooth HID callers pass it separately. */
public final class PenProtocol {
    public static final int REPORT_ID = 1;
    public static final int BODY_SIZE = 7;
    public static final int REPORT_SIZE = BODY_SIZE + 1;

    /** HID report descriptor for an external Digitizers-page Pen with Stylus physical collection. */
    public static final byte[] DESCRIPTOR = new byte[] {
        0x05, 0x0D,             // Usage Page (Digitizers)
        0x09, 0x01,             // Usage (Digitizer)
        (byte) 0xA1, 0x01,      // Collection (Application)
        (byte) 0x85, 0x01,      //   Report ID (1)
        0x09, 0x20,             //   Usage (Stylus)
        (byte) 0xA1, 0x00,      //   Collection (Physical)
        0x09, 0x42,             //     Tip Switch
        0x09, 0x32,             //     In Range
        0x09, 0x44,             //     Barrel Switch
        0x09, 0x3C,             //     Invert
        0x09, 0x45,             //     Eraser
        0x15, 0x00,             //     Logical Minimum (0)
        0x25, 0x01,             //     Logical Maximum (1)
        0x75, 0x01,             //     Report Size (1)
        (byte) 0x95, 0x05,      //     Report Count (5)
        (byte) 0x81, 0x02,      //     Input (Data, Variable, Absolute)
        0x75, 0x03,             //     Report Size (3)
        (byte) 0x95, 0x01,      //     Report Count (1)
        (byte) 0x81, 0x03,      //     Input (Constant, Variable, Absolute) padding
        0x05, 0x01,             //     Usage Page (Generic Desktop)
        0x09, 0x30,             //     Usage (X)
        0x09, 0x31,             //     Usage (Y)
        0x16, 0x00, 0x00,       //     Logical Minimum (0)
        0x26, (byte) 0xFF, 0x7F,//     Logical Maximum (32767)
        0x75, 0x10,             //     Report Size (16)
        (byte) 0x95, 0x02,      //     Report Count (2)
        (byte) 0x81, 0x02,      //     Input (Data, Variable, Absolute)
        0x05, 0x0D,             //     Usage Page (Digitizers)
        0x09, 0x30,             //     Usage (Tip Pressure)
        0x16, 0x00, 0x00,       //     Logical Minimum (0)
        0x26, (byte) 0xFF, 0x0F,//     Logical Maximum (4095)
        0x75, 0x10,             //     Report Size (16)
        (byte) 0x95, 0x01,      //     Report Count (1)
        (byte) 0x81, 0x02,      //     Input (Data, Variable, Absolute)
        (byte) 0xC0,            //   End Collection
        (byte) 0xC0             // End Collection
    };

    /**
     * Descriptor selected by the application after it has measured the active area.
     * DESCRIPTOR remains a geometry-neutral fixture until measured dimensions are supplied.
     */
    public static volatile byte[] activeDescriptor = DESCRIPTOR.clone();

    private PenProtocol() {}

    /**
     * Build a descriptor with per-axis physical dimensions in tenths of a millimeter.
     * Logical coordinates remain 0..32767; physical values use SI linear centimeters
     * with exponent -2, making each unit 0.1 mm.
     */
    public static byte[] descriptor(int widthTenthMm, int heightTenthMm) {
        validateDimension(widthTenthMm, "widthTenthMm");
        validateDimension(heightTenthMm, "heightTenthMm");
        return new byte[] {
            0x05, 0x0D,             // Usage Page (Digitizers)
            0x09, 0x01,             // Usage (Digitizer)
            (byte) 0xA1, 0x01,      // Collection (Application)
            (byte) 0x85, 0x01,      //   Report ID (1)
            0x09, 0x20,             //   Usage (Stylus)
            (byte) 0xA1, 0x00,      //   Collection (Physical)
            0x09, 0x42, 0x09, 0x32, 0x09, 0x44, 0x09, 0x3C, 0x09, 0x45,
            0x15, 0x00,             // Logical Minimum (0)
            0x25, 0x01,             // Logical Maximum (1)
            0x75, 0x01,             // Report Size (1)
            (byte) 0x95, 0x05,      // Report Count (5)
            (byte) 0x81, 0x02,      // Five flag bits
            0x75, 0x03,
            (byte) 0x95, 0x01,
            (byte) 0x81, 0x03,      // Three padding bits

            (byte) 0xA4,            // Push globals before X
            0x05, 0x01, 0x09, 0x30, // Generic Desktop, X
            0x16, 0x00, 0x00,       // Logical Minimum (0)
            0x26, (byte) 0xFF, 0x7F,// Logical Maximum (32767)
            0x36, 0x00, 0x00,       // Physical Minimum (0)
            0x46, (byte) widthTenthMm, (byte) (widthTenthMm >>> 8), // Physical Maximum
            0x55, 0x0E,             // Unit Exponent (-2)
            0x65, 0x11,             // Unit (SI Linear, centimeter)
            0x75, 0x10, (byte) 0x95, 0x01,
            (byte) 0x81, 0x02,
            (byte) 0xB4,            // Pop globals before Y

            (byte) 0xA4,            // Push globals before Y
            0x05, 0x01, 0x09, 0x31, // Generic Desktop, Y
            0x16, 0x00, 0x00,
            0x26, (byte) 0xFF, 0x7F,
            0x36, 0x00, 0x00,
            0x46, (byte) heightTenthMm, (byte) (heightTenthMm >>> 8),
            0x55, 0x0E,
            0x65, 0x11,
            0x75, 0x10, (byte) 0x95, 0x01,
            (byte) 0x81, 0x02,
            (byte) 0xB4,            // Pop globals so pressure has no inherited axis units

            0x05, 0x0D, 0x09, 0x30, // Digitizers, Tip Pressure
            0x16, 0x00, 0x00,
            0x26, (byte) 0xFF, 0x0F,// Logical Maximum (4095)
            0x75, 0x10, (byte) 0x95, 0x01,
            (byte) 0x81, 0x02,
            (byte) 0xC0, (byte) 0xC0
        };
    }

    private static void validateDimension(int value, String name) {
        if (value < 1 || value > 32767) {
            throw new IllegalArgumentException(name + " must be in 1..32767 tenths of a millimeter");
        }
    }

    /** Map normalized view coordinates through a centered active area, mirror, then rotation. */
    public static double[] map(double xNorm, double yNorm, double activeW, double activeH,
            int rotation, boolean mirror) {
        if (!Double.isFinite(xNorm) || !Double.isFinite(yNorm)) {
            throw new IllegalArgumentException("Normalized coordinates must be finite");
        }
        validateActiveFraction(activeW, "activeW");
        validateActiveFraction(activeH, "activeH");
        if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
            throw new IllegalArgumentException("rotation must be 0, 90, 180, or 270 degrees");
        }
        double x = clamp(((xNorm - (1.0 - activeW) / 2.0) / activeW), 0.0, 1.0);
        double y = clamp(((yNorm - (1.0 - activeH) / 2.0) / activeH), 0.0, 1.0);
        if (mirror) x = 1.0 - x;
        switch (rotation) {
            case 90: return new double[] {1.0 - y, x};
            case 180: return new double[] {1.0 - x, 1.0 - y};
            case 270: return new double[] {y, 1.0 - x};
            default: return new double[] {x, y};
        }
    }

    private static void validateActiveFraction(double value, String name) {
        if (!Double.isFinite(value) || value < 0.1 || value > 1.0) {
            throw new IllegalArgumentException(name + " must be finite and in 0.1..1.0");
        }
    }

    private static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }

    /** Encode normalized coordinates/pressure to the seven-byte body, excluding the report ID. */
    public static byte[] encode(double x, double y, double pressure,
            boolean tip, boolean inRange, boolean barrel, boolean invert, boolean eraser) {
        boolean contact = inRange && (tip || eraser);
        boolean tipSwitch = inRange && tip && !eraser;
        int flags = (tipSwitch ? 1 : 0)
                | (inRange ? 1 << 1 : 0)
                | (inRange && barrel ? 1 << 2 : 0)
                | (inRange && invert ? 1 << 3 : 0)
                | (inRange && eraser ? 1 << 4 : 0);
        int px = quantize(x, 32767);
        int py = quantize(y, 32767);
        int p = contact ? quantize(pressure, 4095) : 0;
        return new byte[] {(byte) flags, (byte) px, (byte) (px >>> 8),
                (byte) py, (byte) (py >>> 8), (byte) p, (byte) (p >>> 8)};
    }

    public static byte[] allUp() {
        return new byte[BODY_SIZE];
    }

    private static int quantize(double value, int max) {
        if (Double.isNaN(value) || value <= 0) return 0;
        if (value >= 1 || Double.isInfinite(value)) return max;
        return (int) Math.round(value * max);
    }
}
