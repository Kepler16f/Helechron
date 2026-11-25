package top.celechron.celechron

import android.app.AlertDialog
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.net.http.SslError
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JsResult
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ZhiyunInlinePlayerFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return ZhiyunInlinePlayerView(context, messenger, viewId, params)
    }
}

@OptIn(UnstableApi::class)
class ZhiyunInlinePlayerView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    initialArgs: Map<String, Any?>
) : PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        private val SAKURA_ACCENT = Color.parseColor("#FB7299")
    }

    private enum class IconKind { PLAY, PAUSE, FULLSCREEN }

    private class InlineIconDrawable(
        private val kind: IconKind,
        private val color: Int,
        private val intrinsicPx: Int
    ) : Drawable() {
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = this@InlineIconDrawable.color
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = this@InlineIconDrawable.color
            style = Paint.Style.FILL
        }

        override fun getIntrinsicWidth(): Int = intrinsicPx
        override fun getIntrinsicHeight(): Int = intrinsicPx

        override fun draw(canvas: Canvas) {
            val b = bounds
            val w = b.width().toFloat()
            val h = b.height().toFloat()
            if (w <= 0f || h <= 0f) return
            val s = minOf(w, h) / 24f
            val ox = b.left + (w - 24f * s) / 2f
            val oy = b.top + (h - 24f * s) / 2f
            canvas.save()
            canvas.translate(ox, oy)
            strokePaint.strokeWidth = 2.15f * s

            when (kind) {
                IconKind.PLAY -> {
                    val p = Path().apply {
                        moveTo(7.5f * s, 5.0f * s)
                        lineTo(19.0f * s, 12.0f * s)
                        lineTo(7.5f * s, 19.0f * s)
                        close()
                    }
                    canvas.drawPath(p, fillPaint)
                }
                IconKind.PAUSE -> {
                    canvas.drawRoundRect(RectF(6.5f * s, 5.2f * s, 10.3f * s, 18.8f * s), 1.2f * s, 1.2f * s, fillPaint)
                    canvas.drawRoundRect(RectF(13.7f * s, 5.2f * s, 17.5f * s, 18.8f * s), 1.2f * s, 1.2f * s, fillPaint)
                }
                IconKind.FULLSCREEN -> {
                    val p = Path().apply {
                        moveTo(4f * s, 9.2f * s); lineTo(4f * s, 4f * s); lineTo(9.2f * s, 4f * s)
                        moveTo(14.8f * s, 4f * s); lineTo(20f * s, 4f * s); lineTo(20f * s, 9.2f * s)
                        moveTo(20f * s, 14.8f * s); lineTo(20f * s, 20f * s); lineTo(14.8f * s, 20f * s)
                        moveTo(9.2f * s, 20f * s); lineTo(4f * s, 20f * s); lineTo(4f * s, 14.8f * s)
                    }
                    canvas.drawPath(p, strokePaint)
                }
            }
            canvas.restore()
        }

        override fun setAlpha(alpha: Int) {
            strokePaint.alpha = alpha
            fillPaint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            strokePaint.colorFilter = colorFilter
            fillPaint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private fun dp(v: Int): Int =
        (v * context.resources.displayMetrics.density).toInt().coerceAtLeast(if (v > 0) 1 else 0)

    private val channel = MethodChannel(messenger, "helechron/zhiyun_inline_player_$viewId")
    private val mainHandler = Handler(Looper.getMainLooper())

    private var rawInitialUrl = ""
    private var titleText = "智云课堂"
    private var webFallbackUrl = ""
    private var token = ""
    private var ssoCookie = ""
    private var zhiyunCookies = ""
    private var preferWeb = false
    private var isLiveStream = false
    private val streamCandidates = mutableListOf<Pair<String, String>>()

    private var activePlayer: ExoPlayer? = null
    private var activeWebView: WebView? = null
    private var currentStreamIndex = 0
    private val speeds = floatArrayOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    private var speedIndex = 1
    private var controlsVisible = true
    private var isUserSeeking = false
    private var pendingSeekMs = 0L
    private var pendingAutoPlay = true

    private val rootFrame: FrameLayout
    private val videoContainer: FrameLayout
    private val gestureLayer: View
    private val overlayRoot: FrameLayout
    private val topBar: LinearLayout
    private val sourcePill: TextView
    private val webTogglePill: TextView
    private val centerPlayBtn: ImageView
    private val bufferingSpinner: ProgressBar
    private val bottomBar: LinearLayout
    private val progressRow: LinearLayout
    private val timeView: TextView
    private val seekBar: SeekBar
    private val bottomPlayBtn: ImageView
    private val liveBadge: LinearLayout
    private val followLivePill: TextView
    private val speedPill: TextView
    private val fullscreenBtn: ImageView

    private val autoHideRunnable = Runnable { setControlsVisible(false) }
    private val prepareWatchdogRunnable = Runnable {
        if (activePlayer != null && activeWebView == null) {
            val st = activePlayer?.playbackState
            if (st == Player.STATE_BUFFERING || st == Player.STATE_IDLE) {
                val nextIdx = currentStreamIndex + 1
                if (nextIdx < streamCandidates.size) {
                    playStreamAt(nextIdx)
                } else if (webFallbackUrl.isNotEmpty()) {
                    attachWebView(webFallbackUrl)
                }
            }
        }
    }
    private val progressRunnable = object : Runnable {
        override fun run() {
            updatePlaybackProgress()
            mainHandler.postDelayed(this, 500L)
        }
    }

    init {
        channel.setMethodCallHandler(this)

        rootFrame = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        videoContainer = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        gestureLayer = View(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        val detector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                setControlsVisible(!controlsVisible)
                return true
            }
            override fun onDoubleTap(e: MotionEvent): Boolean {
                togglePlayPause()
                return true
            }
        })
        gestureLayer.setOnTouchListener { v, event ->
            detector.onTouchEvent(event)
            if (event.action == MotionEvent.ACTION_UP) v.performClick()
            true
        }

        overlayRoot = FrameLayout(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Top bar
        topBar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#B3000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        sourcePill = makePill("线路 1") { showStreamPicker() }
        val topSpacer = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
        }
        webTogglePill = makePill("网页") {
            if (activeWebView != null && streamCandidates.isNotEmpty()) {
                playStreamAt(currentStreamIndex.coerceIn(0, streamCandidates.lastIndex))
            } else if (webFallbackUrl.isNotEmpty()) {
                attachWebView(webFallbackUrl)
            }
        }
        topBar.addView(sourcePill)
        topBar.addView(topSpacer)
        topBar.addView(webTogglePill)

        // Center Play Button
        centerPlayBtn = ImageView(context).apply {
            setImageDrawable(InlineIconDrawable(IconKind.PLAY, Color.WHITE, dp(26)))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(12)
            setPadding(p, p, p, p)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#99000000"))
                setStroke(dp(1), Color.parseColor("#44FFFFFF"))
            }
            layoutParams = FrameLayout.LayoutParams(dp(50), dp(50), Gravity.CENTER)
            setOnClickListener {
                scheduleAutoHide()
                togglePlayPause()
            }
        }

        bufferingSpinner = ProgressBar(context).apply {
            indeterminateTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(dp(36), dp(36), Gravity.CENTER)
        }

        // Bottom bar
        bottomBar = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(6))
            background = GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                intArrayOf(Color.parseColor("#CC000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        progressRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        seekBar = SeekBar(context).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            thumbTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            progressBackgroundTintList = ColorStateList.valueOf(Color.parseColor("#55FFFFFF"))
            setPadding(dp(6), dp(4), dp(6), dp(4))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(sb: SeekBar?) {
                    isUserSeeking = true
                    mainHandler.removeCallbacks(autoHideRunnable)
                }
                override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) {
                        val dur = activePlayer?.duration ?: C.TIME_UNSET
                        if (dur > 0 && dur != C.TIME_UNSET) {
                            val targetMs = (dur * progress) / 1000L
                            timeView.text = "${formatDuration(targetMs)} / ${formatDuration(dur)}"
                        }
                    }
                }
                override fun onStopTrackingTouch(sb: SeekBar?) {
                    val dur = activePlayer?.duration ?: C.TIME_UNSET
                    if (dur > 0 && dur != C.TIME_UNSET && sb != null) {
                        activePlayer?.seekTo((dur * sb.progress) / 1000L)
                    }
                    isUserSeeking = false
                    scheduleAutoHide()
                }
            })
        }
        timeView = TextView(context).apply {
            text = "00:00 / 00:00"
            textSize = 11f
            setTextColor(Color.WHITE)
            setPadding(dp(4), 0, dp(4), 0)
        }
        progressRow.addView(seekBar)
        progressRow.addView(timeView)

        val actionRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        bottomPlayBtn = ImageView(context).apply {
            setImageDrawable(InlineIconDrawable(IconKind.PAUSE, Color.WHITE, dp(20)))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(6)
            setPadding(p, p, p, p)
            layoutParams = LinearLayout.LayoutParams(dp(34), dp(34))
            setOnClickListener {
                scheduleAutoHide()
                togglePlayPause()
            }
        }

        liveBadge = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(3), dp(8), dp(3))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Color.parseColor("#33FB7299"))
            }
            visibility = View.GONE
            addView(View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(SAKURA_ACCENT)
                }
                layoutParams = LinearLayout.LayoutParams(dp(6), dp(6)).apply {
                    marginEnd = dp(4)
                }
            })
            addView(TextView(context).apply {
                text = "直播"
                textSize = 11.5f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(SAKURA_ACCENT)
            })
        }

        followLivePill = makePill(
            "跟进直播",
            bgColor = Color.parseColor("#44FB7299"),
            textColor = SAKURA_ACCENT
        ) {
            seekToLiveEdge()
        }.apply {
            visibility = View.GONE
            (layoutParams as? LinearLayout.LayoutParams)?.marginStart = dp(6)
        }

        val bottomSpacer = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
        }

        speedPill = makePill("1.0x") { cycleSpeed() }.apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(6)
            }
        }

        fullscreenBtn = ImageView(context).apply {
            setImageDrawable(InlineIconDrawable(IconKind.FULLSCREEN, Color.WHITE, dp(20)))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(7)
            setPadding(p, p, p, p)
            layoutParams = LinearLayout.LayoutParams(dp(34), dp(34))
            setOnClickListener { requestFullscreenHandoff() }
        }

        actionRow.addView(bottomPlayBtn)
        actionRow.addView(liveBadge)
        actionRow.addView(followLivePill)
        actionRow.addView(bottomSpacer)
        actionRow.addView(speedPill)
        actionRow.addView(fullscreenBtn)

        bottomBar.addView(progressRow)
        bottomBar.addView(actionRow)

        overlayRoot.addView(topBar)
        overlayRoot.addView(centerPlayBtn)
        overlayRoot.addView(bottomBar)

        rootFrame.addView(videoContainer)
        rootFrame.addView(gestureLayer)
        rootFrame.addView(overlayRoot)
        rootFrame.addView(bufferingSpinner)

        applyArgs(initialArgs)
        startPlayback()
        mainHandler.postDelayed(progressRunnable, 500L)
    }

    private fun makePill(
        label: String,
        bgColor: Int = Color.parseColor("#55000000"),
        textColor: Int = Color.WHITE,
        onClick: () -> Unit
    ): TextView {
        return TextView(context).apply {
            text = label
            textSize = 11.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(textColor)
            gravity = Gravity.CENTER
            setPadding(dp(9), dp(4), dp(9), dp(4))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(bgColor)
            }
            setOnClickListener {
                scheduleAutoHide()
                onClick()
            }
        }
    }

    private fun applyArgs(args: Map<String, Any?>) {
        streamCandidates.clear()
        val seenUrls = mutableSetOf<String>()
        rawInitialUrl = (args["url"]?.toString() ?: "").trim()
        titleText = (args["title"]?.toString() ?: "智云课堂").ifBlank { "智云课堂" }
        val rawLivingroom = args["livingroomUrl"]?.toString() ?: ""
        token = args["token"]?.toString() ?: ""
        ssoCookie = args["ssoCookie"]?.toString() ?: ""
        zhiyunCookies = args["zhiyunCookies"]?.toString() ?: ""
        preferWeb = args["preferWeb"] == true
        isLiveStream = args["isLive"] == true ||
            titleText.contains("直播") ||
            rawInitialUrl.contains("/live/") ||
            rawInitialUrl.contains(".flv")
        pendingSeekMs = ((args["initialPositionMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
        currentStreamIndex = ((args["initialStreamIndex"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
        speedIndex = ((args["initialSpeedIndex"] as? Number)?.toInt() ?: 1).coerceIn(0, speeds.lastIndex)
        pendingAutoPlay = args["autoPlay"] != false

        @Suppress("UNCHECKED_CAST")
        val rawStreams = args["streams"] as? List<Map<String, Any?>> ?: emptyList()
        fun addCandidate(label: String, candidateUrl: String) {
            val trimmed = candidateUrl.trim()
            if (trimmed.isEmpty() || !seenUrls.add(trimmed)) return
            if (ZhiyunPlayerActivity.isDirectStreamUrl(trimmed)) {
                streamCandidates.add(Pair(label, trimmed))
            }
        }
        rawStreams.forEachIndexed { idx, item ->
            val u = item["url"]?.toString() ?: ""
            val l = item["label"]?.toString()?.trim()?.ifEmpty { "线路 ${idx + 1}" } ?: "线路 ${idx + 1}"
            addCandidate(l, u)
        }
        if (rawInitialUrl.isNotEmpty() && ZhiyunPlayerActivity.isDirectStreamUrl(rawInitialUrl)) {
            addCandidate("默认线路", rawInitialUrl)
        }
        webFallbackUrl = when {
            rawLivingroom.isNotBlank() -> rawLivingroom.trim()
            rawInitialUrl.isNotBlank() && !ZhiyunPlayerActivity.isDirectStreamUrl(rawInitialUrl) -> rawInitialUrl
            else -> ""
        }
        speedPill.text = "${speeds[speedIndex]}x"
        updateControlModes()
    }

    private fun startPlayback() {
        val openWebDirectly = preferWeb ||
            (rawInitialUrl.isNotEmpty() && !ZhiyunPlayerActivity.isDirectStreamUrl(rawInitialUrl))
        val fallback = webFallbackUrl.ifEmpty { rawInitialUrl }
        if (openWebDirectly && fallback.isNotEmpty()) {
            attachWebView(fallback)
        } else if (streamCandidates.isNotEmpty()) {
            playStreamAt(currentStreamIndex.coerceIn(0, streamCandidates.lastIndex))
        } else if (fallback.isNotEmpty()) {
            attachWebView(fallback)
        }
    }

    private fun playStreamAt(index: Int) {
        mainHandler.removeCallbacks(prepareWatchdogRunnable)
        if (index < 0 || index >= streamCandidates.size) {
            if (webFallbackUrl.isNotEmpty()) attachWebView(webFallbackUrl)
            return
        }
        currentStreamIndex = index
        val streamUrl = streamCandidates[index].second
        activeWebView?.destroy()
        activeWebView = null
        releasePlayer()
        videoContainer.removeAllViews()
        gestureLayer.visibility = View.VISIBLE
        bufferingSpinner.visibility = View.VISIBLE

        val lowerStream = streamUrl.lowercase()
        val isSelfSigned = lowerStream.contains("livepgc.cmc.zju.edu.cn") || lowerStream.contains("auth_key=")
        val headers = mutableMapOf(
            "Referer" to "https://classroom.zju.edu.cn/",
            "Origin" to "https://classroom.zju.edu.cn",
            "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Connection" to "keep-alive"
        )
        if (!isSelfSigned && token.isNotBlank()) {
            val phpCookie = ZhiyunPlayerActivity.buildPhpSerializedToken(token)
            headers["Cookie"] = when {
                zhiyunCookies.isNotBlank() -> zhiyunCookies.trim()
                phpCookie.isNotEmpty() -> "_token=$phpCookie; token=$token"
                else -> "_token=$token; token=$token"
            }
            headers["Authorization"] = "Bearer $token"
        }

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8000)
            .setReadTimeoutMs(10000)
            .setDefaultRequestProperties(headers)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                if (isLiveStream) 2500 else DefaultLoadControl.DEFAULT_MIN_BUFFER_MS,
                if (isLiveStream) 8000 else DefaultLoadControl.DEFAULT_MAX_BUFFER_MS,
                if (isLiveStream) 500 else DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                if (isLiveStream) 1000 else DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
            )
            .build()

        val player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .setLoadControl(loadControl)
            .build()

        val mediaBuilder = MediaItem.Builder().setUri(streamUrl)
        if (lowerStream.contains(".m3u8")) {
            mediaBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        if (isLiveStream) {
            mediaBuilder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setMaxPlaybackSpeed(1.02f)
                    .setMinPlaybackSpeed(0.98f)
                    .build()
            )
        }

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY || playbackState == Player.STATE_ENDED) {
                    mainHandler.removeCallbacks(prepareWatchdogRunnable)
                }
                bufferingSpinner.visibility = if (playbackState == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
                updatePlayPauseIcons()
                if (playbackState == Player.STATE_READY) {
                    updatePlaybackProgress()
                    scheduleAutoHide()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) {
                    mainHandler.removeCallbacks(prepareWatchdogRunnable)
                    bufferingSpinner.visibility = View.GONE
                    scheduleAutoHide()
                } else {
                    mainHandler.removeCallbacks(autoHideRunnable)
                }
                updatePlayPauseIcons()
            }

            override fun onPlayerError(error: PlaybackException) {
                mainHandler.removeCallbacks(prepareWatchdogRunnable)
                bufferingSpinner.visibility = View.GONE
                val nextIdx = currentStreamIndex + 1
                if (nextIdx < streamCandidates.size) {
                    playStreamAt(nextIdx)
                } else if (webFallbackUrl.isNotEmpty()) {
                    attachWebView(webFallbackUrl)
                }
            }
        })

        val playerView = PlayerView(context).apply {
            this.player = player
            useController = false
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        videoContainer.addView(playerView)
        activePlayer = player
        updateControlModes()
        setControlsVisible(true)
        player.setPlaybackParameters(PlaybackParameters(if (isLiveStream) 1.0f else speeds[speedIndex]))
        player.setMediaItem(mediaBuilder.build())
        if (pendingSeekMs > 0L && !isLiveStream) {
            player.seekTo(pendingSeekMs)
            pendingSeekMs = 0L
        }
        player.prepare()
        player.playWhenReady = pendingAutoPlay
        pendingAutoPlay = true
        mainHandler.postDelayed(prepareWatchdogRunnable, if (isLiveStream) 5500L else 8000L)
    }

    private fun attachWebView(targetUrl: String) {
        mainHandler.removeCallbacks(prepareWatchdogRunnable)
        if (targetUrl.isBlank()) return
        releasePlayer()
        activeWebView?.destroy()
        videoContainer.removeAllViews()
        gestureLayer.visibility = View.GONE
        bufferingSpinner.visibility = View.GONE

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        val rawJar = zhiyunCookies.trim()
        if (rawJar.isNotEmpty()) {
            rawJar.split(";").forEach { part ->
                val kv = part.trim()
                if (kv.contains("=")) {
                    cookieManager.setCookie("https://classroom.zju.edu.cn", "$kv; path=/")
                    cookieManager.setCookie("https://tgmedia.cmc.zju.edu.cn", "$kv; path=/")
                }
            }
        }
        if (token.isNotBlank()) {
            val phpCookie = ZhiyunPlayerActivity.buildPhpSerializedToken(token)
            if (phpCookie.isNotEmpty()) {
                cookieManager.setCookie("https://classroom.zju.edu.cn", "_token=$phpCookie; path=/")
                cookieManager.setCookie("https://tgmedia.cmc.zju.edu.cn", "_token=$phpCookie; path=/")
            }
            cookieManager.setCookie("https://classroom.zju.edu.cn", "token=$token; path=/")
        }
        val cleanSso = ssoCookie.trim().replace("iPlanetDirectoryPro=", "")
        if (cleanSso.isNotEmpty()) {
            cookieManager.setCookie("https://zjuam.zju.edu.cn", "iPlanetDirectoryPro=$cleanSso; path=/; domain=.zju.edu.cn")
        }
        cookieManager.flush()

        val trimmedTarget = targetUrl.trim()
        val hasFullSession = rawJar.contains("JWTUser=") && token.isNotBlank()
        val finalUrl = if (!hasFullSession && cleanSso.isNotEmpty() && trimmedTarget.contains("classroom.zju.edu.cn")) {
            val cleanForward = trimmedTarget.replace(Regex("([?&])token=[^&]*&?"), "$1").trimEnd('?', '&')
            val encodedForward = try { java.net.URLEncoder.encode(cleanForward, "UTF-8") } catch (_: Exception) { cleanForward }
            "https://tgmedia.cmc.zju.edu.cn/index.php?r=auth/login&auType=cmc&tenant_code=112&forward=$encodedForward"
        } else {
            ZhiyunPlayerActivity.appendTokenToUrl(trimmedTarget, token)
        }

        val wv = WebView(context).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            }
            cookieManager.setAcceptThirdPartyCookies(this, true)
            webViewClient = object : WebViewClient() {
                override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                    handler?.proceed()
                }
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val u = request?.url?.toString() ?: return false
                    return !(u.startsWith("http://") || u.startsWith("https://"))
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onJsConfirm(view: WebView?, url: String?, message: String?, result: JsResult?): Boolean {
                    result?.confirm()
                    return true
                }
            }
            loadUrl(finalUrl)
        }

        videoContainer.addView(wv)
        activeWebView = wv
        updateControlModes()
        setControlsVisible(true)
    }

    private fun updateControlModes() {
        val isWeb = activeWebView != null
        val isLive = isLiveStream && !isWeb
        sourcePill.text = streamCandidates.getOrNull(currentStreamIndex)?.first
            ?: if (isLive) "直播流" else "默认线路"
        sourcePill.visibility = if (!isWeb && streamCandidates.isNotEmpty()) View.VISIBLE else View.GONE
        webTogglePill.text = if (isWeb) "原生流" else "网页"
        webTogglePill.visibility = if ((isWeb && streamCandidates.isNotEmpty()) || (!isWeb && webFallbackUrl.isNotEmpty())) View.VISIBLE else View.GONE

        centerPlayBtn.visibility = if (isWeb) View.GONE else View.VISIBLE
        bottomPlayBtn.visibility = if (isWeb) View.GONE else View.VISIBLE
        progressRow.visibility = if (!isWeb && !isLive) View.VISIBLE else View.GONE
        liveBadge.visibility = if (isLive) View.VISIBLE else View.GONE
        speedPill.visibility = if (!isWeb && !isLive) View.VISIBLE else View.GONE
        followLivePill.visibility = View.GONE

        // In WebView mode keep top bar & compact bottom-right fullscreen button accessible
        if (isWeb) {
            topBar.visibility = View.VISIBLE
            bottomBar.background = null
        } else {
            bottomBar.background = GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                intArrayOf(Color.parseColor("#CC000000"), Color.TRANSPARENT)
            )
        }
    }

    private fun updatePlayPauseIcons() {
        val playing = activePlayer?.isPlaying == true || activePlayer?.playWhenReady == true
        centerPlayBtn.setImageDrawable(
            InlineIconDrawable(if (playing) IconKind.PAUSE else IconKind.PLAY, Color.WHITE, dp(26))
        )
        bottomPlayBtn.setImageDrawable(
            InlineIconDrawable(if (playing) IconKind.PAUSE else IconKind.PLAY, Color.WHITE, dp(20))
        )
    }

    private fun togglePlayPause() {
        val player = activePlayer ?: return
        if (player.isPlaying) {
            player.pause()
        } else {
            if (isLiveStream) {
                seekToLiveEdge()
            } else {
                player.play()
            }
        }
        updatePlayPauseIcons()
    }

    private fun seekToLiveEdge() {
        val player = activePlayer ?: return
        val dur = player.duration
        if (dur > 0L && dur != C.TIME_UNSET) {
            player.seekTo((dur - 1500L).coerceAtLeast(0L))
        } else if (player.isCurrentMediaItemLive) {
            player.seekToDefaultPosition()
        }
        player.play()
        followLivePill.visibility = View.GONE
    }

    private fun updatePlaybackProgress() {
        val player = activePlayer ?: return
        if (isLiveStream) {
            val dur = player.duration
            val pos = player.currentPosition
            val behindLive = (dur > 0 && dur != C.TIME_UNSET && dur - pos > 12_000L) || !player.isPlaying
            followLivePill.visibility = if (behindLive) View.VISIBLE else View.GONE
            return
        }
        if (isUserSeeking) return
        val dur = player.duration
        val pos = player.currentPosition.coerceAtLeast(0L)
        if (dur > 0 && dur != C.TIME_UNSET) {
            seekBar.isEnabled = true
            seekBar.progress = ((pos * 1000L) / dur).toInt().coerceIn(0, 1000)
            timeView.text = "${formatDuration(pos)} / ${formatDuration(dur)}"
        } else {
            seekBar.isEnabled = false
            timeView.text = "${formatDuration(pos)} / --:--"
        }
    }

    private fun formatDuration(ms: Long): String {
        val totalSec = (ms / 1000L).coerceAtLeast(0L)
        val hours = totalSec / 3600L
        val mins = (totalSec % 3600L) / 60L
        val secs = totalSec % 60L
        return if (hours > 0) String.format("%d:%02d:%02d", hours, mins, secs)
        else String.format("%02d:%02d", mins, secs)
    }

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        mainHandler.removeCallbacks(autoHideRunnable)
        if (activeWebView != null) {
            overlayRoot.visibility = View.VISIBLE
            return
        }
        overlayRoot.visibility = if (visible) View.VISIBLE else View.GONE
        if (visible) scheduleAutoHide()
    }

    private fun scheduleAutoHide() {
        mainHandler.removeCallbacks(autoHideRunnable)
        if (activeWebView == null && activePlayer?.isPlaying == true) {
            mainHandler.postDelayed(autoHideRunnable, 3500L)
        }
    }

    private fun cycleSpeed() {
        speedIndex = (speedIndex + 1) % speeds.size
        val spd = speeds[speedIndex]
        speedPill.text = "${spd}x"
        activePlayer?.setPlaybackParameters(PlaybackParameters(spd))
    }

    private fun showStreamPicker() {
        if (streamCandidates.size <= 1) {
            Toast.makeText(context, "当前仅有 1 条可用线路", Toast.LENGTH_SHORT).show()
            return
        }
        val labels = streamCandidates.map { it.first }.toTypedArray()
        AlertDialog.Builder(context)
            .setTitle("选择视频线路")
            .setSingleChoiceItems(labels, currentStreamIndex) { dlg, which ->
                dlg.dismiss()
                pendingSeekMs = (activePlayer?.currentPosition ?: 0L).coerceAtLeast(0L)
                playStreamAt(which)
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun buildStateMap(): Map<String, Any> {
        val player = activePlayer
        return mapOf(
            "positionMs" to (player?.currentPosition ?: 0L).coerceAtLeast(0L),
            "streamIndex" to currentStreamIndex,
            "speedIndex" to speedIndex,
            "wasPlaying" to (player?.playWhenReady == true || player?.isPlaying == true),
            "isWebMode" to (activeWebView != null)
        )
    }

    private fun requestFullscreenHandoff() {
        val state = buildStateMap()
        activePlayer?.pause()
        updatePlayPauseIcons()
        channel.invokeMethod("onFullscreenRequested", state)
    }

    private fun releasePlayer() {
        mainHandler.removeCallbacks(prepareWatchdogRunnable)
        try {
            activePlayer?.stop()
            activePlayer?.release()
        } catch (_: Exception) {
        }
        activePlayer = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadLesson" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                applyArgs(args)
                startPlayback()
                result.success(true)
            }
            "pause" -> {
                activePlayer?.pause()
                updatePlayPauseIcons()
                result.success(true)
            }
            "play" -> {
                activePlayer?.play()
                updatePlayPauseIcons()
                result.success(true)
            }
            "getState" -> {
                result.success(buildStateMap())
            }
            "syncState" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                val nextStream = (args["streamIndex"] as? Number)?.toInt() ?: currentStreamIndex
                val nextSpeed = (args["speedIndex"] as? Number)?.toInt() ?: speedIndex
                val nextPos = ((args["positionMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
                val wasPlaying = args["wasPlaying"] == true
                val isWebMode = args["isWebMode"] == true

                speedIndex = nextSpeed.coerceIn(0, speeds.lastIndex)
                speedPill.text = "${speeds[speedIndex]}x"

                if (isWebMode && webFallbackUrl.isNotEmpty()) {
                    if (activeWebView == null) attachWebView(webFallbackUrl)
                } else if (streamCandidates.isNotEmpty()) {
                    val targetStream = nextStream.coerceIn(0, streamCandidates.lastIndex)
                    if (activeWebView != null || activePlayer == null || targetStream != currentStreamIndex) {
                        pendingSeekMs = nextPos
                        pendingAutoPlay = wasPlaying
                        playStreamAt(targetStream)
                    } else {
                        val player = activePlayer
                        player?.setPlaybackParameters(PlaybackParameters(if (isLiveStream) 1.0f else speeds[speedIndex]))
                        if (!isLiveStream && nextPos > 0L) {
                            player?.seekTo(nextPos)
                        }
                        if (wasPlaying) {
                            player?.play()
                        } else {
                            player?.pause()
                        }
                        updatePlayPauseIcons()
                    }
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = rootFrame

    override fun dispose() {
        mainHandler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        releasePlayer()
        activeWebView?.destroy()
        activeWebView = null
    }
}
