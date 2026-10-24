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

        val now = System.currentTimeMillis()
        val courseData = resolveCurrentCourse(coursesJsonStr, now, leadWindowMinutes)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_course)

            views.setTextViewText(R.id.widget_course_name, courseData.name)
            views.setTextViewText(R.id.widget_course_status, courseData.status)
            views.setTextColor(R.id.widget_course_status, courseData.statusColor)
            views.setTextViewText(R.id.widget_course_status_time, courseData.statusTime)
            views.setTextColor(R.id.widget_course_status_time, courseData.statusColor)

            if (courseData.hasCourse) {
                views.setViewVisibility(R.id.widget_course_time, View.VISIBLE)
                views.setTextViewText(R.id.widget_course_time, courseData.time)

                if (courseData.location.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_course_location, View.VISIBLE)
                    views.setTextViewText(R.id.widget_course_location, courseData.location)
                } else {
                    views.setViewVisibility(R.id.widget_course_location, View.GONE)
                }

                if (courseData.teacher.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_course_teacher, View.VISIBLE)
                    views.setTextViewText(R.id.widget_course_teacher, courseData.teacher)
                } else {
                    views.setViewVisibility(R.id.widget_course_teacher, View.GONE)
                }

                if (courseData.showProgress) {
                    views.setViewVisibility(R.id.widget_course_progress, View.VISIBLE)
                    views.setProgressBar(R.id.widget_course_progress, 100, courseData.progress, false)
                } else {
                    views.setViewVisibility(R.id.widget_course_progress, View.GONE)
                }
            } else {
                views.setViewVisibility(R.id.widget_course_time, View.GONE)
                views.setViewVisibility(R.id.widget_course_location, View.GONE)
                views.setViewVisibility(R.id.widget_course_teacher, View.GONE)
                views.setViewVisibility(R.id.widget_course_progress, View.GONE)
            }

            // Click root -> open MainActivity
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingLaunch = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_course_root, pendingLaunch)

            // Click refresh -> broadcast refresh
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

    private fun resolveCurrentCourse(coursesJsonStr: String, now: Long, leadWindowMinutes: Int): CourseDisplayData {
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

            // 1. Check if currently in class
            for (c in courses) {
                if (now in c.s..c.e) {
                    val remainingMin = Math.max(1, ((c.e - now) / 60000).toInt())
                    val totalDuration = Math.max(1, c.e - c.s)
                    val progress = (((now - c.s) * 100) / totalDuration).toInt().coerceIn(0, 100)
                    return CourseDisplayData(
                        name = c.n,
                        status = "正在上课",
                        statusTime = "距下课 $remainingMin 分钟",
                        statusColor = Color.parseColor("#1E88E5"),
                        time = c.t,
                        location = c.l,
                        teacher = c.c,
                        showProgress = true,
                        progress = progress,
                        hasCourse = true
                    )
                }
            }

            // 2. Check for next upcoming course
            for (c in courses) {
                if (now < c.s) {
                    val diffMin = ((c.s - now) / 60000).toInt()
                    val (status, statusTime, color) = if (diffMin <= leadWindowMinutes) {
                        val timeStr = if (diffMin < 60) "${diffMin}分钟后" else "${diffMin / 60}小时${diffMin % 60}分后"
                        Triple("下一节", timeStr, Color.parseColor("#E65100"))
                    } else {
                        val startTime = c.t.split(" - ").firstOrNull() ?: ""
                        Triple("今日课程", startTime, Color.parseColor("#2E7D32"))
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
                status = if (isFinished) "全部结课" else "无日程",
                statusTime = "",
                statusColor = Color.parseColor("#8E8E93"),
                time = "",
                location = "",
                teacher = "",
                showProgress = false,
                progress = 0,
                hasCourse = false
            )
        } catch (e: Exception) {
            return CourseDisplayData(
                name = "今日暂无课程",
                status = "无日程",
                statusTime = "",
                statusColor = Color.parseColor("#8E8E93"),
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
