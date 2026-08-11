package com.fern.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Точка входа Android плюс приём текста, выделенного в ЧУЖОМ приложении.
///
/// `ACTION_PROCESS_TEXT` кладёт Fern в системное меню выделения: выделил слово
/// в мессенджере или браузере — «Fern» стоит рядом с «Копировать». Текст
/// забирается один раз (`take`) и стирается: иначе он всплывал бы снова при
/// каждом возврате на экран.
class MainActivity : FlutterActivity() {
    private var pendingText: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingText = extractProcessText(intent)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fern/process_text",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        result.success(pendingText)
                        pendingText = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = extractProcessText(intent) ?: return
        // Приложение уже запущено (launchMode=singleTop): движок Dart жив, и
        // ждать запроса `take` неоткуда — шлём текст сами.
        pendingText = text
        channel?.invokeMethod("onText", text)
    }

    private fun extractProcessText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_PROCESS_TEXT) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            ?: return null
        return text.toString().trim().ifEmpty { null }
    }
}
