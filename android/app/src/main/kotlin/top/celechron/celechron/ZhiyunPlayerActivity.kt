package top.celechron.celechron

import android.app.Activity
import android.app.AlertDialog
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.Gravity
import android.view.OrientationEventListener
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
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

/**
 * 智云课堂内置播放器 Activity：
 * 支持一键横屏全屏、重力感应自动旋屏、倍速/换源切换、画中画（横向小窗）与网页版无缝回退。
 */
@OptIn(UnstableApi::class)
class ZhiyunPlayerActivity : Activity() {
    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_LIVINGROOM_URL = "livingroomUrl"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_STREAM_LABELS = "streamLabels"
        const val EXTRA_STREAM_URLS = "streamUrls"

        fun isDirectStreamUrl(targetUrl: String): Boolean {
            val lower = targetUrl.lowercase()
            if (lower.contains("livingroom")) return false
            return lower.contains(".mp4") ||
                lower.contains(".m3u8") ||
                lower.contains(".flv") ||
                lower.contains(".ts")
        }
    }

    private val streamCandidates = mutableListOf<Pair<String, String>>()
    private var webFallbackUrl: String = ""
    private var token: String = ""
    private var titleText: String = "智云课堂"

    private lateinit var rootLayout: LinearLayout
    private lateinit var topBar: LinearLayout
    private lateinit var container: FrameLayout
    private lateinit var sourceBtn: TextView
    private lateinit var speedBtn: TextView
    private lateinit var webBtn: TextView
    private lateinit var pipBtn: TextView
    private lateinit var rotateBtn: TextView
    private lateinit var fullscreenBtn: TextView

    private var activePlayer: ExoPlayer? = null
    private var activePlayerView: PlayerView? = null
    private var activeWebView: WebView? = null
    private var currentStreamIndex = 0
    private val speeds = floatArrayOf(1.0f, 1.25f, 1.5f, 2.0f, 0.75f)
    private var speedIndex = 0

    private var isFullscreen = false
    private var isFullscreenLocked = false
    private var sensorAutoRotate = true
    private var currentRequestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private var lastRotateTimeMs = 0L
    private var orientationListener: OrientationEventListener? = null
    private var customViewExitCallback: WebChromeClient.CustomViewCallback? = null
    private var exitWebFullscreen: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        parseIntentExtras(intent)
        buildUi()
        setupSensorRotation()
        updatePipParams()
        startPlayback()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        parseIntentExtras(intent)
        startPlayback()
    }

    private fun parseIntentExtras(intent: Intent?) {
        streamCandidates.clear()
        val seenUrls = mutableSetOf<String>()
        val rawUrl = intent?.getStringExtra(EXTRA_URL) ?: ""
        titleText = intent?.getStringExtra(EXTRA_TITLE)?.ifBlank { "智云课堂" } ?: "智云课堂"
        val rawLivingroom = intent?.getStringExtra(EXTRA_LIVINGROOM_URL) ?: ""
        token = intent?.getStringExtra(EXTRA_TOKEN) ?: ""
        val labels = intent?.getStringArrayListExtra(EXTRA_STREAM_LABELS) ?: arrayListOf()
        val urls = intent?.getStringArrayListExtra(EXTRA_STREAM_URLS) ?: arrayListOf()

        fun addCandidate(label: String, candidateUrl: String) {
            val trimmed = candidateUrl.trim()
            if (trimmed.isEmpty() || !seenUrls.add(trimmed)) return
            if (isDirectStreamUrl(trimmed) || trimmed.contains("cmc.zju.edu.cn")) {
                streamCandidates.add(Pair(label, trimmed))
            }
        }

        for (i in urls.indices) {
            val label = labels.getOrNull(i)?.ifBlank { "源${i + 1}" } ?: "源${i + 1}"
            addCandidate(label, urls[i])
        }
        if (rawUrl.isNotEmpty() && isDirectStreamUrl(rawUrl)) {
            addCandidate("默认源", rawUrl)
        }

        webFallbackUrl = when {
            rawLivingroom.isNotBlank() -> rawLivingroom.trim()
            rawUrl.isNotBlank() && !isDirectStreamUrl(rawUrl) -> rawUrl.trim()
            else -> ""
        }
    }

    private fun buildUi() {
        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.parseColor("#E61C1C1E"))
            setPadding(20, 28, 20, 16)
        }

        val closeBtn = makeBarButton("关闭", Color.parseColor("#0A84FF")) {
            finish()
        }

        val titleView = TextView(this).apply {
            text = titleText
            textSize = 14f
            setTextColor(Color.WHITE)
            maxLines = 1
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        sourceBtn = makeBarButton("换源", Color.WHITE) { showSourceDialog() }
        speedBtn = makeBarButton("1.0x", Color.WHITE) { cycleSpeed() }
        webBtn = makeBarButton("网页", Color.parseColor("#0A84FF")) {
            if (webFallbackUrl.isNotEmpty()) attachWebView(webFallbackUrl)
        }
        rotateBtn = makeBarButton("旋屏开", Color.parseColor("#64D2FF")) {
            sensorAutoRotate = !sensorAutoRotate
            rotateBtn.text = if (sensorAutoRotate) "旋屏开" else "旋屏关"
            if (!sensorAutoRotate && !isFullscreenLocked) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
            } else if (sensorAutoRotate) {
                orientationListener?.enable()
            }
        }
        pipBtn = makeBarButton("小窗", Color.parseColor("#30D158")) {
            enterPipMode()
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            pipBtn.visibility = View.GONE
        }
        fullscreenBtn = makeBarButton("横屏全屏", Color.WHITE) {
            toggleLandscapeFullscreen()
        }

        topBar.addView(closeBtn)
        topBar.addView(titleView)
        topBar.addView(sourceBtn)
        topBar.addView(speedBtn)
        topBar.addView(webBtn)
        topBar.addView(rotateBtn)
        topBar.addView(pipBtn)
        topBar.addView(fullscreenBtn)

        container = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }

        rootLayout.addView(topBar)
        rootLayout.addView(container)
        setContentView(rootLayout)
        refreshTopBarVisibility()
    }

    private fun makeBarButton(label: String, textColor: Int, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(textColor)
            setPadding(12, 8, 12, 8)
            setOnClickListener { onClick() }
        }
    }

    private fun refreshTopBarVisibility() {
        sourceBtn.visibility = if (activeWebView == null && streamCandidates.size > 1) View.VISIBLE else View.GONE
        speedBtn.visibility = if (activeWebView == null && streamCandidates.isNotEmpty()) View.VISIBLE else View.GONE
        webBtn.visibility = if (webFallbackUrl.isNotEmpty()) View.VISIBLE else View.GONE
    }

    private fun setupSensorRotation() {
        val listener = object : OrientationEventListener(this) {
            override fun onOrientationChanged(orientation: Int) {
                if (!sensorAutoRotate || orientation == ORIENTATION_UNKNOWN || isFinishing || isDestroyed) {
                    return
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
                    return
                }
                val now = System.currentTimeMillis()
                if (now - lastRotateTimeMs < 550) return

                val desired = when {
                    orientation in 65..115 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                    orientation in 245..295 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    !isFullscreenLocked && (orientation <= 22 || orientation >= 338) ->
                        ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    else -> null
                } ?: return

                if (desired != currentRequestedOrientation) {
                    lastRotateTimeMs = now
                    currentRequestedOrientation = desired
                    requestedOrientation = desired
                    val isLand = desired == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE ||
                        desired == ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                    applyFullscreenChrome(isLand)
                }
            }
        }
        if (listener.canDetectOrientation()) {
            listener.enable()
        }
        orientationListener = listener
    }

    private fun toggleLandscapeFullscreen() {
        if (!isFullscreen) {
            isFullscreenLocked = true
            currentRequestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            applyFullscreenChrome(true)
        } else {
            isFullscreenLocked = false
            currentRequestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            applyFullscreenChrome(false)
        }
    }

    private fun applyFullscreenChrome(fullscreen: Boolean) {
        isFullscreen = fullscreen
        fullscreenBtn.text = if (fullscreen) "退出全屏" else "横屏全屏"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
            topBar.visibility = View.GONE
            return
        }
        topBar.visibility = if (fullscreen) View.GONE else View.VISIBLE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                if (fullscreen) {
                    controller.hide(WindowInsets.Type.systemBars())
                    controller.systemBarsBehavior =
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                } else {
                    controller.show(WindowInsets.Type.systemBars())
                }
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (fullscreen) {
                (View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
            } else {
                View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(activePlayer != null)
                builder.setSeamlessResizeEnabled(true)
            }
            setPictureInPictureParams(builder.build())
        }
    }

    private fun enterPipMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(activePlayer != null)
                builder.setSeamlessResizeEnabled(true)
            }
            topBar.visibility = View.GONE
            activePlayerView?.useController = false
            activePlayerView?.hideController()
            enterPictureInPictureMode(builder.build())
        } catch (e: Exception) {
            topBar.visibility = if (isFullscreen) View.GONE else View.VISIBLE
            activePlayerView?.useController = true
            Toast.makeText(this, "当前设备不支持画中画小窗", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S) {
            if (activePlayer != null && !isInPictureInPictureMode) {
                enterPipMode()
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            topBar.visibility = View.GONE
            activePlayerView?.useController = false
            activePlayerView?.hideController()
        } else {
            topBar.visibility = if (isFullscreen) View.GONE else View.VISIBLE
            activePlayerView?.useController = true
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) return
        val landscape = newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE
        if (landscape != isFullscreen) {
            applyFullscreenChrome(landscape)
        }
    }

    private fun startPlayback() {
        if (streamCandidates.isNotEmpty()) {
            playStreamAt(0)
        } else {
            val fallback = webFallbackUrl.ifEmpty { intent?.getStringExtra(EXTRA_URL) ?: "" }
            if (fallback.isNotEmpty()) {
                attachWebView(fallback)
            }
        }
    }

    private fun playStreamAt(index: Int) {
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
        refreshTopBarVisibility()

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
                        this@ZhiyunPlayerActivity,
                        "直接流播放失败，切换网页播放器",
                        Toast.LENGTH_SHORT
                    ).show()
                    attachWebView(webFallbackUrl)
                } else {
                    Toast.makeText(
                        this@ZhiyunPlayerActivity,
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
            setFullscreenButtonClickListener { _ ->
                toggleLandscapeFullscreen()
            }
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        container.addView(playerView)
        activePlayer = player
        activePlayerView = playerView
        updatePipParams()
        player.setPlaybackParameters(PlaybackParameters(speeds[speedIndex]))
        player.setMediaItem(mediaBuilder.build())
        player.prepare()
        player.playWhenReady = true
    }

    private fun attachWebView(targetUrl: String) {
        if (targetUrl.isBlank()) return
        releasePlayer()
        activeWebView?.destroy()
        container.removeAllViews()

        val customViewHolder = FrameLayout(this).apply {
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        var fullscreenView: View? = null

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
                cookieManager.setCookie(h, "_token=$token; Domain=.zju.edu.cn; Path=/")
                cookieManager.setCookie(h, "token=$token; Domain=.zju.edu.cn; Path=/")
            }
            cookieManager.flush()
        }

        val escapedToken = token
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "")
        val injectJs = if (escapedToken.isNotEmpty()) {
            "try{localStorage.setItem('token','$escapedToken');localStorage.setItem('_token','$escapedToken');document.cookie='_token=$escapedToken;path=/';document.cookie='token=$escapedToken;path=/';}catch(e){}"
        } else {
            ""
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
            val chromeClient = object : WebChromeClient() {
                override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                    if (view == null) return
                    fullscreenView?.let { customViewHolder.removeView(it) }
                    fullscreenView = view
                    customViewExitCallback = callback
                    customViewHolder.addView(
                        view,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    )
                    customViewHolder.visibility = View.VISIBLE
                    isFullscreenLocked = true
                    currentRequestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    applyFullscreenChrome(true)
                }

                override fun onHideCustomView() {
                    fullscreenView?.let { customViewHolder.removeView(it) }
                    fullscreenView = null
                    customViewExitCallback?.onCustomViewHidden()
                    customViewExitCallback = null
                    customViewHolder.visibility = View.GONE
                    isFullscreenLocked = false
                    currentRequestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    applyFullscreenChrome(false)
                }
            }
            exitWebFullscreen = { chromeClient.onHideCustomView() }
            webChromeClient = chromeClient
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    super.onPageStarted(view, url, favicon)
                    if (injectJs.isNotEmpty()) {
                        view?.evaluateJavascript(injectJs, null)
                    }
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    if (injectJs.isNotEmpty()) {
                        view?.evaluateJavascript(injectJs, null)
                    }
                }

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
        refreshTopBarVisibility()
        updatePipParams()
        container.addView(
            wv,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        container.addView(customViewHolder)
    }

    private fun showSourceDialog() {
        if (streamCandidates.isEmpty()) return
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

    private fun cycleSpeed() {
        speedIndex = (speedIndex + 1) % speeds.size
        val spd = speeds[speedIndex]
        speedBtn.text = "${spd}x"
        activePlayer?.setPlaybackParameters(PlaybackParameters(spd))
    }

    private fun releasePlayer() {
        try {
            activePlayer?.stop()
            activePlayer?.release()
        } catch (_: Exception) {
        }
        activePlayer = null
        activePlayerView = null
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (isFullscreen) {
            if (customViewExitCallback != null) {
                exitWebFullscreen?.invoke()
            } else {
                toggleLandscapeFullscreen()
            }
            return
        }
        super.onBackPressed()
    }

    override fun onDestroy() {
        orientationListener?.disable()
        orientationListener = null
        releasePlayer()
        activeWebView?.destroy()
        activeWebView = null
        super.onDestroy()
    }
}
