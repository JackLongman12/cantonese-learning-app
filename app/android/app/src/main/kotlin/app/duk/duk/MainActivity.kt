package app.duk.duk

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives text from other apps: "Share" (ACTION_SEND) and the text-selection menu
 * (ACTION_PROCESS_TEXT). The text is handed to Dart over the "ducklearn/share" channel:
 * Dart asks for text that launched the app, and is told about text arriving later.
 */
class MainActivity : FlutterActivity() {
    private var pending: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = sharedText(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ducklearn/update").setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val problem = installApk(call.argument<String>("path")!!)
                if (problem == null) result.success(null) else result.error(problem, null, null)
            } else {
                result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ducklearn/share").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "takeSharedText") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    /** Opens the system installer for a downloaded update (see lib/platform/updater.dart). */
    private fun installApk(path: String): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            // One-time: the learner allows DuckLearn to install its own updates.
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return "needs_permission"
        }
        // only an APK the updater downloaded into its own cache folder
        val file = File(path).canonicalFile
        val updates = File(cacheDir, "ducklearn_updates").canonicalFile
        if (file.parentFile != updates || !file.name.endsWith(".apk")) return "bad_path"
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        return null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = sharedText(intent) ?: return
        channel?.invokeMethod("sharedText", text) ?: run { pending = text }
    }

    private fun sharedText(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
        Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        else -> null
    }?.takeIf { it.isNotBlank() }
        // any app can share in: cap the size so a huge text can't freeze the reader
        ?.take(20000)
}
