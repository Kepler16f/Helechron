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
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
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
    }

    private enum class IconKind {
        BACK, PLAY, PAUSE, FULLSCREEN, FULLSCREEN_EXIT, PIP, ROTATE, MORE
    }

    private class VectorIconDrawable(
        private val kind: IconKind,
        private val color: Int = Color.WHITE
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

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.width() <= 0 || b.height() <= 0) return
            val sx = b.width() / 24f
            val sy = b.height() / 24f
            strokePaint.strokeWidth = 2.1f * minOf(sx, sy)
            canvas.save()
            canvas.translate(b.left.toFloat(), b.top.toFloat())
            canvas.scale(sx, sy)

            when (kind) {
                IconKind.BACK -> {
                    val p = Path().apply {
                        moveTo(15f, 5f)
                        lineTo(8f, 12f)
                        lineTo(15f, 19f)
                    }
                    canvas.drawPath(p, strokePaint)
                }

                IconKind.PLAY -> {
                    val p = Path().apply {
                        moveTo(7f, 4.5f)
                        lineTo(19.5f, 12f)
                        lineTo(7f, 19.5f)
                        close()
                    }
                    canvas.drawPath(p, fillPaint)
                }

                IconKind.PAUSE -> {
                    canvas.drawRoundRect(RectF(6.5f, 5f, 10.2f, 19f), 1.2f, 1.2f, fillPaint)
                    canvas.drawRoundRect(RectF(13.8f, 5f, 17.5f, 19f), 1.2f, 1.2f, fillPaint)
                }

                IconKind.FULLSCREEN -> {
                    val p = Path().apply {
                        moveTo(4f, 9f); lineTo(4f, 4f); lineTo(9f, 4f)
                        moveTo(15f, 4f); lineTo(20f, 4f); lineTo(20f, 9f)
                        moveTo(20f, 15f); lineTo(20f, 20f); lineTo(15f, 20f)
                        moveTo(9f, 20f); lineTo(4f, 20f); lineTo(4f, 15f)
                    }
                    canvas.drawPath(p, strokePaint)
                }

                IconKind.FULLSCREEN_EXIT -> {
                    val p = Path().apply {
                        moveTo(9f, 4f); lineTo(9f, 9f); lineTo(4f, 9f)
                        moveTo(15f, 4f); lineTo(15f, 9f); lineTo(20f, 9f)
                        moveTo(15f, 20f); lineTo(15f, 15f); lineTo(20f, 15f)
                        moveTo(9f, 20f); lineTo(9f, 15f); lineTo(4f, 15f)
                    }
                    canvas.drawPath(p, strokePaint)
                }

                IconKind.PIP -> {
                    canvas.drawRoundRect(RectF(3f, 5f, 21f, 19f), 2.2f, 2.2f, strokePaint)
                    canvas.drawRoundRect(RectF(11.5f, 11.5f, 18.8f, 16.8f), 1.2f, 1.2f, fillPaint)
                }

                IconKind.ROTATE -> {
                    canvas.drawRoundRect(RectF(6.5f, 4.5f, 17.5f, 19.5f), 2.0f, 2.0f, strokePaint)
                    val arr = Path().apply {
                        moveTo(3.5f, 9.5f); lineTo(3.5f, 6f); lineTo(6.8f, 6f)
                        moveTo(20.5f, 14.5f); lineTo(20.5f, 18f); lineTo(17.2f, 18f)
                    }
                    canvas.drawPath(arr, strokePaint)
                }

                IconKind.MORE -> {
                    canvas.drawCircle(6f, 12f, 1.8f, fillPaint)
                    canvas.drawCircle(12f, 12f, 1.8f, fillPaint)
                    canvas.drawCircle(18f, 12f, 1.8f, fillPaint)
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
    private lateinit var rotateBtn: ImageView
    private lateinit var pipBtn: ImageView
    private lateinit var moreBtn: ImageView
    private lateinit var centerPlayBtn: ImageView
    private lateinit var bottomPlayBtn: ImageView
    private lateinit var timeCurrentView: TextView
    private lateinit var timeDurationView: TextView
    private lateinit var seekBar: SeekBar
    private lateinit var speedPill: TextView
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
            if (isDirectStreamUrl(trimmed) || trimmed.contains("cmc.zju.edu.cn")) {
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

    private fun makeIconBtn(kind: IconKind, sizeDp: Int = 38, padDp: Int = 9, color: Int = Color.WHITE, onClick: () -> Unit): ImageView {
        return ImageView(this).apply {
            setImageDrawable(VectorIconDrawable(kind, color))
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
                val player = activePlayer ?: return false
                val w = gestureLayer.width.coerceAtLeast(1)
                when {
                    e.x < w * 0.30f -> seekBy(-10_000L, "-10s")
                    e.x > w * 0.70f -> seekBy(10_000L, "+10s")
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
                intArrayOf(Color.parseColor("#CC000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val backBtn = makeIconBtn(IconKind.BACK, sizeDp = 40, padDp = 9) {
            if (isFullscreen) {
                toggleLandscapeFullscreen()
            } else {
                finish()
            }
        }

        titleView = TextView(this).apply {
            text = titleText
            textSize = 15f
            setTextColor(Color.WHITE)
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(4), 0, dp(8), 0)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        rotateBtn = makeIconBtn(IconKind.ROTATE, sizeDp = 38, padDp = 9, color = SAKURA_ACCENT) {
            sensorAutoRotate = !sensorAutoRotate
            updateRotateIcon()
            if (!sensorAutoRotate && !isFullscreenLocked) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
                showHud("已锁定当前方向")
            } else if (sensorAutoRotate) {
                orientationListener?.enable()
                showHud("已开启重力旋屏")
            }
        }

        pipBtn = makeIconBtn(IconKind.PIP, sizeDp = 38, padDp = 9) {
            enterPipMode()
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            pipBtn.visibility = View.GONE
        }

        moreBtn = makeIconBtn(IconKind.MORE, sizeDp = 38, padDp = 9) {
            showMoreMenuDialog()
        }

        topBar.addView(backBtn)
        topBar.addView(titleView)
        topBar.addView(rotateBtn)
        topBar.addView(pipBtn)
        topBar.addView(moreBtn)

        // Center Play/Pause Floating Button
        centerPlayBtn = ImageView(this).apply {
            setImageDrawable(VectorIconDrawable(IconKind.PLAY, Color.WHITE))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(14)
            setPadding(p, p, p, p)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#88000000"))
            }
            layoutParams = FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER)
            setOnClickListener { togglePlayPause(showBanner = false) }
        }

        // Bottom Bar Scrim
        bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
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

        bottomPlayBtn = makeIconBtn(IconKind.PLAY, sizeDp = 36, padDp = 8) {
            togglePlayPause(showBanner = false)
        }

        timeCurrentView = TextView(this).apply {
            text = "00:00"
            textSize = 11.5f
            setTextColor(Color.WHITE)
            setPadding(dp(4), 0, dp(6), 0)
        }

        seekBar = SeekBar(this).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            thumbTintList = ColorStateList.valueOf(Color.WHITE)
            progressBackgroundTintList = ColorStateList.valueOf(Color.parseColor("#55FFFFFF"))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
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
            textSize = 11.5f
            setTextColor(Color.parseColor("#CCFFFFFF"))
            setPadding(dp(6), 0, dp(6), 0)
        }

        speedPill = TextView(this).apply {
            text = "1.0x"
            textSize = 11.5f
            setTextColor(Color.WHITE)
            setPadding(dp(8), dp(4), dp(8), dp(4))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Color.parseColor("#44FFFFFF"))
            }
            setOnClickListener {
                cycleSpeed()
                scheduleAutoHide()
            }
        }

        fullscreenBtn = makeIconBtn(IconKind.FULLSCREEN, sizeDp = 38, padDp = 9) {
            toggleLandscapeFullscreen()
        }

        bottomBar.addView(bottomPlayBtn)
        bottomBar.addView(timeCurrentView)
        bottomBar.addView(seekBar)
        bottomBar.addView(timeDurationView)
        bottomBar.addView(speedPill)
        bottomBar.addView(fullscreenBtn)

        overlayRoot.addView(topBar)
        overlayRoot.addView(centerPlayBtn)
        overlayRoot.addView(bottomBar)

        bufferingSpinner = ProgressBar(this).apply {
            indeterminateTintList = ColorStateList.valueOf(SAKURA_ACCENT)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(dp(42), dp(42), Gravity.CENTER)
        }

        webBarToggleBtn = ImageView(this).apply {
            setImageDrawable(VectorIconDrawable(IconKind.MORE, Color.WHITE))
            scaleType = ImageView.ScaleType.FIT_CENTER
            val p = dp(7)
            setPadding(p, p, p, p)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#88000000"))
            }
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(dp(34), dp(34), Gravity.TOP or Gravity.END)
            setOnClickListener {
                setControlsVisible(!controlsVisible)
            }
        }

        hudPill = TextView(this).apply {
            textSize = 13f
            setTextColor(Color.WHITE)
            setPadding(dp(14), dp(7), dp(14), dp(7))
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
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
        val topExtra = if (isFullscreen) maxOf(dp(10), safeTop + dp(6)) else maxOf(dp(14), safeTop + dp(8))
        val bottomExtra = if (isFullscreen) maxOf(dp(10), safeBottom + dp(6)) else maxOf(dp(12), safeBottom + dp(8))

        topBar.setPadding(hPadLeft, topExtra, hPadRight, dp(14))
        bottomBar.setPadding(hPadLeft, dp(14), hPadRight, bottomExtra)

        (webBarToggleBtn.layoutParams as FrameLayout.LayoutParams).apply {
            topMargin = topExtra + dp(2)
            rightMargin = hPadRight + dp(2)
        }
        webBarToggleBtn.requestLayout()

        (hudPill.layoutParams as FrameLayout.LayoutParams).topMargin = topExtra + dp(52)
        hudPill.requestLayout()
    }

    private fun updateRotateIcon() {
        rotateBtn.setImageDrawable(
            VectorIconDrawable(IconKind.ROTATE, if (sensorAutoRotate) SAKURA_ACCENT else Color.WHITE)
        )
    }

    private fun updatePlayPauseIcons() {
        val playing = activePlayer?.isPlaying == true
        val kind = if (playing) IconKind.PAUSE else IconKind.PLAY
        centerPlayBtn.setImageDrawable(VectorIconDrawable(kind, Color.WHITE))
        bottomPlayBtn.setImageDrawable(VectorIconDrawable(kind, Color.WHITE))
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
        controlsVisible = visible
        overlayRoot.visibility = if (visible) View.VISIBLE else View.GONE
        val isWeb = activeWebView != null
        bottomBar.visibility = if (isWeb) View.GONE else View.VISIBLE
        centerPlayBtn.visibility = if (isWeb) View.GONE else View.VISIBLE
        webBarToggleBtn.visibility = if (isWeb && !visible) View.VISIBLE else View.GONE
        if (visible) {
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
        if (player.isCurrentMediaItemLive || dur <= 0L || dur == C.TIME_UNSET) {
            timeCurrentView.text = if (pos > 0) formatMs(pos) else "直播"
            timeDurationView.text = "LIVE"
            seekBar.isEnabled = false
            seekBar.progress = 1000
        } else {
            seekBar.isEnabled = true
            timeCurrentView.text = formatMs(pos)
            timeDurationView.text = formatMs(dur)
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
        fullscreenBtn.setImageDrawable(
            VectorIconDrawable(if (fullscreen) IconKind.FULLSCREEN_EXIT else IconKind.FULLSCREEN, Color.WHITE)
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
        videoContainer.removeAllViews()
        gestureLayer.visibility = View.VISIBLE
        bufferingSpinner.visibility = View.VISIBLE

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
            override fun onPlaybackStateChanged(playbackState: Int) {
                bufferingSpinner.visibility =
                    if (playbackState == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
                updatePlayPauseIcons()
                if (playbackState == Player.STATE_READY) {
                    scheduleAutoHide()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                updatePlayPauseIcons()
                if (isPlaying) {
                    scheduleAutoHide()
                } else {
                    mainHandler.removeCallbacks(autoHideRunnable)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
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
        setControlsVisible(true)
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
        videoContainer.removeAllViews()
        gestureLayer.visibility = View.GONE
        bufferingSpinner.visibility = View.GONE

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
        videoContainer.addView(
            wv,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        videoContainer.addView(customViewHolder)
        setControlsVisible(true)
        updatePipParams()
    }

    private fun showMoreMenuDialog() {
        val options = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        if (activeWebView == null) {
            options.add("倍速播放（当前 ${speeds[speedIndex]}x）")
            actions.add { showSpeedDialog() }
        }
        if (streamCandidates.size > 1) {
            options.add("切换视频线路（共 ${streamCandidates.size} 条）")
            actions.add { showSourceDialog() }
        }
        if (activeWebView == null && webFallbackUrl.isNotEmpty()) {
            options.add("切换网页端智云播放器")
            actions.add { attachWebView(webFallbackUrl) }
        } else if (activeWebView != null && streamCandidates.isNotEmpty()) {
            options.add("返回原生流媒体播放器")
            actions.add { playStreamAt(currentStreamIndex.coerceIn(0, streamCandidates.lastIndex)) }
        }
        if (activeWebView != null) {
            options.add("收起顶部工具栏")
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
