package com.bufang.supercollection

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "com.bufang.supercollection/share"
  private var methodChannel: MethodChannel? = null
  private var pendingSharedText: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    captureSharedText(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    captureSharedText(intent)
    pendingSharedText?.let { text ->
      methodChannel?.invokeMethod("onSharedText", text)
      pendingSharedText = null
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    methodChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getSharedText" -> {
          val text = pendingSharedText
          pendingSharedText = null
          result.success(text)
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun captureSharedText(intent: Intent?) {
    if (intent == null) return
    if (intent.action != Intent.ACTION_SEND) return
    val type = intent.type ?: return
    if (!type.startsWith("text/")) return
    val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
    if (text.isNotEmpty()) {
      pendingSharedText = text
    }
  }
}
