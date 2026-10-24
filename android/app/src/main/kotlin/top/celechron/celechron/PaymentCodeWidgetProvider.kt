package top.celechron.celechron

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import java.util.EnumMap

class PaymentCodeWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_REFRESH = "top.celechron.celechron.ACTION_REFRESH_PAYMENT"

        fun updateAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, PaymentCodeWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            if (allWidgetIds.isNotEmpty()) {
                val intent = Intent(context, PaymentCodeWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, allWidgetIds)
                }
                context.sendBroadcast(intent)
            }
        }

        private fun generateQrBitmap(content: String, size: Int = 400): Bitmap? {
            if (content.isEmpty()) return null
            return try {
                val hints = EnumMap<EncodeHintType, Any>(EncodeHintType::class.java).apply {
                    put(EncodeHintType.CHARACTER_SET, "UTF-8")
                    put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.M)
                    put(EncodeHintType.MARGIN, 1)
                }
                val matrix = MultiFormatWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
                val width = matrix.width
                val height = matrix.height
                val pixels = IntArray(width * height)
                for (y in 0 until height) {
                    val offset = y * width
                    for (x in 0 until width) {
                        pixels[offset + x] = if (matrix.get(x, y)) Color.BLACK else Color.WHITE
                    }
                }
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
                bitmap
            } catch (e: Exception) {
                null
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(MainActivity.EXTRA_TARGET, "ecardpaypage")
            }
            context.startActivity(launchIntent)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val paymentCode = prefs.getString("paymentCode", "") ?: ""
        val displayName = prefs.getString("displayName", "付款码") ?: "付款码"

        val qrBitmap = if (paymentCode.isNotEmpty()) generateQrBitmap(paymentCode, 400) else null

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_payment_code)
            views.setTextViewText(R.id.widget_payment_title, displayName)

            // Setup click intent to open ecardpaypage in MainActivity
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(MainActivity.EXTRA_TARGET, "ecardpaypage")
            }
            val pendingOpen = PendingIntent.getActivity(
                context, 2, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Setup refresh button
            val refreshIntent = Intent(context, PaymentCodeWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            val pendingRefresh = PendingIntent.getBroadcast(
                context, 3, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_payment_refresh, pendingRefresh)

            if (qrBitmap != null && paymentCode.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_payment_qr, View.VISIBLE)
                views.setViewVisibility(R.id.widget_payment_code_text, View.VISIBLE)
                views.setViewVisibility(R.id.widget_payment_empty_layout, View.GONE)

                views.setImageViewBitmap(R.id.widget_payment_qr, qrBitmap)

                val formatted = paymentCode.chunked(4).joinToString(" ")
                views.setTextViewText(R.id.widget_payment_code_text, formatted)

                views.setOnClickPendingIntent(R.id.widget_payment_qr_card, pendingOpen)
                views.setOnClickPendingIntent(R.id.widget_payment_root, pendingOpen)
            } else {
                views.setViewVisibility(R.id.widget_payment_qr, View.GONE)
                views.setViewVisibility(R.id.widget_payment_code_text, View.GONE)
                views.setViewVisibility(R.id.widget_payment_empty_layout, View.VISIBLE)

                views.setOnClickPendingIntent(R.id.widget_payment_empty_layout, pendingOpen)
                views.setOnClickPendingIntent(R.id.widget_payment_root, pendingOpen)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
