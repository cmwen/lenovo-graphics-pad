package com.cmwen.lenovo_graphics_pad

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Foreground-only native input pipeline. No exported control service or boot daemon. */
@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var surface: PadSurface? = null
    private var options = emptyMap<String, Any?>()
    private var selected = "usb"
    private var foreground = false
    private var error: String? = null
    private var permissionAction: String? = null
    private var txReports = 0L
    private var droppedReports = 0L
    private var sampleAt = 0L
    private var statePending = false
    private var receiverRegistered = false
    private val bonds = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { publishHosts() }
    }
    private fun publishHosts() {
        if (selected == "bluetooth") sink?.success(mapOf("kind" to "hosts", "hosts" to bt.pairedHosts()))
    }
    private val bt by lazy { BluetoothPenTransport(this, handler, { emit() }, { fail(it) }) }
    private val usb by lazy { UsbHidTransport(this, handler, object : UsbHidTransport.Listener {
        override fun onRegistered(registered: Boolean) { emit() }
        override fun onConnection(connected: Boolean) { surface?.release(); emit() }
        override fun onReport(data: ByteArray) {} // Input-only pen descriptor.
        override fun onError(message: String) { fail(message) }
        override fun onChanged() { emit() }
        override fun onSent() { txReports++; emit() }
    }) }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        selected = getSharedPreferences("pad", MODE_PRIVATE).getString("transport", "usb") ?: "usb"
        engine.platformViewsController.registry.registerViewFactory("graphics_pad/surface", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, id: Int, args: Any?): PlatformView {
                surface?.release()
                val view = PadSurface(context, { send(it) }, { sample(it) })
                surface = view
                view.configure(options)
                return object : PlatformView {
                    override fun getView(): View = view
                    override fun dispose() { view.release(); if (surface === view) surface = null }
                }
            }
        })
        EventChannel(engine.dartExecutor.binaryMessenger, "graphics_pad/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events; events.success(state()) }
            override fun onCancel(args: Any?) { sink = null }
        })
        MethodChannel(engine.dartExecutor.binaryMessenger, "graphics_pad/control").setMethodCallHandler { call, result ->
            try { handle(call, result) }
            catch (e: Exception) { fail(e.message ?: "Pad operation failed"); result.error("pad", error, null) }
        }
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(bonds, filter, Context.RECEIVER_EXPORTED)
        else registerReceiver(bonds, filter)
        receiverRegistered = true
        // Only a previous interrupted USB session can trigger recovery on opening.
        usb.recoverIfNeeded { emit() }
    }

    private fun state(): Map<String, Any?> {
        val bluetooth = selected == "bluetooth"
        return mapOf(
            "kind" to "state", "transport" to selected,
            "registered" to if (bluetooth) bt.registered else usb.active,
            "connected" to if (bluetooth) bt.connected else usb.connected,
            "busy" to (usb.busy || bt.busy || permissionAction != null),
            "status" to if (bluetooth) bt.status else usb.status,
            "hostName" to if (bluetooth) bt.hostName else if (usb.connected) "USB host" else null,
            "error" to error, "txReports" to txReports, "droppedReports" to droppedReports,
        )
    }

    private fun emit() {
        if (statePending) return
        statePending = true
        handler.postDelayed({ statePending = false; sink?.success(state()) }, 32)
    }
    private fun fail(message: String) { error = message; emit() }
    private fun sample(detail: Map<String, Any?>) {
        val now = SystemClock.uptimeMillis()
        if (now - sampleAt < 33 && detail["tip"] == true) return
        sampleAt = now
        sink?.success(detail + ("kind" to "sample"))
    }
    private fun send(body: ByteArray): Boolean {
        if (!foreground) return false
        val ready = if (selected == "usb") usb.active && usb.connected else bt.registered && bt.connected
        if (!ready) return false // Local ink remains usable without a host.
        val accepted = if (selected == "usb") usb.send(body) else bt.send(body)
        if (accepted && selected == "bluetooth") txReports++
        if (!accepted) droppedReports++
        emit()
        return accepted
    }

    private fun stopAll() {
        surface?.release()
        bt.stop()
        usb.stop()
        permissionAction = null
        emit()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(state())
            "capabilities" -> result.success(PadSurface.capabilities())
            "pairedHosts" -> result.success(bt.pairedHosts())
            "configure" -> {
                @Suppress("UNCHECKED_CAST")
                val values = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                options = values.toMap()
                surface?.configure(options)
                result.success(null)
            }
            "clear" -> { surface?.clear(); result.success(null) }
            "start" -> {
                check(foreground) { "Keep Graphics Pad visible to start a session" }
                check(!usb.busy && !bt.busy && permissionAction == null) { "Wait for the current transport operation" }
                val transport = call.argument<String>("transport") ?: selected
                require(transport == "usb" || transport == "bluetooth") { "Choose USB or Bluetooth" }
                if (transport != selected) {
                    check(!usb.active && !bt.registered) { "Stop the current transport before switching" }
                    selected = transport
                    getSharedPreferences("pad", MODE_PRIVATE).edit().putString("transport", selected).apply()
                }
                error = null
                prepareDescriptor()
                if (selected == "usb") usb.start() else withBluetoothPermission("start") { bt.start() }
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                emit(); result.success(null)
            }
            "selectTransport" -> {
                check(!usb.busy && !bt.busy && !usb.active && !bt.registered && permissionAction == null) { "Stop and wait for the current transport before switching" }
                val transport = call.argument<String>("transport")
                require(transport == "usb" || transport == "bluetooth") { "Choose USB or Bluetooth" }
                selected = transport!!
                error = null
                getSharedPreferences("pad", MODE_PRIVATE).edit().putString("transport", selected).apply()
                emit(); result.success(null)
            }
            "stop" -> { stopAll(); result.success(null) }
            "recoverUsb" -> {
                surface?.release(); bt.stop(); permissionAction = null; error = null
                usb.recover { restored -> if (restored) error = null; emit() }
                emit(); result.success(null)
            }
            "discoverable" -> {
                check(selected == "bluetooth") { "Choose Bluetooth to pair a host" }
                withBluetoothPermission("discoverable") { makeDiscoverable() }
                result.success(null)
            }
            "connect" -> {
                check(selected == "bluetooth") { "Choose Bluetooth to connect a paired host" }
                bt.connect(call.argument<String>("address") ?: "")
                result.success(null)
            }
            "disconnect" -> {
                surface?.release()
                if (selected == "bluetooth") bt.disconnect() else usb.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun prepareDescriptor() {
        val view = surface ?: error("Wait for the pad surface to appear")
        check(view.width > 0 && view.height > 0) { "Wait for the pad surface to finish layout" }
        val dm = resources.displayMetrics
        check(dm.xdpi.isFinite() && dm.ydpi.isFinite() && dm.xdpi > 0 && dm.ydpi > 0) { "Android did not report physical display dimensions" }
        val widthFraction = (options["activeWidth"] as? Number)?.toDouble()?.coerceIn(0.1, 1.0) ?: 1.0
        val heightFraction = (options["activeHeight"] as? Number)?.toDouble()?.coerceIn(0.1, 1.0) ?: 1.0
        var w = (view.width / dm.xdpi * 254.0 * widthFraction).toInt().coerceIn(1, 32767)
        var h = (view.height / dm.ydpi * 254.0 * heightFraction).toInt().coerceIn(1, 32767)
        if ((options["rotation"] as? Number)?.toInt() in listOf(90, 270)) { val old = w; w = h; h = old }
        PenProtocol.activeDescriptor = PenProtocol.descriptor(w, h)
    }

    private fun withBluetoothPermission(action: String, operation: () -> Unit) {
        val missing = if (Build.VERSION.SDK_INT >= 31) listOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
            .filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED } else emptyList()
        if (missing.isEmpty()) { operation(); return }
        permissionAction = action
        requestPermissions(missing.toTypedArray(), 93)
        emit()
    }
    private fun makeDiscoverable() {
        startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120), 94)
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code != 93) return
        val action = permissionAction
        permissionAction = null
        if (results.isEmpty() || results.any { it != PackageManager.PERMISSION_GRANTED }) fail("Bluetooth permission was denied. Allow Nearby devices in Android app settings.")
        else if (foreground) when (action) { "start" -> bt.start(); "discoverable" -> makeDiscoverable() }
        emit()
    }

    override fun onResume() { super.onResume(); foreground = true; window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); emit(); publishHosts() }
    override fun onPause() { surface?.release(); super.onPause() }
    override fun onStop() { stopAll(); foreground = false; window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); super.onStop() }
    override fun onDestroy() {
        if (receiverRegistered) { unregisterReceiver(bonds); receiverRegistered = false }
        surface?.release(); bt.close(); usb.stop(); sink = null; super.onDestroy()
    }
}
