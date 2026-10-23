package com.cmwen.lenovo_graphics_pad

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Color
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import kotlin.math.pow

/** Native, single-pointer pen capture and local ink preview. send receives the seven-byte report body. */
class PadSurface(
    context: Context,
    private val send: (ByteArray) -> Boolean,
    private val sample: (Map<String, Any?>) -> Unit,
) : View(context) {
    private data class Options(
        var rotation: Int = 0,
        var pressureMode: String = "auto",
        var pressureCurve: Double = 1.0,
        var activeWidth: Double = 1.0,
        var activeHeight: Double = 1.0,
        var leftHanded: Boolean = false,
        var barrel: Boolean = true,
        var eraser: Boolean = true,
        var fingerInput: Boolean = true,
    )

    private data class Mapped(val x: Double, val y: Double)
    private val options = Options()
    private val path = Path()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(38, 115, 210)
        style = Paint.Style.STROKE
        strokeWidth = 4f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private var activePointerId = MotionEvent.INVALID_POINTER_ID
    private var activeDeviceId = -1
    private var lastMapped: Mapped? = null
    private var lastSample: Map<String, Any?>? = null
    private var inkPointCount = 0
    private var inRange = false
    private var contact = false

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        setBackgroundColor(Color.WHITE)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (options.activeWidth < 1.0 || options.activeHeight < 1.0) {
            val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(125, 145, 150)
                style = Paint.Style.STROKE
                strokeWidth = 2f
                pathEffect = android.graphics.DashPathEffect(floatArrayOf(12f, 8f), 0f)
            }
            val left = (width * (1.0 - options.activeWidth) / 2.0).toFloat()
            val top = (height * (1.0 - options.activeHeight) / 2.0).toFloat()
            canvas.drawRect(left, top, width - left, height - top, border)
        }
        canvas.drawPath(path, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean = handle(event)

    override fun onHoverEvent(event: MotionEvent): Boolean = handle(event)

    override fun onGenericMotionEvent(event: MotionEvent): Boolean = handle(event)

    private fun handle(event: MotionEvent): Boolean {
        val tool = event.getToolType(event.actionIndex)
        val stylus = tool == MotionEvent.TOOL_TYPE_STYLUS || tool == MotionEvent.TOOL_TYPE_ERASER
        if (!stylus && (!options.fingerInput || event.source and InputDevice.SOURCE_TOUCHSCREEN != InputDevice.SOURCE_TOUCHSCREEN)) {
            return false
        }
        if (activeDeviceId != -1 && event.deviceId != activeDeviceId &&
            (activePointerId != MotionEvent.INVALID_POINTER_ID || inRange)) return true

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (activePointerId != MotionEvent.INVALID_POINTER_ID) return true
                if (event.actionMasked == MotionEvent.ACTION_POINTER_DOWN && !stylus) return true
                requestFocus()
                activePointerId = event.getPointerId(event.actionIndex)
                activeDeviceId = event.deviceId
                inRange = true
                contact = true
                addInkPoint(event.getX(event.actionIndex), event.getY(event.actionIndex), move = true)
                process(event, event.actionIndex, -1, contactNow = true)
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE, MotionEvent.ACTION_HOVER_MOVE, MotionEvent.ACTION_HOVER_ENTER -> {
                var index = event.findPointerIndex(activePointerId)
                if (index < 0) {
                    // Hover has no active touch pointer; track the event's primary tool only.
                    if (event.actionMasked == MotionEvent.ACTION_MOVE) return activePointerId != MotionEvent.INVALID_POINTER_ID
                    index = 0
                    activeDeviceId = event.deviceId
                    inRange = true
                }
                if (activePointerId == MotionEvent.INVALID_POINTER_ID && event.actionMasked == MotionEvent.ACTION_MOVE) return false
                val firstHistory = if (event.historySize > MAX_HISTORY_PER_EVENT) event.historySize - MAX_HISTORY_PER_EVENT else 0
                for (h in firstHistory until event.historySize) process(event, index, h, contactNow = contact)
                process(event, index, -1, contactNow = contact)
                if (contact) {
                    addInkPoint(event.getX(index), event.getY(index), move = false)
                    invalidate()
                }
                return true
            }
            MotionEvent.ACTION_BUTTON_PRESS, MotionEvent.ACTION_BUTTON_RELEASE -> {
                if (event.pointerCount == 0) return false
                if (activeDeviceId == -1) activeDeviceId = event.deviceId
                process(event, 0, -1, contactNow = contact)
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(event.actionIndex) == activePointerId) {
                    val ix = event.actionIndex
                    process(event, ix, -1, contactNow = false)
                    release()
                }
                return true
            }
            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_OUTSIDE, MotionEvent.ACTION_HOVER_EXIT -> {
                release()
                return true
            }
        }
        return activePointerId != MotionEvent.INVALID_POINTER_ID
    }

    private fun process(event: MotionEvent, pointerIndex: Int, historyIndex: Int, contactNow: Boolean) {
        val rawX = if (historyIndex >= 0) event.getHistoricalX(pointerIndex, historyIndex) else event.getX(pointerIndex)
        val rawY = if (historyIndex >= 0) event.getHistoricalY(pointerIndex, historyIndex) else event.getY(pointerIndex)
        val rawPressure = if (historyIndex >= 0) event.getHistoricalPressure(pointerIndex, historyIndex) else event.getPressure(pointerIndex)
        val mapped = mapPoint(rawX, rawY)
        val tool = event.getToolType(pointerIndex)
        val isStylus = tool == MotionEvent.TOOL_TYPE_STYLUS || tool == MotionEvent.TOOL_TYPE_ERASER
        val device = event.device
        val range = device?.getMotionRange(MotionEvent.AXIS_PRESSURE, event.source)
            ?: device?.getMotionRange(MotionEvent.AXIS_PRESSURE, InputDevice.SOURCE_STYLUS)
        val pressureSupported = isStylus && range != null && range.max > range.min
        val normalizedPressure = when {
            !contactNow -> 0.0
            options.pressureMode == "binary" || !pressureSupported -> 1.0
            else -> ((rawPressure - range!!.min) / (range.max - range.min)).coerceIn(0f, 1f)
                .toDouble().pow(options.pressureCurve).coerceIn(0.0, 1.0)
        }
        val eraserTool = tool == MotionEvent.TOOL_TYPE_ERASER
        val eraser = options.eraser && contactNow && (eraserTool || event.isButtonPressed(MotionEvent.BUTTON_STYLUS_SECONDARY))
        val barrel = options.barrel && (event.isButtonPressed(MotionEvent.BUTTON_STYLUS_PRIMARY) || event.isButtonPressed(MotionEvent.BUTTON_STYLUS_SECONDARY) && !eraser)
        val inRangeNow = inRange || contactNow
        val tip = contactNow && !eraser
        val body = PenProtocol.encode(mapped.x, mapped.y, normalizedPressure, tip, inRangeNow, barrel, eraserTool, eraser)
        send(body)
        val detail = linkedMapOf<String, Any?>(
            "x" to mapped.x, "y" to mapped.y, "pressure" to normalizedPressure,
            "rawPressure" to rawPressure.toDouble(), "tool" to if (eraser) "eraser" else if (isStylus) "stylus" else "touch",
            "tip" to tip, "inRange" to inRangeNow, "barrel" to barrel,
            "eraser" to eraser, "source" to event.source, "pressureSupported" to pressureSupported,
            "deviceId" to event.deviceId, "deviceName" to (device?.name ?: "unknown"),
            "historySamples" to event.historySize.coerceAtMost(MAX_HISTORY_PER_EVENT),
        )
        sample(detail)
        lastSample = detail.toMap()
        lastMapped = mapped
        contact = contactNow
    }

    private fun addInkPoint(x: Float, y: Float, move: Boolean) {
        if (inkPointCount >= MAX_INK_POINTS) {
            path.reset()
            path.moveTo(x, y)
            inkPointCount = 1
        } else if (move || inkPointCount == 0) {
            path.moveTo(x, y)
            inkPointCount++
        } else {
            path.lineTo(x, y)
            inkPointCount++
        }
    }

    private fun mapPoint(x: Float, y: Float): Mapped {
        val w = width.coerceAtLeast(1).toDouble()
        val h = height.coerceAtLeast(1).toDouble()
        val mapped = PenProtocol.map(
            x / w,
            y / h,
            options.activeWidth,
            options.activeHeight,
            options.rotation,
            options.leftHanded,
        )
        return Mapped(mapped[0], mapped[1])
    }

    /** Send a zero report on lifecycle loss, then forget the active pointer. */
    fun release() {
        val wasActive = activePointerId != MotionEvent.INVALID_POINTER_ID || inRange || contact
        if (wasActive) {
            send(PenProtocol.allUp())
            val last = lastSample
            if (last != null) {
                val released = last.toMutableMap()
                released["tip"] = false
                released["inRange"] = false
                released["barrel"] = false
                released["eraser"] = false
                released["pressure"] = 0.0
                released["rawPressure"] = 0.0
                released["historySamples"] = 0
                sample(released)
                lastSample = released
            }
        }
        activePointerId = MotionEvent.INVALID_POINTER_ID
        activeDeviceId = -1
        inRange = false
        contact = false
        lastMapped = null
    }

    fun clear() {
        release()
        path.reset()
        inkPointCount = 0
        lastSample = null
        invalidate()
    }

    fun configure(options: Map<String, Any?>) {
        if (activePointerId != MotionEvent.INVALID_POINTER_ID || inRange || contact) release()
        options["rotation"]?.let { (it as? Number)?.toInt()?.takeIf { n -> n in listOf(0, 90, 180, 270) }?.let { n -> this.options.rotation = n } }
        options["pressureMode"]?.toString()?.takeIf { it == "auto" || it == "binary" }?.let { this.options.pressureMode = it }
        options["pressureCurve"]?.numberIn(0.25, 4.0)?.let { this.options.pressureCurve = it }
        options["activeWidth"]?.numberIn(0.1, 1.0)?.let { this.options.activeWidth = it }
        options["activeHeight"]?.numberIn(0.1, 1.0)?.let { this.options.activeHeight = it }
        options["leftHanded"]?.let { (it as? Boolean)?.let { v -> this.options.leftHanded = v } }
        options["barrel"]?.let { (it as? Boolean)?.let { v -> this.options.barrel = v } }
        options["eraser"]?.let { (it as? Boolean)?.let { v -> this.options.eraser = v } }
        options["fingerInput"]?.let { (it as? Boolean)?.let { v -> this.options.fingerInput = v } }
        invalidate()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) release()
    }

    override fun onDetachedFromWindow() {
        release()
        super.onDetachedFromWindow()
    }

    private fun Any.numberIn(min: Double, max: Double): Double? =
        (this as? Number)?.toDouble()?.takeIf { it.isFinite() && it in min..max }

    companion object {
        private const val MAX_HISTORY_PER_EVENT = 32
        private const val MAX_INK_POINTS = 8192

        /** Read-only Android input-device capability inventory. Values are device-reported diagnostics. */
        fun capabilities(): List<Map<String, Any?>> = InputDevice.getDeviceIds().asList().mapNotNull { id ->
            val device = InputDevice.getDevice(id) ?: return@mapNotNull null
            val pressure = device.getMotionRange(MotionEvent.AXIS_PRESSURE, InputDevice.SOURCE_STYLUS)
            val tools = device.sources.let { sources -> buildList {
                if (sources and InputDevice.SOURCE_STYLUS == InputDevice.SOURCE_STYLUS) add("stylus-source")
                if (sources and InputDevice.SOURCE_TOUCHSCREEN == InputDevice.SOURCE_TOUCHSCREEN) add("touchscreen-source")
                if (sources and InputDevice.SOURCE_MOUSE == InputDevice.SOURCE_MOUSE) add("mouse-source")
            } }
            mapOf(
                "deviceId" to id, "name" to device.name, "sources" to device.sources,
                "tools" to tools, "pressureMin" to pressure?.min?.toDouble(),
                "pressureMax" to pressure?.max?.toDouble(),
                "pressureSupported" to (pressure != null && pressure.max > pressure.min),
            )
        }
    }
}
