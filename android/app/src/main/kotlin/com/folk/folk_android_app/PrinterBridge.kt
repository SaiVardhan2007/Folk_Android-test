package com.folk.folk_android_app

import android.annotation.SuppressLint
import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Receipt printer link for the Flutter app (channel "folk/printer").
 * Works with ESC/POS thermal printers over classic Bluetooth (SPP) or USB (OTG cable).
 * Based on the seznik_print Bluetooth bridge, extended with USB.
 */
@SuppressLint("MissingPermission")
class PrinterBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val context: Context = activity
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val io = Executors.newSingleThreadExecutor()
    private val ui = android.os.Handler(context.mainLooper)

    private var btSocket: BluetoothSocket? = null
    private var usbConn: UsbDeviceConnection? = null
    private var usbIface: UsbInterface? = null
    private var usbOut: UsbEndpoint? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var kind = "" // "bluetooth" | "usb" | ""
    private var name = ""

    init {
        MethodChannel(messenger, "folk/printer").setMethodCallHandler(::onCall)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bluetoothPermission" -> {
                if (Build.VERSION.SDK_INT < 31 ||
                    activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                    result.success("granted")
                } else {
                    pendingPermission?.success("denied")
                    pendingPermission = result
                    activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQ_BT)
                }
            }
            "openAppSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
                result.success(true)
            }
            "listBluetooth" -> {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) result.error("NO_BT", "This phone has no Bluetooth", null)
                else if (!adapter.isEnabled) result.error("BT_OFF", "Bluetooth is off. Turn it on and try again.", null)
                else result.success(adapter.bondedDevices.map {
                    mapOf("name" to (it.name ?: it.address), "id" to it.address)
                })
            }
            "listUsb" -> {
                val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
                result.success(usb.deviceList.values.filter { findOut(it) != null }.map {
                    mapOf("name" to (it.productName ?: "USB printer ${it.vendorId}:${it.productId}"), "id" to it.deviceName)
                })
            }
            "connectBluetooth" -> {
                val address = call.argument<String>("id")!!
                io.execute {
                    try {
                        closeAll()
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        stopDiscovery(adapter)
                        val dev = adapter.getRemoteDevice(address)
                        // Some printers ignore the normal (SDP-looked-up) connection and hang, so try other ways in turn.
                        val attempts: List<Pair<String, () -> BluetoothSocket>> = listOf(
                            // Insecure first: it never asks the user to confirm a pairing code. A "secure" connection to a printer whose pairing
                            // is stale (it was paired with another phone since) pops up a code prompt that ends in "incorrect code".
                            "insecure SPP" to { dev.createInsecureRfcommSocketToServiceRecord(sppUuid) },
                            "secure SPP" to { dev.createRfcommSocketToServiceRecord(sppUuid) },
                            "channel 1" to {
                                @Suppress("UNCHECKED_CAST")
                                dev.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                                    .invoke(dev, 1) as BluetoothSocket
                            },
                        )
                        var lastError = "unknown error"
                        var connected: BluetoothSocket? = null
                        for ((label, make) in attempts) {
                            var s: BluetoothSocket? = null
                            // connect() can hang for minutes on an unresponsive printer: cut it off after 12 s.
                            val watchdog = Runnable { try { s?.close() } catch (_: Exception) {} }
                            try {
                                stopDiscovery(adapter)
                                s = make()
                                ui.postDelayed(watchdog, 12_000)
                                s.connect()
                                connected = s
                                Log.i(TAG, "Connected to $address using $label")
                                break
                            } catch (e: Exception) {
                                lastError = "${e.message ?: e.javaClass.simpleName} ($label)"
                                Log.e(TAG, "Connect to $address failed using $label", e)
                                try { s?.close() } catch (_: Exception) {}
                                Thread.sleep(600)
                            } finally {
                                ui.removeCallbacks(watchdog)
                            }
                        }
                        if (connected == null) throw java.io.IOException(
                            "$lastError. Switch the printer off and on, make sure no other phone is connected to it, then try again."
                        )
                        btSocket = connected
                        kind = "bluetooth"; name = dev.name ?: address
                        ui.post { result.success(true) }
                    } catch (e: Exception) {
                        closeAll()
                        Log.e(TAG, "Bluetooth connect failed", e)
                        ui.post { result.error("CONNECT", "Could not connect: ${e.message}", null) }
                    }
                }
            }
            "connectUsb" -> connectUsb(call.argument<String>("id")!!, result)
            "write" -> {
                val data = call.argument<ByteArray>("data")!!
                io.execute {
                    try {
                        write(data)
                        ui.post { result.success(true) }
                    } catch (e: Exception) {
                        closeAll() // the link is broken: the app will ask to connect again
                        ui.post { result.error("WRITE", e.message ?: "Printer not responding", null) }
                    }
                }
            }
            "disconnect" -> io.execute { closeAll(); ui.post { result.success(true) } }
            "status" -> result.success(mapOf("connected" to isConnected(), "kind" to kind, "name" to name))
            else -> result.notImplemented()
        }
    }

    /** Android 12+ needs BLUETOOTH_SCAN for cancelDiscovery(). We never scan, so a refusal is harmless: ignore it. */
    private fun stopDiscovery(adapter: BluetoothAdapter) {
        try { adapter.cancelDiscovery() } catch (e: SecurityException) { Log.w(TAG, "cancelDiscovery skipped: ${e.message}") }
    }

    private fun isConnected(): Boolean = when (kind) {
        "bluetooth" -> btSocket?.isConnected == true
        "usb" -> usbConn != null && usbOut != null
        else -> false
    }

    private fun write(data: ByteArray) {
        when (kind) {
            "bluetooth" -> {
                val out = btSocket?.outputStream ?: throw IllegalStateException("Printer not connected")
                out.write(data); out.flush()
            }
            "usb" -> {
                val c = usbConn ?: throw IllegalStateException("Printer not connected")
                val ep = usbOut ?: throw IllegalStateException("Printer not connected")
                var off = 0
                val chunk = 16 * 1024
                while (off < data.size) {
                    val n = minOf(chunk, data.size - off)
                    val sent = c.bulkTransfer(ep, data, off, n, 5000)
                    if (sent <= 0) throw IllegalStateException("USB printer not responding")
                    off += sent
                }
            }
            else -> throw IllegalStateException("Printer not connected")
        }
    }

    // ---- USB
    private fun findOut(d: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        var fallback: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until d.interfaceCount) {
            val iface = d.getInterface(i)
            for (e in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    if (iface.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return iface to ep
                    if (fallback == null && iface.interfaceClass != UsbConstants.USB_CLASS_MASS_STORAGE) fallback = iface to ep
                }
            }
        }
        return fallback
    }

    private fun connectUsb(id: String, result: MethodChannel.Result) {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val dev = usb.deviceList.values.firstOrNull { it.deviceName == id }
        if (dev == null) { result.error("CONNECT", "USB printer not found. Re-plug the cable.", null); return }
        if (usb.hasPermission(dev)) { openUsb(usb, dev, result); return }
        val action = "${context.packageName}.USB_PERMISSION"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                context.unregisterReceiver(this)
                if (i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) openUsb(usb, dev, result)
                else result.error("CONNECT", "USB permission was denied.", null)
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pi = PendingIntent.getBroadcast(context, 0, Intent(action).setPackage(context.packageName), flags)
        usb.requestPermission(dev, pi)
    }

    private fun openUsb(usb: UsbManager, dev: UsbDevice, result: MethodChannel.Result) {
        io.execute {
            try {
                closeAll()
                val (iface, ep) = findOut(dev) ?: throw IllegalStateException("No printer port on this USB device")
                val conn = usb.openDevice(dev) ?: throw IllegalStateException("Could not open the USB device")
                if (!conn.claimInterface(iface, true)) { conn.close(); throw IllegalStateException("USB printer is busy") }
                usbConn = conn; usbIface = iface; usbOut = ep
                kind = "usb"; name = dev.productName ?: "USB printer"
                ui.post { result.success(true) }
            } catch (e: Exception) {
                closeAll()
                ui.post { result.error("CONNECT", "Could not connect: ${e.message}", null) }
            }
        }
    }

    private fun closeAll() {
        try { btSocket?.close() } catch (_: Exception) {}
        try { usbIface?.let { usbConn?.releaseInterface(it) } } catch (_: Exception) {}
        try { usbConn?.close() } catch (_: Exception) {}
        btSocket = null; usbConn = null; usbIface = null; usbOut = null
        kind = ""; name = ""
    }

    /** Called by MainActivity with the answer to the Bluetooth permission pop-up. */
    fun onPermissionResult(requestCode: Int, granted: Boolean, canAskAgain: Boolean) {
        if (requestCode != REQ_BT) return
        pendingPermission?.success(if (granted) "granted" else if (canAskAgain) "denied" else "blocked")
        pendingPermission = null
    }

    fun dispose() = closeAll()

    companion object { const val REQ_BT = 7731; const val TAG = "PrinterBridge" }
}
