package com.folk.folk_android_app

import android.Manifest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var printer: PrinterBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printer = PrinterBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        val canAsk = shouldShowRequestPermissionRationale(Manifest.permission.BLUETOOTH_CONNECT)
        printer?.onPermissionResult(requestCode, granted, canAsk)
    }

    override fun onDestroy() {
        printer?.dispose()
        super.onDestroy()
    }
}
