package top.celechron.celechron

import android.app.Dialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.StrictMode
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.MimeTypeMap
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.MediaController
import android.widget.TextView
import android.widget.VideoView
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
                    result.success(showInAppVideoDialog(url, title))
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

    private fun showInAppVideoDialog(url: String, title: String): Boolean {
        if (url.isEmpty()) return false
        return try {
            runOnUiThread {
                val dialog = Dialog(this, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
                val root = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setBackgroundColor(Color.BLACK)
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }

                val topBar = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setBackgroundColor(Color.parseColor("#E61C1C1E"))
                    setPadding(36, 48, 36, 28)
                }

                val closeBtn = TextView(this).apply {
                    text = "关闭"
                    textSize = 15f
                    setTextColor(Color.parseColor("#0A84FF"))
                    setPadding(16, 8, 24, 8)
                    setOnClickListener { dialog.dismiss() }
                }

                val titleView = TextView(this).apply {
                    text = title
                    textSize = 15f
                    setTextColor(Color.WHITE)
                    maxLines = 1
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                }

                topBar.addView(closeBtn)
                topBar.addView(titleView)
                root.addView(topBar)

                val container = FrameLayout(this).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        0,
                        1f
                    )
                }

                val lower = url.lowercase()
                val isDirectStream = lower.contains(".mp4") || lower.contains(".m3u8")
                var activeWebView: WebView? = null

                fun attachWebView(targetUrl: String) {
                    container.removeAllViews()
                    val wv = WebView(this).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        settings.loadWithOverviewMode = true
                        settings.useWideViewPort = true
                        webChromeClient = WebChromeClient()
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(
                                view: WebView?,
                                request: WebResourceRequest?
                            ): Boolean = false
                        }
                        loadUrl(
                            targetUrl,
                            mapOf(
                                "Referer" to "https://classroom.zju.edu.cn/",
                                "Origin" to "https://classroom.zju.edu.cn"
                            )
                        )
                    }
                    activeWebView = wv
                    container.addView(
                        wv,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    )
                }

                if (isDirectStream) {
                    val videoView = VideoView(this)
                    val mediaController = MediaController(this)
                    mediaController.setAnchorView(videoView)
                    videoView.setMediaController(mediaController)
                    videoView.setVideoURI(
                        Uri.parse(url),
                        mapOf(
                            "Referer" to "https://classroom.zju.edu.cn/",
                            "Origin" to "https://classroom.zju.edu.cn"
                        )
                    )
                    videoView.setOnPreparedListener { mp ->
                        mp.isLooping = false
                        videoView.start()
                    }
                    videoView.setOnErrorListener { _, _, _ ->
                        attachWebView(url)
                        true
                    }
                    container.addView(
                        videoView,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            Gravity.CENTER
                        )
                    )
                } else {
                    attachWebView(url)
                }

                root.addView(container)
                dialog.setContentView(root)
                dialog.setOnDismissListener {
                    activeWebView?.destroy()
                }
                dialog.show()
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
