package top.celechron.celechron

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val WIDGET_CHANNEL = "top.celechron.celechron/widget"
        const val PREFS_NAME = "HelechronWidgetPrefs"
        const val EXTRA_TARGET = "target"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val target = intent?.getStringExtra(EXTRA_TARGET)
            ?: intent?.data?.host?.takeIf { it.isNotEmpty() }
        if (!target.isNullOrEmpty()) {
            pendingRoute = target
            widgetChannel?.invokeMethod("onWidgetRoute", mapOf("target" to target))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        widgetChannel = channel

        channel.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            when (call.method) {
                "updateCourseWidget" -> {
                    val coursesJson = call.argument<String>("coursesJson") ?: "[]"
                    val leadWindowMinutes = call.argument<Int>("leadWindowMinutes") ?: 120
                    prefs.edit()
                        .putString("coursesJson", coursesJson)
                        .putInt("leadWindowMinutes", leadWindowMinutes)
                        .apply()
                    CourseWidgetProvider.updateAll(context)
                    result.success(true)
                }
                "updatePaymentCodeWidget" -> {
                    val paymentCode = call.argument<String>("paymentCode") ?: ""
                    val displayName = call.argument<String>("displayName") ?: "付款码"
                    prefs.edit()
                        .putString("paymentCode", paymentCode)
                        .putString("displayName", displayName)
                        .apply()
                    PaymentCodeWidgetProvider.updateAll(context)
                    result.success(true)
                }
                "setWidgetData" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key != null && value != null) {
                        prefs.edit().putString(key, value).apply()
                    }
                    result.success(true)
                }
                "consumePendingRoute" -> {
                    val route = pendingRoute
                    pendingRoute = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }

        // Deliver pending route if opened from widget before engine ready
        pendingRoute?.let { target ->
            channel.invokeMethod("onWidgetRoute", mapOf("target" to target))
        }
    }
}
