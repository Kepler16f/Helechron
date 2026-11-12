package top.celechron.celechron

import android.app.Activity
import android.app.AlertDialog
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.ColorStateList
import android.content.res.Configuration
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
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.Rational
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.OrientationEventListener
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.CookieManager
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
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.common.C
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
 * 智云课堂内置播放器 Activity（参照现代主流全屏视频播放器设计）：
 * - 全屏无边框沉浸渲染 + 刘海/状态栏/导航栏安全区自动避让（无遮挡）
 * - 图标化半透明悬浮顶/底栏，无冗余文字拥挤，播放时 3.5 秒自动隐藏、点击呼出
 * - 左/右侧双击快退/快进 10 秒、中间双击播放/暂停
 * - 重力感应自动横竖屏切换 + 一键横屏全屏 + 16:9 原生画中画小窗 + 网页端无缝降级
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

        private val SAKURA_ACCENT = Color.parseColor("#FB7299")

        fun isDirectStreamUrl(targetUrl: String): Boolean {
            val lower = targetUrl.lowercase()
            if (lower.contains("livingroom")) return false
            return lower.contains(".mp4") ||
                lower.contains(".m3u8") ||
                lower.contains(".flv") ||
                lower.contains(".ts")
        }

        fun buildPhpSerializedToken(token: String): String {
            val raw = token.trim()
            if (raw.isEmpty()) return ""
            val byteLen = raw.toByteArray(Charsets.UTF_8).size
            val serialized = "a:2:{i:0;s:6:\"_token\";i:1;s:$byteLen:\"$raw\";}"
            return try {
                java.net.URLEncoder.encode(serialized, "UTF-8").replace("+", "%20")
            } catch (_: Exception) {
                serialized
            }
        }

        fun appendTokenToUrl(rawUrl: String, token: String): String {
            val tk = token.trim()
            if (tk.isEmpty() || rawUrl.isBlank()) return rawUrl
            if (rawUrl.contains("token=") || rawUrl.contains("_token=")) return rawUrl
            val encoded = try {
                java.net.URLEncoder.encode(tk, "UTF-8").replace("+", "%20")
            } catch (_: Exception) {
                tk
            }
            val hashIdx = rawUrl.indexOf('#')
            val base = if (hashIdx >= 0) rawUrl.substring(0, hashIdx) else rawUrl
            val hash = if (hashIdx >= 0) rawUrl.substring(hashIdx) else ""
            val sep = if (base.contains('?')) '&' else '?'
            return "$base${sep}token=$encoded$hash"
        }
    }

    private enum class IconKind {
        BACK, PLAY, PAUSE, FULLSCREEN, FULLSCREEN_EXIT, PIP, ROTATE, MORE
    }

    private class VectorIconDrawable(
        private val kind: IconKind,
        private val color: Int = Color.WHITE,
        private val intrinsicSizePx: Int = 72
    ) : Drawable() {
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = this@VectorIconDrawable.color
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = this@VectorIconDrawable.color
            style = Paint.Style.FILL
        }

        override fun getIntrinsicWidth(): Int = intrinsicSizePx
        override fun getIntrinsicHeight(): Int = intrinsicSizePx

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.width() <= 0 || b.height() <= 0) return
            val sx = b.width() / 24f
            val sy = b.height() / 24f
            strokePaint.strokeWidth = 2.2f * minOf(sx, sy)
            canvas.save()
            canvas.translate(b.left.toFloat(), b.top.toFloat())
            canvas.scale(sx, sy)

            when (kind) {
                IconKind.BACK -> {
                    val p = Path().apply {
                        moveTo(15f, 4.5f)
                        lineTo(7.5f, 12f)
                        lineTo(15f, 19.5f)
                    }
                    canvas.drawPath(p, strokePaint)
                }

                IconKind.PLAY -> {
                    val p = Path().apply {
                        moveTo(6.5f, 4f)
                        lineTo(20f, 12f)
                        lineTo(6.5f, 20f)
                        close()
                    }
                    canvas.drawPath(p, fillPaint)
                }

                IconKind.PAUSE -> {
                    canvas.drawRoundRect(RectF(6f, 4.5f, 10f, 19.5f), 1.3f, 1.3f, fillPaint)
                    canvas.drawRoundRect(RectF(14f, 4.5f, 18f, 19.5f), 1.3f, 1.3f, fillPaint)
                }

                IconKind.FULLSCREEN -> {
                    val p = Path().apply {
                        moveTo(3.5f, 9f); lineTo(3.5f, 3.5f); lineTo(9f, 3.5f)
                        moveTo(15f, 3.5f); lineTo(20.5f, 3.5f); lineTo(20.5f, 9f)
                        moveTo(20.5f, 15f); lineTo(20.5f, 20.5f); lineTo(15f, 20.5f)
                        moveTo(9f, 20.5f); lineTo(3.5f, 20.5f); lineTo(3.5f, 15f)
                    }
                    canvas.drawPath(p, strokePaint)
                }

                IconKind.FULLSCREEN_EXIT -> {
                    val p = Path().apply {
                        moveTo(9f, 3.5f); lineTo(9f, 9f); lineTo(3.5f, 9f)
                        moveTo(15f, 3.5f); lineTo(15f, 9f); lineTo(20.5f, 9f)
                        moveTo(15f, 20.5f); lineTo(15f, 15f); lineTo(20.5f, 15f)
                        moveTo(9f, 20.5f); lineTo(9f, 15f); lineTo(3.5f, 15f)
                    }
                    canvas.drawPath(p, strokePaint)
                }

                IconKind.PIP -> {
                    val outer = Path().apply {
                        moveTo(20.5f, 10f)
                        lineTo(20.5f, 5f)
                        lineTo(3f, 5f)
                        lineTo(3f, 18f)
                        lineTo(9.5f, 18f)
                    }
                    canvas.drawPath(outer, strokePaint)
                    canvas.drawRoundRect(RectF(12f, 12f, 21.5f, 19.2f), 1.5f, 1.5f, fillPaint)
                }

                IconKind.ROTATE -> {
                    val arcRect = RectF(4.2f, 4.2f, 19.8f, 19.8f)
                    val arrows = Path().apply {
                        arcTo(arcRect, 205f, 115f, true)
                        moveTo(18.2f, 3.4f); lineTo(18.2f, 7.2f); lineTo(14.4f, 7.0f)
                        arcTo(arcRect, 25f, 115f, true)
                        moveTo(5.8f, 20.6f); lineTo(5.8f, 16.8f); lineTo(9.6f, 17.0f)
                    }
                    canvas.drawPath(arrows, strokePaint)
                    canvas.drawRoundRect(RectF(9.5f, 7.5f, 14.5f, 16.5f), 1.0f, 1.0f, strokePaint)
                }

                IconKind.MORE -> {
                    canvas.drawCircle(5.5f, 12f, 2.1f, fillPaint)
                    canvas.drawCircle(12f, 12f, 2.1f, fillPaint)
                    canvas.drawCircle(18.5f, 12f, 2.1f, fillPaint)
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

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private val streamCandidates = mutableListOf<Pair<String, String>>()
    private var webFallbackUrl: String = ""
    private var token: String = ""
    private var titleText: String = "智云课堂"

    private lateinit var rootFrame: FrameLayout
    private lateinit var videoContainer: FrameLayout
    private lateinit var gestureLayer: View
    private lateinit var overlayRoot: FrameLayout
    private lateinit var topBar: LinearLayout
    private lateinit var bottomBar: LinearLayout
    private lateinit var titleView: TextView
    private lateinit var webReturnNativePill: TextView
    private lateinit var webOrientPill: TextView
    private lateinit var pipBtn: ImageView
    private lateinit var moreBtn: ImageView
    private lateinit var centerControlsRow: LinearLayout
    private lateinit var rewind10Btn: TextView
    private lateinit var centerPlayBtn: ImageView
    private lateinit var forward10Btn: TextView
    private lateinit var bottomPlayBtn: ImageView
    private lateinit var timeCurrentView: TextView
    private lateinit var timeDurationView: TextView
    private lateinit var seekBar: SeekBar
    private lateinit var liveSourcePill: TextView
    private lateinit var webFallbackPill: TextView
    private lateinit var speedPill: TextView
    private lateinit var orientPill: TextView
    private lateinit var fullscreenBtn: ImageView
    private lateinit var bufferingSpinner: ProgressBar
    private lateinit var hudPill: TextView
    private lateinit var webBarToggleBtn: ImageView

    private var activePlayer: ExoPlayer? = null
    private var activeWebView: WebView? = null
    private var currentStreamIndex = 0
    private val speeds = floatArrayOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    private var speedIndex = 1 // 1.0x

    private var controlsVisible = true
    private var isFullscreen = false
    private var isFullscreenLocked = false
    private var isLiveStream = false
    private var sensorAutoRotate = true
    private var currentRequestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private var lastRotateTimeMs = 0L
    private var orientationListener: OrientationEventListener? = null
    private var customViewExitCallback: WebChromeClient.CustomViewCallback? = null
    private var exitWebFullscreen: (() -> Unit)? = null

    private var safeLeft = 0
    private var safeTop = 0
    private var safeRight = 0
    private var safeBottom = 0
    private var isUserSeeking = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val autoHideRunnable = Runnable { setControlsVisible(false) }
    private val hudHideRunnable = Runnable { hudPill.visibility = View.GONE }
    private val prepareWatchdogRunnable = Runnable {
        if (activePlayer != null && activeWebView == null) {
            val state = activePlayer?.playbackState
            if (state == Player.STATE_BUFFERING || state == Player.STATE_IDLE) {
                val nextIdx = currentStreamIndex + 1
                if (nextIdx < streamCandidates.size) {
                    showHud("当前线路连接超时，切换备用线路...")
                    playStreamAt(nextIdx)
                } else if (webFallbackUrl.isNotEmpty()) {
                    Toast.makeText(
                        this@ZhiyunPlayerActivity,
                        "原生流连接超时，已切换网页端播放",
                        Toast.LENGTH_SHORT
                    ).show()
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        parseIntentExtras(intent)
        buildUi()
        setupWindowInsets()
        setupSensorRotation()
        updatePipParams()
        startPlayback()
        mainHandler.postDelayed(progressRunnable, 500L)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        parseIntentExtras(intent)
        titleView.text = titleText
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
            if (isDirectStreamUrl(trimmed)) {
                streamCandidates.add(Pair(label, trimmed))
            }
        }

        for (i in urls.indices) {
            val label = labels.getOrNull(i)?.ifBlank { "线路 ${i + 1}" } ?: "线路 ${i + 1}"
            addCandidate(label, urls[i])
        }
        if (rawUrl.isNotEmpty() && isDirectStreamUrl(rawUrl)) {
            addCandidate("默认线路", rawUrl)
        }

        webFallbackUrl = when {
            rawLivingroom.isNotBlank() -> rawLivingroom.trim()
            rawUrl.isNotBlank() && !isDirectStreamUrl(rawUrl) -> rawUrl.trim()
            else -> ""
        }
    }

    private fun makeIconBtn(
        kind: IconKind,
        sizeDp: Int = 46,
        padDp: Int = 10,
        color: Int = Color.WHITE,
        onClick: () -> Unit
    ): ImageView {
        val iconPx = dp((sizeDp - padDp * 2).coerceAtLeast(22))
        return ImageView(this).apply {
            setImageDrawable(VectorIconDrawable(kind, color, iconPx))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(padDp)
            setPadding(p, p, p, p)
            layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
            setOnClickListener {
                scheduleAutoHide()
                onClick()
            }
        }
    }

    private fun makePillButton(
        label: String,
        bgColor: Int = Color.parseColor("#44FFFFFF"),
        textColor: Int = Color.WHITE,
        onClick: () -> Unit
    ): TextView {
        return TextView(this).apply {
            text = label
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(textColor)
            gravity = Gravity.CENTER
            minHeight = dp(34)
            setPadding(dp(12), dp(6), dp(12), dp(6))
            background = GradientDrawable().apply {
                cornerRadius = dp(17).toFloat()
                setColor(bgColor)
            }
            setOnClickListener {
                scheduleAutoHide()
                onClick()
            }
        }
    }

    private fun makeCircleSeekBtn(label: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#88000000"))
                setStroke(dp(1), Color.parseColor("#33FFFFFF"))
            }
            layoutParams = LinearLayout.LayoutParams(dp(58), dp(58))
            setOnClickListener {
                scheduleAutoHide()
                onClick()
            }
        }
    }

    private fun buildUi() {
        rootFrame = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        videoContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        gestureLayer = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        val detector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                setControlsVisible(!controlsVisible)
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                activePlayer ?: return false
                val w = gestureLayer.width.coerceAtLeast(1)
                when {
                    e.x < w * 0.30f -> seekBy(-10_000L, "后退 10s")
                    e.x > w * 0.70f -> seekBy(10_000L, "前进 10s")
                    else -> togglePlayPause(showBanner = true)
                }
                return true
            }
        })
        gestureLayer.setOnTouchListener { _, ev -> detector.onTouchEvent(ev) }

        overlayRoot = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Top Bar Scrim
        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#DD000000"), Color.parseColor("#66000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val backBtn = makeIconBtn(IconKind.BACK, sizeDp = 48, padDp = 11) {
            if (isFullscreen) {
                toggleLandscapeFullscreen()
            } else {
                finish()
            }
        }

        titleView = TextView(this).apply {
            text = titleText
            textSize = 15.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(4), 0, dp(8), 0)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        webReturnNativePill = makePillButton(
            "原生流",
            bgColor = Color.parseColor("#33FB7299"),
            textColor = SAKURA_ACCENT
        ) {
            if (streamCandidates.isNotEmpty()) {
                playStreamAt(currentStreamIndex.coerceIn(0, streamCandidates.lastIndex))
            }
        }.apply {
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(6)
            }
        }

        webOrientPill = makePillButton("横屏") {
            toggleLandscapeFullscreen()
        }.apply {
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(4)
            }
        }

        pipBtn = makeIconBtn(IconKind.PIP, sizeDp = 48, padDp = 11) {
            enterPipMode()
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            pipBtn.visibility = View.GONE
        }

        moreBtn = makeIconBtn(IconKind.MORE, sizeDp = 48, padDp = 11) {
            showMoreMenuDialog()
        }

        topBar.addView(backBtn)
        topBar.addView(titleView)
        topBar.addView(webReturnNativePill)
        topBar.addView(webOrientPill)
        topBar.addView(pipBtn)
        topBar.addView(moreBtn)

        // Center Transport Row (-10s / Play / +10s)
        centerControlsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }

        rewind10Btn = makeCircleSeekBtn("-10s") {
            seekBy(-10_000L, "后退 10s")
        }.apply {
            (layoutParams as LinearLayout.LayoutParams).marginEnd = dp(24)
        }

        centerPlayBtn = ImageView(this).apply {
            setImageDrawable(VectorIconDrawable(IconKind.PLAY, Color.WHITE, dp(38)))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(19)
            setPadding(p, p, p, p)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#99000000"))
                setStroke(dp(1), Color.parseColor("#44FFFFFF"))
            }
            layoutParams = LinearLayout.LayoutParams(dp(76), dp(76))
            setOnClickListener {
                togglePlayPause(showBanner = false)
            }
        }

        forward10Btn = makeCircleSeekBtn("+10s") {
            seekBy(10_000L, "前进 10s")
        }.apply {
            (layoutParams as LinearLayout.LayoutParams).marginStart = dp(24)
        }

        centerControlsRow.addView(rewind10Btn)
        centerControlsRow.addView(centerPlayBtn)
        centerControlsRow.addView(forward10Btn)

        // Bottom Bar Scrim (Bilibili / iQiyi 2-row style)
        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                intArrayOf(Color.parseColor("#DD000000"), Color.parseColor("#77000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        val progressRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        timeCurrentView = TextView(this).apply {
            text = "00:00"
            textSize = 12.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setPadding(dp(4), 0, dp(8), 0)
        }

        seekBar = SeekBar(this).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            thumbTintList = ColorStateList.valueOf(Color.WHITE)
            progressBackgroundTintList = ColorStateList.valueOf(Color.parseColor("#55FFFFFF"))
            layoutParams = LinearLayout.LayoutParams(0, dp(34), 1f)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) {
                        val dur = activePlayer?.duration ?: 0L
                        if (dur > 0) {
                            timeCurrentView.text = formatMs(dur * progress / 1000L)
                        }
                    }
                }

                override fun onStartTrackingTouch(sb: SeekBar?) {
                    isUserSeeking = true
                    mainHandler.removeCallbacks(autoHideRunnable)
                }

                override fun onStopTrackingTouch(sb: SeekBar?) {
                    isUserSeeking = false
                    val dur = activePlayer?.duration ?: 0L
                    if (dur > 0 && sb != null) {
                        activePlayer?.seekTo(dur * sb.progress / 1000L)
                    }
                    scheduleAutoHide()
                }
            })
        }

        timeDurationView = TextView(this).apply {
            text = "00:00"
            textSize = 12.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#DDFFFFFF"))
            setPadding(dp(8), 0, dp(4), 0)
        }

        progressRow.addView(timeCurrentView)
        progressRow.addView(seekBar)
        progressRow.addView(timeDurationView)

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(4)
            }
        }

        bottomPlayBtn = makeIconBtn(IconKind.PLAY, sizeDp = 46, padDp = 10) {
            togglePlayPause(showBanner = false)
        }

        val actionSpacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
        }

        liveSourcePill = makePillButton("线路") {
            showSourceDialog()
        }.apply {
            visibility = if (streamCandidates.size > 1) View.VISIBLE else View.GONE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(8)
            }
        }

        webFallbackPill = makePillButton("网页版") {
            if (webFallbackUrl.isNotEmpty()) {
                attachWebView(webFallbackUrl)
            }
        }.apply {
            visibility = if (webFallbackUrl.isNotEmpty()) View.VISIBLE else View.GONE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(8)
            }
        }

        speedPill = makePillButton("1.0x") {
            cycleSpeed()
        }.apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(8)
            }
        }

        orientPill = makePillButton("横屏") {
            toggleLandscapeFullscreen()
        }.apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(4)
            }
        }

        fullscreenBtn = makeIconBtn(IconKind.FULLSCREEN, sizeDp = 46, padDp = 10) {
            toggleLandscapeFullscreen()
        }

        actionRow.addView(bottomPlayBtn)
        actionRow.addView(actionSpacer)
        actionRow.addView(liveSourcePill)
        actionRow.addView(webFallbackPill)
        actionRow.addView(speedPill)
        actionRow.addView(orientPill)
        actionRow.addView(fullscreenBtn)

        bottomBar.addView(progressRow)
        bottomBar.addView(actionRow)

        overlayRoot.addView(topBar)
        overlayRoot.addView(centerControlsRow)
        overlayRoot.addView(bottomBar)

        bufferingSpinner = ProgressBar(this).apply {
            indeterminateTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER)
        }

        webBarToggleBtn = ImageView(this).apply {
            setImageDrawable(VectorIconDrawable(IconKind.MORE, Color.WHITE, dp(26)))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(10)
            setPadding(p, p, p, p)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#99000000"))
            }
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(dp(46), dp(46), Gravity.TOP or Gravity.END)
            setOnClickListener {
                setControlsVisible(!controlsVisible)
            }
        }

        hudPill = TextView(this).apply {
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setPadding(dp(16), dp(8), dp(16), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(Color.parseColor("#CC1C1C1E"))
            }
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL or Gravity.TOP
            )
        }

        rootFrame.addView(videoContainer)
        rootFrame.addView(gestureLayer)
        rootFrame.addView(overlayRoot)
        rootFrame.addView(bufferingSpinner)
        rootFrame.addView(webBarToggleBtn)
        rootFrame.addView(hudPill)
        setContentView(rootFrame)
        applyBarSafePadding()
    }

    private fun setupWindowInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(rootFrame) { _, windowInsets ->
            val insets = windowInsets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            safeLeft = insets.left
            safeTop = insets.top
            safeRight = insets.right
            safeBottom = insets.bottom
            applyBarSafePadding()
            windowInsets
        }
        ViewCompat.requestApplyInsets(rootFrame)
    }

    private fun applyBarSafePadding() {
        val hPadLeft = maxOf(dp(12), safeLeft + dp(8))
        val hPadRight = maxOf(dp(12), safeRight + dp(8))
        val topExtra = if (isFullscreen) maxOf(dp(8), safeTop + dp(4)) else maxOf(dp(12), safeTop + dp(6))
        val bottomExtra = if (isFullscreen) maxOf(dp(10), safeBottom + dp(6)) else maxOf(dp(12), safeBottom + dp(8))

        topBar.setPadding(hPadLeft, topExtra, hPadRight, dp(10))
        bottomBar.setPadding(hPadLeft, dp(14), hPadRight, bottomExtra)

        val vcParams = videoContainer.layoutParams as FrameLayout.LayoutParams
        val desiredTopMargin = if (activeWebView != null && customViewExitCallback == null) {
            topExtra + dp(58)
        } else {
            0
        }
        if (vcParams.topMargin != desiredTopMargin) {
            vcParams.topMargin = desiredTopMargin
            videoContainer.layoutParams = vcParams
        }

        (webBarToggleBtn.layoutParams as FrameLayout.LayoutParams).apply {
            topMargin = topExtra + dp(4)
            rightMargin = hPadRight + dp(4)
        }
        webBarToggleBtn.requestLayout()

        (hudPill.layoutParams as FrameLayout.LayoutParams).topMargin = topExtra + dp(64)
        hudPill.requestLayout()
    }

    private fun clearPrepareWatchdog() {
        mainHandler.removeCallbacks(prepareWatchdogRunnable)
    }

    private fun updatePlayPauseIcons() {
        val playing = activePlayer?.isPlaying == true
        val kind = if (playing) IconKind.PAUSE else IconKind.PLAY
        centerPlayBtn.setImageDrawable(VectorIconDrawable(kind, Color.WHITE, dp(38)))
        bottomPlayBtn.setImageDrawable(VectorIconDrawable(kind, Color.WHITE, dp(26)))
    }

    private fun showHud(msg: String) {
        hudPill.text = msg
        hudPill.visibility = View.VISIBLE
        mainHandler.removeCallbacks(hudHideRunnable)
        mainHandler.postDelayed(hudHideRunnable, 1600L)
    }

    private fun setControlsVisible(visible: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
            overlayRoot.visibility = View.GONE
            webBarToggleBtn.visibility = View.GONE
            return
        }
        val isWeb = activeWebView != null
        val isWebCustomFullscreen = isWeb && customViewExitCallback != null
        val effectiveVisible = if (isWeb && !isWebCustomFullscreen) true else visible
        controlsVisible = effectiveVisible

        overlayRoot.visibility = if (effectiveVisible) View.VISIBLE else View.GONE
        bottomBar.visibility = if (isWeb) View.GONE else View.VISIBLE
        centerControlsRow.visibility = if (isWeb) View.GONE else View.VISIBLE
        webReturnNativePill.visibility = if (isWeb && streamCandidates.isNotEmpty()) View.VISIBLE else View.GONE
        webOrientPill.visibility = if (isWeb) View.VISIBLE else View.GONE
        pipBtn.visibility = if (!isWeb && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) View.VISIBLE else View.GONE
        webBarToggleBtn.visibility = if (isWebCustomFullscreen && !effectiveVisible) View.VISIBLE else View.GONE

        if (!isWeb) {
            liveSourcePill.visibility = if (streamCandidates.size > 1) View.VISIBLE else View.GONE
            webFallbackPill.visibility = if (webFallbackUrl.isNotEmpty()) View.VISIBLE else View.GONE
        }

        if (effectiveVisible && !isWeb) {
            scheduleAutoHide()
        } else {
            mainHandler.removeCallbacks(autoHideRunnable)
        }
    }

    private fun scheduleAutoHide() {
        mainHandler.removeCallbacks(autoHideRunnable)
        if (activeWebView == null && activePlayer?.isPlaying == true) {
            mainHandler.postDelayed(autoHideRunnable, 3500L)
        }
    }

    private fun togglePlayPause(showBanner: Boolean) {
        val player = activePlayer ?: return
        if (player.isPlaying) {
            player.pause()
            if (showBanner) showHud("已暂停")
        } else {
            player.play()
            if (showBanner) showHud("继续播放")
        }
        updatePlayPauseIcons()
        scheduleAutoHide()
    }

    private fun seekBy(deltaMs: Long, label: String) {
        val player = activePlayer ?: return
        val dur = player.duration
        if (dur <= 0 || dur == C.TIME_UNSET) return
        val target = (player.currentPosition + deltaMs).coerceIn(0L, dur)
        player.seekTo(target)
        showHud(label)
        updatePlaybackProgress()
    }

    private fun updatePlaybackProgress() {
        val player = activePlayer ?: return
        updatePlayPauseIcons()
        if (isUserSeeking) return
        val dur = player.duration
        val pos = player.currentPosition.coerceAtLeast(0L)
        val live = player.isCurrentMediaItemLive || dur <= 0L || dur == C.TIME_UNSET
        isLiveStream = live
        rewind10Btn.visibility = if (live) View.GONE else View.VISIBLE
        forward10Btn.visibility = if (live) View.GONE else View.VISIBLE
        speedPill.visibility = if (live) View.GONE else View.VISIBLE

        if (live) {
            timeCurrentView.text = if (pos > 0) formatMs(pos) else "00:00"
            timeDurationView.text = "● LIVE"
            timeDurationView.setTextColor(SAKURA_ACCENT)
            seekBar.isEnabled = false
            seekBar.progress = 1000
        } else {
            seekBar.isEnabled = true
            timeCurrentView.text = formatMs(pos)
            timeDurationView.text = formatMs(dur)
            timeDurationView.setTextColor(Color.parseColor("#DDFFFFFF"))
            seekBar.progress = ((pos * 1000L) / dur).toInt().coerceIn(0, 1000)
        }
    }

    private fun formatMs(ms: Long): String {
        val totalSec = (ms / 1000L).coerceAtLeast(0L)
        val hours = totalSec / 3600L
        val mins = (totalSec % 3600L) / 60L
        val secs = totalSec % 60L
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, mins, secs)
        } else {
            String.format("%02d:%02d", mins, secs)
        }
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
                if (now - lastRotateTimeMs < 600) return

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
        orientPill.text = if (fullscreen) "竖屏" else "横屏"
        webOrientPill.text = if (fullscreen) "竖屏" else "横屏"
        fullscreenBtn.setImageDrawable(
            VectorIconDrawable(if (fullscreen) IconKind.FULLSCREEN_EXIT else IconKind.FULLSCREEN, Color.WHITE, dp(26))
        )
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
                (View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
            }
        }
        applyBarSafePadding()
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
            overlayRoot.visibility = View.GONE
            webBarToggleBtn.visibility = View.GONE
            enterPictureInPictureMode(builder.build())
        } catch (e: Exception) {
            setControlsVisible(true)
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
            overlayRoot.visibility = View.GONE
            webBarToggleBtn.visibility = View.GONE
        } else {
            setControlsVisible(true)
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) return
        val landscape = newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE
        if (landscape != isFullscreen) {
            applyFullscreenChrome(landscape)
        } else {
            applyBarSafePadding()
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
        clearPrepareWatchdog()
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
        customViewExitCallback = null
        exitWebFullscreen = null
        releasePlayer()
        videoContainer.removeAllViews()
        gestureLayer.visibility = View.VISIBLE
        bufferingSpinner.visibility = View.VISIBLE

        val headers = mutableMapOf(
            "Referer" to "https://classroom.zju.edu.cn/",
            "Origin" to "https://classroom.zju.edu.cn",
            "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        )
        if (token.isNotBlank()) {
            val phpCookie = buildPhpSerializedToken(token)
            headers["Cookie"] = if (phpCookie.isNotEmpty()) {
                "_token=$phpCookie; token=$token"
            } else {
                "_token=$token; token=$token"
            }
            headers["Authorization"] = "Bearer $token"
        }

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8000)
            .setReadTimeoutMs(10000)
            .setDefaultRequestProperties(headers)

        val player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build()

        val mediaBuilder = MediaItem.Builder().setUri(streamUrl)
        if (streamUrl.lowercase().contains(".m3u8")) {
            mediaBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY || playbackState == Player.STATE_ENDED) {
                    clearPrepareWatchdog()
                }
                bufferingSpinner.visibility =
                    if (playbackState == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
                updatePlayPauseIcons()
                if (playbackState == Player.STATE_READY) {
                    updatePlaybackProgress()
                    scheduleAutoHide()
                    updatePipParams()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) {
                    clearPrepareWatchdog()
                    bufferingSpinner.visibility = View.GONE
                }
                updatePlayPauseIcons()
                if (isPlaying) {
                    scheduleAutoHide()
                } else {
                    mainHandler.removeCallbacks(autoHideRunnable)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                clearPrepareWatchdog()
                bufferingSpinner.visibility = View.GONE
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
            useController = false
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        videoContainer.addView(playerView)
        activePlayer = player
        applyBarSafePadding()
        setControlsVisible(true)
        updatePipParams()
        player.setPlaybackParameters(PlaybackParameters(speeds[speedIndex]))
        player.setMediaItem(mediaBuilder.build())
        player.prepare()
        player.playWhenReady = true
        mainHandler.postDelayed(prepareWatchdogRunnable, 8000L)
    }

    private fun attachWebView(targetUrl: String) {
        clearPrepareWatchdog()
        if (targetUrl.isBlank()) return
        releasePlayer()
        activeWebView?.destroy()
        videoContainer.removeAllViews()
        gestureLayer.visibility = View.GONE
        bufferingSpinner.visibility = View.VISIBLE

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
        val phpCookie = buildPhpSerializedToken(token)
        if (token.isNotBlank()) {
            val hosts = listOf(
                "https://classroom.zju.edu.cn",
                "https://livingroom.cmc.zju.edu.cn",
                "https://yjapi.cmc.zju.edu.cn",
                "https://tgmedia.cmc.zju.edu.cn",
                "https://www.zju.edu.cn"
            )
            for (h in hosts) {
                if (phpCookie.isNotEmpty()) {
                    cookieManager.setCookie(h, "_token=$phpCookie; Path=/")
                    cookieManager.setCookie(h, "_token=$phpCookie; Domain=.zju.edu.cn; Path=/")
                }
                cookieManager.setCookie(h, "token=$token; Path=/")
                cookieManager.setCookie(h, "token=$token; Domain=.zju.edu.cn; Path=/")
            }
            cookieManager.flush()
        }

        val escapedToken = token
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "")
        val escapedPhpCookie = phpCookie
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "")
        val injectJs = buildString {
            append("(function(){try{")
            if (escapedToken.isNotEmpty()) {
                append("localStorage.setItem('token','$escapedToken');")
                append("localStorage.setItem('_token','$escapedToken');")
                val cookieToken = if (escapedPhpCookie.isNotEmpty()) escapedPhpCookie else escapedToken
                append("document.cookie='_token=$cookieToken;path=/;domain=.zju.edu.cn';")
                append("document.cookie='_token=$cookieToken;path=/';")
                append("document.cookie='token=$escapedToken;path=/;domain=.zju.edu.cn';")
                append("document.cookie='token=$escapedToken;path=/';")
            }
            append(
                "if(!document.getElementById('helechron-zy-fix')){" +
                    "var s=document.createElement('style');s.id='helechron-zy-fix';" +
                    "s.innerHTML='html,body{background:#000!important;margin:0!important;padding:0!important;overflow-x:hidden!important;}" +
                    ".player-wrapper,.prism-player,video{max-width:100vw!important;background:#000!important;}';" +
                    "(document.head||document.documentElement).appendChild(s);" +
                    "}"
            )
            append("}catch(e){}})();")
        }

        val finalUrl = appendTokenToUrl(targetUrl.trim(), token)

        val wv = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            settings.userAgentString =
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
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
                    setControlsVisible(false)
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
                    setControlsVisible(true)
                }
            }
            exitWebFullscreen = { chromeClient.onHideCustomView() }
            webChromeClient = chromeClient
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    super.onPageStarted(view, url, favicon)
                    view?.evaluateJavascript(injectJs, null)
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    bufferingSpinner.visibility = View.GONE
                    view?.evaluateJavascript(injectJs, null)
                }

                override fun onReceivedSslError(
                    view: WebView?,
                    handler: SslErrorHandler?,
                    error: SslError?
                ) {
                    val urlStr = error?.url?.lowercase() ?: ""
                    if (urlStr.contains("zju.edu.cn") ||
                        urlStr.contains("chinamcloud.com") ||
                        urlStr.contains("chinamcache.com")
                    ) {
                        handler?.proceed()
                    } else {
                        handler?.cancel()
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
                finalUrl,
                mapOf(
                    "Referer" to "https://classroom.zju.edu.cn/",
                    "Origin" to "https://classroom.zju.edu.cn"
                )
            )
        }
        activeWebView = wv
        videoContainer.addView(
            wv,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        videoContainer.addView(customViewHolder)
        applyBarSafePadding()
        setControlsVisible(true)
        updatePipParams()
    }

    private fun showMoreMenuDialog() {
        val options = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        if (activeWebView == null && !isLiveStream) {
            options.add("倍速播放（当前 ${speeds[speedIndex]}x）")
            actions.add { showSpeedDialog() }
        }
        if (streamCandidates.size > 1) {
            options.add("切换视频线路（共 ${streamCandidates.size} 条）")
            actions.add { showSourceDialog() }
        }
        options.add(if (isFullscreen) "退出横屏全屏" else "切换横屏全屏")
        actions.add { toggleLandscapeFullscreen() }

        options.add(if (sensorAutoRotate) "关闭重力感应旋屏" else "开启重力感应旋屏")
        actions.add {
            sensorAutoRotate = !sensorAutoRotate
            if (!sensorAutoRotate && !isFullscreenLocked) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
                showHud("已锁定当前方向")
            } else if (sensorAutoRotate) {
                orientationListener?.enable()
                showHud("已开启重力旋屏")
            }
        }

        if (activeWebView == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            options.add("画中画小窗播放")
            actions.add { enterPipMode() }
        }

        if (activeWebView == null && webFallbackUrl.isNotEmpty()) {
            options.add("切换网页端智云播放器")
            actions.add { attachWebView(webFallbackUrl) }
        } else if (activeWebView != null && streamCandidates.isNotEmpty()) {
            options.add("返回原生流媒体播放器")
            actions.add { playStreamAt(currentStreamIndex.coerceIn(0, streamCandidates.lastIndex)) }
        }
        if (activeWebView != null && customViewExitCallback != null) {
            options.add("隐藏顶部控制栏")
            actions.add { setControlsVisible(false) }
        }
        if (options.isEmpty()) return
        AlertDialog.Builder(this)
            .setTitle("播放器选项")
            .setItems(options.toTypedArray()) { dlg, which ->
                dlg.dismiss()
                actions[which].invoke()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun showSpeedDialog() {
        val labels = speeds.map { "${it}x" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("选择播放倍速")
            .setSingleChoiceItems(labels, speedIndex) { dlg, which ->
                dlg.dismiss()
                speedIndex = which
                val spd = speeds[speedIndex]
                speedPill.text = "${spd}x"
                activePlayer?.setPlaybackParameters(PlaybackParameters(spd))
                showHud("${spd}x 倍速")
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun showSourceDialog() {
        if (streamCandidates.isEmpty()) return
        val labels = streamCandidates.map { it.first }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("选择视频线路")
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
        speedPill.text = "${spd}x"
        activePlayer?.setPlaybackParameters(PlaybackParameters(spd))
        showHud("${spd}x 倍速")
    }

    private fun releasePlayer() {
        clearPrepareWatchdog()
        try {
            activePlayer?.stop()
            activePlayer?.release()
        } catch (_: Exception) {
        }
        activePlayer = null
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
        mainHandler.removeCallbacksAndMessages(null)
        orientationListener?.disable()
        orientationListener = null
        releasePlayer()
        activeWebView?.destroy()
        activeWebView = null
        super.onDestroy()
    }
}
