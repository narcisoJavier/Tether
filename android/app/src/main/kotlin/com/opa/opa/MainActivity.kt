package com.opa.opa

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CPU_ABI_CHANNEL = "com.opa.app/cpu_abi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CPU_ABI_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getSupportedAbis") {
                result.success(Build.SUPPORTED_ABIS?.toList())
            } else {
                result.notImplemented()
            }
        }
    }
}
