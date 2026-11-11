package top.celechron.celechron

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.StrictMode
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                "openFileWithSystem" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val rawMime = call.argument<String>("mimeType") ?: ""
                    val title = call.argument<String>("title") ?: "选择打开方式"
                    result.success(openFileWithSystem(filePath, rawMime, title))
                }
                "openInAppVideoPlayer" -> {
                    val url = call.argument<String>("url") ?: ""
                    val title = call.argument<String>("title") ?: "智云课堂"
                    val rawStreams = call.argument<List<Map<String, Any?>>>("streams") ?: emptyList()
                    val streams = rawStreams.mapNotNull { item ->
                        val sUrl = item["url"]?.toString()?.trim() ?: ""
                        if (sUrl.isEmpty()) null else Pair(
                            item["label"]?.toString()?.trim()?.ifEmpty { "视频源" } ?: "视频源",
                            sUrl
                        )
                    }
                    val livingroomUrl = call.argument<String>("livingroomUrl") ?: ""
                    val token = call.argument<String>("token") ?: ""
                    result.success(showInAppVideoDialog(url, title, streams, livingroomUrl, token))
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    result.success(installApk(filePath))
                }
                else -> result.notImplemented()
            }
        }

        // Deliver pending route if opened from widget before engine ready
        pendingRoute?.let { target ->
            channel.invokeMethod("onWidgetRoute", mapOf("target" to target))
        }
    }

    private fun installApk(filePath: String): Boolean {
        if (filePath.isEmpty()) return false
        return try {
            val file = File(filePath)
            if (!file.exists()) return false
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            openFileWithSystem(filePath, "application/vnd.android.package-archive", "安装更新")
        }
    }

    private fun openFileWithSystem(filePath: String, rawMime: String, title: String): Boolean {
        if (filePath.isEmpty()) return false
        return try {
            val builder = StrictMode.VmPolicy.Builder()
            StrictMode.setVmPolicy(builder.build())
            val uri = if (filePath.startsWith("content://") || filePath.startsWith("file://")) {
                Uri.parse(filePath)
            } else {
                Uri.fromFile(File(filePath))
            }
            val ext = MimeTypeMap.getFileExtensionFromUrl(filePath)?.lowercase() ?: ""
            val mime = when {
                rawMime.isNotEmpty() -> rawMime
                ext.isNotEmpty() -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
                else -> "*/*"
            }
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(viewIntent, title.ifEmpty { "选择打开方式" }).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun showInAppVideoDialog(
        url: String,
        title: String,
        streams: List<Pair<String, String>> = emptyList(),
        livingroomUrl: String = "",
        token: String = ""
    ): Boolean {
        if (url.isEmpty() && livingroomUrl.isEmpty() && streams.isEmpty()) return false
        return try {
            val labels = ArrayList<String>(streams.map { it.first })
            val urls = ArrayList<String>(streams.map { it.second })
            val playerIntent = Intent(this, ZhiyunPlayerActivity::class.java).apply {
                putExtra(ZhiyunPlayerActivity.EXTRA_URL, url)
                putExtra(ZhiyunPlayerActivity.EXTRA_TITLE, title)
                putExtra(ZhiyunPlayerActivity.EXTRA_LIVINGROOM_URL, livingroomUrl)
                putExtra(ZhiyunPlayerActivity.EXTRA_TOKEN, token)
                putStringArrayListExtra(ZhiyunPlayerActivity.EXTRA_STREAM_LABELS, labels)
                putStringArrayListExtra(ZhiyunPlayerActivity.EXTRA_STREAM_URLS, urls)
            }
            startActivity(playerIntent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
