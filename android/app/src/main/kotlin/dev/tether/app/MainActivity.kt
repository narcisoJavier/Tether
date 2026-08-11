package dev.tether.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CPU_ABI_CHANNEL = "dev.tether.app/cpu_abi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CPU_ABI_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSupportedAbis") {
                val abis = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    Build.SUPPORTED_ABIS.toList()
                } else {
                    listOf(Build.CPU_ABI, Build.CPU_ABI2).filter { it.isNotEmpty() }
                }
                result.success(abis)
            } else {
                result.notImplemented()
            }
        }
    }
}
