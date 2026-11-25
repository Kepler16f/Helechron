package top.celechron.celechron

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class CourseWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_REFRESH = "top.celechron.celechron.ACTION_REFRESH_COURSE"
        private val DEFAULT_ACCENT = Color.parseColor("#007AFF")
        private val COLOR_ONGOING = Color.parseColor("#16A34A")
        private val COLOR_URGENT = Color.parseColor("#D97706")
        private val COLOR_IDLE = Color.parseColor("#6B7280")

        fun resolveAccentColor(rawHex: String?): Int {
            val cleaned = rawHex?.trim()?.removePrefix("#") ?: ""
            return try {
                when (cleaned.length) {
                    6 -> Color.parseColor("#$cleaned")
                    8 -> Color.parseColor("#${cleaned.substring(2)}")
                    else -> DEFAULT_ACCENT
                }
            } catch (_: Exception) {
                DEFAULT_ACCENT
            }
        }

        private fun softTintColor(rgbColor: Int): Int {
            return Color.argb(
                0x1F,
                Color.red(rgbColor),
                Color.green(rgbColor),
                Color.blue(rgbColor)
            )
        }

        fun updateAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, CourseWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            if (allWidgetIds.isNotEmpty()) {
                val intent = Intent(context, CourseWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, allWidgetIds)
                }
                context.sendBroadcast(intent)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            if (launchIntent != null) {
                context.startActivity(launchIntent)
            }
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(ComponentName(context, CourseWidgetProvider::class.java))
            updateWidgets(context, appWidgetManager, allWidgetIds)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    private fun updateWidgets(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val coursesJsonStr = prefs.getString("coursesJson", "[]") ?: "[]"
        val leadWindowMinutes = prefs.getInt("leadWindowMinutes", 120)
        val accentColor = resolveAccentColor(prefs.getString("themePrimaryHex", "#007AFF"))

        val now = System.currentTimeMillis()
        val courseData = resolveCurrentCourse(coursesJsonStr, now, leadWindowMinutes, accentColor)
        val combinedStatus = if (courseData.statusTime.isNotEmpty()) {
            "${courseData.status} · ${courseData.statusTime}"
        } else {
            courseData.status
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_course)

            views.setInt(R.id.widget_brand_dot, "setColorFilter", accentColor)
            views.setInt(R.id.widget_refresh_bg, "setColorFilter", accentColor)
            views.setInt(R.id.widget_status_dot, "setColorFilter", courseData.statusColor)
            views.setInt(
                R.id.widget_status_pill_bg,
                "setColorFilter",
                softTintColor(courseData.statusColor)
            )
            views.setTextViewText(R.id.widget_course_name, courseData.name)
            views.setTextViewText(R.id.widget_course_status, combinedStatus)
            views.setTextColor(R.id.widget_course_status, courseData.statusColor)

            if (courseData.hasCourse) {
                views.setViewVisibility(R.id.widget_course_info_group, View.VISIBLE)
                views.setViewVisibility(R.id.widget_course_empty_hint, View.GONE)
                views.setInt(R.id.widget_time_bar, "setColorFilter", courseData.statusColor)
                views.setTextViewText(R.id.widget_course_time, courseData.time)

                val hasLoc = courseData.location.isNotEmpty()
                val hasTeacher = courseData.teacher.isNotEmpty()
                if (hasLoc || hasTeacher) {
                    views.setViewVisibility(R.id.widget_course_meta_row, View.VISIBLE)
                    views.setTextViewText(
                        R.id.widget_course_location,
                        if (hasLoc) courseData.location else courseData.teacher
                    )
                    if (hasLoc && hasTeacher) {
                        views.setViewVisibility(R.id.widget_course_teacher, View.VISIBLE)
                        views.setTextViewText(R.id.widget_course_teacher, courseData.teacher)
                    } else {
                        views.setViewVisibility(R.id.widget_course_teacher, View.GONE)
                    }
                } else {
                    views.setViewVisibility(R.id.widget_course_meta_row, View.GONE)
                }

                if (courseData.showProgress) {
                    views.setViewVisibility(R.id.widget_course_progress, View.VISIBLE)
                    views.setProgressBar(R.id.widget_course_progress, 100, courseData.progress, false)
                } else {
                    views.setViewVisibility(R.id.widget_course_progress, View.GONE)
                }
            } else {
                views.setViewVisibility(R.id.widget_course_info_group, View.GONE)
                views.setViewVisibility(R.id.widget_course_empty_hint, View.VISIBLE)
                views.setViewVisibility(R.id.widget_course_progress, View.GONE)
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingLaunch = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_course_root, pendingLaunch)

            val refreshIntent = Intent(context, CourseWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            val pendingRefresh = PendingIntent.getBroadcast(
                context, 1, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_course_refresh, pendingRefresh)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    data class CourseDisplayData(
        val name: String,
        val status: String,
        val statusTime: String,
        val statusColor: Int,
        val time: String,
        val location: String,
        val teacher: String,
        val showProgress: Boolean,
        val progress: Int,
        val hasCourse: Boolean
    )

    private fun resolveCurrentCourse(
        coursesJsonStr: String,
        now: Long,
        leadWindowMinutes: Int,
        accentColor: Int
    ): CourseDisplayData {
        try {
            val jsonArray = JSONArray(coursesJsonStr)
            val courses = mutableListOf<CourseItem>()
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                courses.add(
                    CourseItem(
                        s = obj.optLong("s", 0L),
                        e = obj.optLong("e", 0L),
                        n = obj.optString("n", ""),
                        t = obj.optString("t", ""),
                        l = obj.optString("l", ""),
                        c = obj.optString("c", "")
                    )
                )
            }
            courses.sortBy { it.s }

            for (c in courses) {
                if (now in c.s..c.e) {
                    val remainingMin = Math.max(1, ((c.e - now) / 60000).toInt())
                    val totalDuration = Math.max(1, c.e - c.s)
                    val progress = (((now - c.s) * 100) / totalDuration).toInt().coerceIn(0, 100)
                    return CourseDisplayData(
                        name = c.n,
                        status = "上课中",
                        statusTime = "剩${remainingMin}分",
                        statusColor = COLOR_ONGOING,
                        time = c.t,
                        location = c.l,
                        teacher = c.c,
                        showProgress = true,
                        progress = progress,
                        hasCourse = true
                    )
                }
            }

            for (c in courses) {
                if (now < c.s) {
                    val diffMin = ((c.s - now) / 60000).toInt()
                    val (status, statusTime, color) = when {
                        diffMin <= 0 -> Triple("即将开始", "", accentColor)
                        diffMin <= 20 -> Triple("${diffMin}分钟后上课", "", COLOR_URGENT)
                        diffMin <= leadWindowMinutes -> {
                            val timeStr = if (diffMin < 60) {
                                "${diffMin}分钟后"
                            } else {
                                val m = diffMin % 60
                                if (m > 0) "${diffMin / 60}小时${m}分后" else "${diffMin / 60}小时后"
                            }
                            Triple(timeStr, "", accentColor)
                        }
                        else -> {
                            val startTime = c.t.split(" - ").firstOrNull() ?: ""
                            Triple("待上课", startTime, accentColor)
                        }
                    }
                    return CourseDisplayData(
                        name = c.n,
                        status = status,
                        statusTime = statusTime,
                        statusColor = color,
                        time = c.t,
                        location = c.l,
                        teacher = c.c,
                        showProgress = false,
                        progress = 0,
                        hasCourse = true
                    )
                }
            }

            val isFinished = courses.isNotEmpty()
            return CourseDisplayData(
                name = if (isFinished) "今日课程已结束" else "今日暂无课程",
                status = if (isFinished) "全部结课" else "暂无日程",
                statusTime = "",
                statusColor = COLOR_IDLE,
                time = "",
                location = "",
                teacher = "",
                showProgress = false,
                progress = 0,
                hasCourse = false
            )
        } catch (_: Exception) {
            return CourseDisplayData(
                name = "今日暂无课程",
                status = "暂无日程",
                statusTime = "",
                statusColor = COLOR_IDLE,
                time = "",
                location = "",
                teacher = "",
                showProgress = false,
                progress = 0,
                hasCourse = false
            )
        }
    }

    private data class CourseItem(
        val s: Long,
        val e: Long,
        val n: String,
        val t: String,
        val l: String,
        val c: String
    )
}
