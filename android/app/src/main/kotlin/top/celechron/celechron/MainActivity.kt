package top.celechron.celechron

import android.app.AlertDialog
import android.app.Dialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.StrictMode
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
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

    private fun isDirectStreamUrl(targetUrl: String): Boolean {
        val lower = targetUrl.lowercase()
        if (lower.contains("livingroom")) return false
        return lower.contains(".mp4") ||
            lower.contains(".m3u8") ||
            lower.contains(".flv") ||
            lower.contains(".ts")
    }

    @OptIn(UnstableApi::class)
    private fun showInAppVideoDialog(
        url: String,
        title: String,
        streams: List<Pair<String, String>> = emptyList(),
        livingroomUrl: String = "",
        token: String = ""
    ): Boolean {
        if (url.isEmpty() && livingroomUrl.isEmpty() && streams.isEmpty()) return false
        return try {
            runOnUiThread {
                val streamCandidates = mutableListOf<Pair<String, String>>()
                val seenUrls = mutableSetOf<String>()
                fun addCandidate(label: String, candidateUrl: String) {
                    val trimmed = candidateUrl.trim()
                    if (trimmed.isEmpty() || !seenUrls.add(trimmed)) return
                    if (isDirectStreamUrl(trimmed) || trimmed.contains("cmc.zju.edu.cn")) {
                        streamCandidates.add(Pair(label, trimmed))
                    }
                }
                streams.forEach { addCandidate(it.first, it.second) }
                if (url.isNotEmpty() && isDirectStreamUrl(url)) {
                    addCandidate("默认源", url)
                }

                val webFallbackUrl = when {
                    livingroomUrl.isNotBlank() -> livingroomUrl.trim()
                    url.isNotBlank() && !isDirectStreamUrl(url) -> url.trim()
                    else -> ""
                }

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
                    setPadding(24, 42, 24, 22)
                }

                val closeBtn = TextView(this).apply {
                    text = "关闭"
                    textSize = 15f
                    setTextColor(Color.parseColor("#0A84FF"))
                    setPadding(12, 8, 20, 8)
                    setOnClickListener { dialog.dismiss() }
                }

                val titleView = TextView(this).apply {
                    text = title
                    textSize = 15f
                    setTextColor(Color.WHITE)
                    maxLines = 1
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                }

                val container = FrameLayout(this).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        0,
                        1f
                    )
                }

                var activePlayer: ExoPlayer? = null
                var activeWebView: WebView? = null
                var currentStreamIndex = 0
                val speeds = floatArrayOf(1.0f, 1.25f, 1.5f, 2.0f, 0.75f)
                var speedIndex = 0

                val sourceBtn = TextView(this).apply {
                    text = "换源"
                    textSize = 14f
                    setTextColor(Color.WHITE)
                    setPadding(14, 8, 14, 8)
                    visibility = if (streamCandidates.size > 1) View.VISIBLE else View.GONE
                }

                val speedBtn = TextView(this).apply {
                    text = "1.0x"
                    textSize = 14f
                    setTextColor(Color.WHITE)
                    setPadding(14, 8, 14, 8)
                    visibility = if (streamCandidates.isNotEmpty()) View.VISIBLE else View.GONE
                }

                val webBtn = TextView(this).apply {
                    text = "网页版"
                    textSize = 14f
                    setTextColor(Color.parseColor("#0A84FF"))
                    setPadding(14, 8, 8, 8)
                    visibility = if (webFallbackUrl.isNotEmpty()) View.VISIBLE else View.GONE
                }

                topBar.addView(closeBtn)
                topBar.addView(titleView)
                topBar.addView(sourceBtn)
                topBar.addView(speedBtn)
                topBar.addView(webBtn)
                root.addView(topBar)
                root.addView(container)

                fun releasePlayer() {
                    try {
                        activePlayer?.stop()
                        activePlayer?.release()
                    } catch (_: Exception) {
                    }
                    activePlayer = null
                }

                fun attachWebView(targetUrl: String) {
                    if (targetUrl.isBlank()) return
                    releasePlayer()
                    activeWebView?.destroy()
                    container.removeAllViews()
                    speedBtn.visibility = View.GONE
                    sourceBtn.visibility = View.GONE

                    val customViewHolder = FrameLayout(this).apply {
                        visibility = View.GONE
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    }

                    var fullscreenView: View? = null
                    var fullscreenCallback: WebChromeClient.CustomViewCallback? = null

                    val cookieManager = CookieManager.getInstance()
                    cookieManager.setAcceptCookie(true)
                    if (token.isNotBlank()) {
                        val hosts = listOf(
                            "https://classroom.zju.edu.cn",
                            "https://yjapi.cmc.zju.edu.cn",
                            "https://tgmedia.cmc.zju.edu.cn"
                        )
                        for (h in hosts) {
                            cookieManager.setCookie(h, "_token=$token; Path=/")
                            cookieManager.setCookie(h, "token=$token; Path=/")
                        }
                        cookieManager.flush()
                    }

                    val wv = WebView(this).apply {
                        setBackgroundColor(Color.BLACK)
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                        settings.loadWithOverviewMode = true
                        settings.useWideViewPort = true
                        settings.userAgentString =
                            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
                        cookieManager.setAcceptThirdPartyCookies(this, true)
                        webChromeClient = object : WebChromeClient() {
                            override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                                if (view == null) return
                                fullscreenView?.let { customViewHolder.removeView(it) }
                                fullscreenView = view
                                fullscreenCallback = callback
                                customViewHolder.addView(
                                    view,
                                    FrameLayout.LayoutParams(
                                        ViewGroup.LayoutParams.MATCH_PARENT,
                                        ViewGroup.LayoutParams.MATCH_PARENT
                                    )
                                )
                                customViewHolder.visibility = View.VISIBLE
                            }

                            override fun onHideCustomView() {
                                fullscreenView?.let { customViewHolder.removeView(it) }
                                fullscreenView = null
                                fullscreenCallback?.onCustomViewHidden()
                                fullscreenCallback = null
                                customViewHolder.visibility = View.GONE
                            }
                        }
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(
                                view: WebView?,
                                request: WebResourceRequest?
                            ): Boolean {
                                val nextUrl = request?.url?.toString() ?: return false
                                return !(nextUrl.startsWith("http://") || nextUrl.startsWith("https://"))
                            }
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
                    container.addView(customViewHolder)
                }

                fun playStreamAt(index: Int) {
                    if (index < 0 || index >= streamCandidates.size) {
                        if (webFallbackUrl.isNotEmpty()) {
                            Toast.makeText(this, "视频流加载失败，正在切换网页播放", Toast.LENGTH_SHORT).show()
                            attachWebView(webFallbackUrl)
                        }
                        return
                    }
                    currentStreamIndex = index
                    val streamUrl = streamCandidates[index].second
                    activeWebView?.destroy()
                    activeWebView = null
                    releasePlayer()
                    container.removeAllViews()
                    speedBtn.visibility = View.VISIBLE
                    sourceBtn.visibility = if (streamCandidates.size > 1) View.VISIBLE else View.GONE

                    val headers = mutableMapOf(
                        "Referer" to "https://classroom.zju.edu.cn/",
                        "Origin" to "https://classroom.zju.edu.cn",
                        "User-Agent" to "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
                    )
                    if (token.isNotBlank()) {
                        headers["Cookie"] = "_token=$token; token=$token"
                        headers["Authorization"] = "Bearer $token"
                    }

                    val dataSourceFactory = DefaultHttpDataSource.Factory()
                        .setAllowCrossProtocolRedirects(true)
                        .setConnectTimeoutMs(15000)
                        .setReadTimeoutMs(20000)
                        .setDefaultRequestProperties(headers)

                    val player = ExoPlayer.Builder(this)
                        .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
                        .build()

                    val mediaBuilder = MediaItem.Builder().setUri(streamUrl)
                    if (streamUrl.lowercase().contains(".m3u8")) {
                        mediaBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
                    }

                    player.addListener(object : Player.Listener {
                        override fun onPlayerError(error: PlaybackException) {
                            val nextIdx = currentStreamIndex + 1
                            if (nextIdx < streamCandidates.size) {
                                playStreamAt(nextIdx)
                            } else if (webFallbackUrl.isNotEmpty()) {
                                Toast.makeText(
                                    this@MainActivity,
                                    "直接流播放失败，切换网页播放器",
                                    Toast.LENGTH_SHORT
                                ).show()
                                attachWebView(webFallbackUrl)
                            } else {
                                Toast.makeText(
                                    this@MainActivity,
                                    "播放失败: ${error.errorCodeName}",
                                    Toast.LENGTH_LONG
                                ).show()
                            }
                        }
                    })

                    val playerView = PlayerView(this).apply {
                        this.player = player
                        useController = true
                        setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    }

                    container.addView(playerView)
                    activePlayer = player
                    player.setPlaybackParameters(PlaybackParameters(speeds[speedIndex]))
                    player.setMediaItem(mediaBuilder.build())
                    player.prepare()
                    player.playWhenReady = true
                }

                speedBtn.setOnClickListener {
                    speedIndex = (speedIndex + 1) % speeds.size
                    val spd = speeds[speedIndex]
                    speedBtn.text = "${spd}x"
                    activePlayer?.setPlaybackParameters(PlaybackParameters(spd))
                }

                sourceBtn.setOnClickListener {
                    if (streamCandidates.isEmpty()) return@setOnClickListener
                    val labels = streamCandidates.map { it.first }.toTypedArray()
                    AlertDialog.Builder(this)
                        .setTitle("选择视频源")
                        .setSingleChoiceItems(labels, currentStreamIndex) { dlg, which ->
                            dlg.dismiss()
                            playStreamAt(which)
                        }
                        .setNegativeButton("取消", null)
                        .show()
                }

                webBtn.setOnClickListener {
                    if (webFallbackUrl.isNotEmpty()) {
                        attachWebView(webFallbackUrl)
                    }
                }

                if (streamCandidates.isNotEmpty()) {
                    playStreamAt(0)
                } else {
                    attachWebView(webFallbackUrl.ifEmpty { url })
                }

                dialog.setContentView(root)
                dialog.setOnDismissListener {
                    releasePlayer()
                    activeWebView?.destroy()
                    activeWebView = null
                }
                dialog.show()
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
