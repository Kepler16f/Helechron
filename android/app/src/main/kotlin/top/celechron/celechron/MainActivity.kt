package top.celechron.celechron

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StrictMode
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        const val WIDGET_CHANNEL = "top.celechron.celechron/widget"
        const val PREFS_NAME = "HelechronWidgetPrefs"
        const val EXTRA_TARGET = "target"
        private const val REQ_PICK_DIRECTORY = 4201
        private const val PREF_DIR_URI_MAP = "pickedDirTreeUriMap"
        private const val PREF_FILE_URI_MAP = "pickedFileUriMap"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingRoute: String? = null
    private var pendingDirPickResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

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
                "pickDirectory" -> {
                    launchNativeDirectoryPicker(result)
                }
                "copyFileToDirectory" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: ""
                    val targetDir = call.argument<String>("targetDir") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "courseware_file"
                    val rawMime = call.argument<String>("mimeType") ?: ""
                    copyFileToDirectory(sourcePath, targetDir, fileName, rawMime, result)
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

    private fun loadJsonStringMap(prefKey: String): JSONObject {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(prefKey, "{}") ?: "{}"
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun saveJsonStringMapEntry(prefKey: String, key: String, value: String) {
        val map = loadJsonStringMap(prefKey)
        map.put(key, value)
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(prefKey, map.toString())
            .apply()
    }

    private fun resolveReadablePathFromTreeUri(treeUri: Uri): String {
        try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            if (docId == "downloads") {
                return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).path
            }
            if (docId.startsWith("raw:")) {
                val rawPath = docId.removePrefix("raw:")
                if (rawPath.isNotEmpty()) return rawPath
            }
            val split = docId.split(":", limit = 2)
            if (split.size == 2) {
                val volumeId = split[0]
                val rel = split[1].trimStart('/')
                if (volumeId.equals("primary", ignoreCase = true)) {
                    val base = Environment.getExternalStorageDirectory().path.trimEnd('/')
                    return if (rel.isEmpty()) base else "$base/$rel"
                }
                if (volumeId.equals("home", ignoreCase = true)) {
                    val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).path.trimEnd('/')
                    return if (rel.isEmpty()) base else "$base/$rel"
                }
                return if (rel.isEmpty()) "/storage/$volumeId" else "/storage/$volumeId/$rel"
            }
        } catch (_: Exception) {
        }
        return treeUri.toString()
    }

    private fun launchNativeDirectoryPicker(result: MethodChannel.Result) {
        pendingDirPickResult?.success(null)
        pendingDirPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }
            startActivityForResult(intent, REQ_PICK_DIRECTORY)
        } catch (e: Exception) {
            val pending = pendingDirPickResult
            pendingDirPickResult = null
            pending?.error("PICK_DIR_UNAVAILABLE", e.message ?: "无法调起系统目录选择器", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_DIRECTORY) {
            val pending = pendingDirPickResult
            pendingDirPickResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending?.success(null)
                return
            }
            val treeUri = data.data!!
            val takeFlags = (data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
                .let { if (it != 0) it else (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) }
            try {
                contentResolver.takePersistableUriPermission(treeUri, takeFlags)
            } catch (_: Exception) {
            }
            val displayPath = resolveReadablePathFromTreeUri(treeUri)
            saveJsonStringMapEntry(PREF_DIR_URI_MAP, displayPath, treeUri.toString())
            pending?.success(displayPath)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun findExistingChildDocumentUri(treeUri: Uri, treeDocId: String, fileName: String): Uri? {
        return try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeDocId)
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            )
            contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    if (nameIdx >= 0 && idIdx >= 0 && cursor.getString(nameIdx) == fileName) {
                        val docId = cursor.getString(idIdx)
                        return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun copyFileToDirectory(
        sourcePath: String,
        targetDir: String,
        fileName: String,
        rawMime: String,
        result: MethodChannel.Result
    ) {
        if (sourcePath.isEmpty() || targetDir.isEmpty()) {
            result.success(null)
            return
        }
        Thread {
            try {
                val srcFile = File(sourcePath)
                if (!srcFile.exists() || srcFile.length() <= 0) {
                    mainHandler.post { result.success(null) }
                    return@Thread
                }

                val dirMap = loadJsonStringMap(PREF_DIR_URI_MAP)
                val treeUriStr = when {
                    targetDir.startsWith("content://") -> targetDir
                    dirMap.has(targetDir) -> dirMap.optString(targetDir, "")
                    else -> ""
                }

                if (treeUriStr.isNotEmpty()) {
                    val treeUri = Uri.parse(treeUriStr)
                    val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
                    val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)
                    val ext = MimeTypeMap.getFileExtensionFromUrl(fileName)?.lowercase() ?: ""
                    val mime = when {
                        rawMime.isNotEmpty() -> rawMime
                        ext.isNotEmpty() -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
                        else -> "application/octet-stream"
                    }
                    val existingUri = findExistingChildDocumentUri(treeUri, treeDocId, fileName)
                    val destUri = existingUri
                        ?: DocumentsContract.createDocument(contentResolver, parentDocUri, mime, fileName)
                    if (destUri != null) {
                        val mode = if (existingUri != null) "wt" else "w"
                        contentResolver.openOutputStream(destUri, mode)?.use { out ->
                            srcFile.inputStream().use { inp -> inp.copyTo(out) }
                        } ?: throw IllegalStateException("openOutputStream returned null")
                        val displayResult = if (targetDir.startsWith("content://")) {
                            destUri.toString()
                        } else {
                            val combined = "${targetDir.trimEnd('/')}/$fileName"
                            saveJsonStringMapEntry(PREF_FILE_URI_MAP, combined, destUri.toString())
                            combined
                        }
                        mainHandler.post { result.success(displayResult) }
                        return@Thread
                    }
                }

                if (!targetDir.startsWith("content://")) {
                    val outDir = File(targetDir)
                    if (!outDir.exists()) outDir.mkdirs()
                    val outFile = File(outDir, fileName)
                    srcFile.copyTo(outFile, overwrite = true)
                    mainHandler.post { result.success(outFile.absolutePath) }
                    return@Thread
                }

                mainHandler.post { result.success(null) }
            } catch (_: Exception) {
                mainHandler.post { result.success(null) }
            }
        }.start()
    }

    private fun openFileWithSystem(filePath: String, rawMime: String, title: String): Boolean {
        if (filePath.isEmpty()) return false
        return try {
            val builder = StrictMode.VmPolicy.Builder()
            StrictMode.setVmPolicy(builder.build())
            val fileUriMap = loadJsonStringMap(PREF_FILE_URI_MAP)
            val resolvedTarget = if (fileUriMap.has(filePath)) fileUriMap.optString(filePath, filePath) else filePath
            val uri = if (resolvedTarget.startsWith("content://") || resolvedTarget.startsWith("file://")) {
                Uri.parse(resolvedTarget)
            } else {
                val file = File(resolvedTarget)
                try {
                    androidx.core.content.FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    )
                } catch (_: Exception) {
                    Uri.fromFile(file)
                }
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
