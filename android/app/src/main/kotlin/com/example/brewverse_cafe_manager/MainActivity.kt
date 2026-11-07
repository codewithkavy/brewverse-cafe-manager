package com.example.brewverse_cafe_manager

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null
    @Volatile private var ownedSocket: BluetoothSocket? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brewverse/receipt_classic")
            .setMethodCallHandler { call, result ->
                if (call.method != "pairedPrinters" && call.method != "send") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                withPermissions(result) {
                    val adapter = getSystemService(BluetoothManager::class.java)?.adapter
                    if (adapter == null || !adapter.isEnabled) {
                        result.error("bluetooth_off", "Enable Bluetooth before printing.", null)
                        return@withPermissions
                    }
                    try {
                        if (call.method == "pairedPrinters") {
                            // Pair new Classic printers in Android Settings first. A bond
                            // is a candidate, not proof of an ESC/POS SPP endpoint.
                            val devices = adapter.bondedDevices.filter {
                                it.type == BluetoothDevice.DEVICE_TYPE_CLASSIC ||
                                it.type == BluetoothDevice.DEVICE_TYPE_DUAL
                            }.map { mapOf("name" to (it.name ?: "Paired device"), "address" to it.address) }
                            result.success(devices)
                        } else {
                            val address = call.argument<String>("address")!!
                            val bytes = call.argument<ByteArray>("bytes")!!
                            val device = adapter.getRemoteDevice(address)
                            if (device.bondState != BluetoothDevice.BOND_BONDED) {
                                result.error("not_paired", "Pair this Classic printer in Android Settings first.", null)
                                return@withPermissions
                            }
                            adapter.cancelDiscovery()
                            worker.execute {
                                var socket: BluetoothSocket? = null
                                val expired = AtomicBoolean(false)
                                try {
                                    socket = device.createRfcommSocketToServiceRecord(
                                        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB"))
                                    val active = socket
                                    ownedSocket = active
                                    val alarm = timer.schedule({
                                        expired.set(true)
                                        try { active.close() } catch (_: Exception) {}
                                    }, 45, TimeUnit.SECONDS)
                                    try {
                                        active.connect()
                                        for (chunk in bytes.toList().chunked(512)) {
                                            if (expired.get()) throw java.io.IOException("SPP deadline exceeded")
                                            active.outputStream.write(chunk.toByteArray())
                                        }
                                        active.outputStream.flush()
                                        if (expired.get()) throw java.io.IOException("SPP deadline exceeded")
                                    } finally { alarm.cancel(false) }
                                    main.post { result.success(null) }
                                } catch (error: Exception) {
                                    main.post { result.error(if (expired.get()) "timeout" else "spp_failed",
                                        "Receipt delivery uncertain: ${error.message}", null) }
                                } finally {
                                    try { socket?.close() } catch (_: Exception) {}
                                    ownedSocket = null
                                }
                            }
                        }
                    } catch (error: Exception) {
                        result.error("classic_failed", error.message, null)
                    }
                }
            }
    }

    private fun withPermissions(result: MethodChannel.Result, action: () -> Unit) {
        val permissions = if (Build.VERSION.SDK_INT >= 31)
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
            else emptyArray()
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { action(); return }
        if (pending != null) { result.error("busy", "Permission request already open.", null); return }
        pending = action
        pendingResult = result
        requestPermissions(missing.toTypedArray(), 7312)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code != 7312) return
        val action = pending
        val result = pendingResult
        pending = null
        pendingResult = null
        if (results.isNotEmpty() && results.all { it == PackageManager.PERMISSION_GRANTED }) action?.invoke()
        else result?.error("permission_denied", "Allow Nearby devices permission in Android Settings.", null)
    }

    override fun onDestroy() {
        try { ownedSocket?.close() } catch (_: Exception) {}
        worker.shutdownNow()
        timer.shutdownNow()
        super.onDestroy()
    }
}
