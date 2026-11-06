package id.kkn.ewslumeneng

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** FileProvider sendiri agar tidak bentrok dengan milik plugin lain. */
class ReportFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ews/whatsapp")
            .setMethodCallHandler { call, result ->
                if (call.method != "send") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(
                    sendToWhatsApp(
                        phone = call.argument<String>("phone")!!,
                        text = call.argument<String>("text")!!,
                        imagePaths = call.argument<List<String>>("imagePaths").orEmpty(),
                    ),
                )
            }
    }

    /** Membuka chat [phone] langsung dengan teks dan foto, tanpa menu bagikan. */
    private fun sendToWhatsApp(phone: String, text: String, imagePaths: List<String>): Boolean {
        val whatsApp = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull(::isInstalled)
            ?: return false

        val uris = ArrayList(
            imagePaths.mapIndexedNotNull { index, path ->
                copyForSharing(path, index)?.let {
                    FileProvider.getUriForFile(this, "$packageName.reportfiles", it)
                }
            },
        )

        val action = if (uris.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND
        val intent = Intent(action).apply {
            setPackage(whatsApp)
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra("jid", "$phone@s.whatsapp.net")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            when {
                uris.size > 1 -> putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                uris.size == 1 -> putExtra(Intent.EXTRA_STREAM, uris.first())
            }
            type = if (uris.isEmpty()) "text/plain" else "image/jpeg"
            if (uris.isNotEmpty()) addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun isInstalled(packageName: String): Boolean = try {
        packageManager.getPackageInfo(packageName, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    // Foto dari image_picker bisa berada di luar folder yang dibagikan provider.
    private fun copyForSharing(path: String, index: Int): File? {
        val source = File(path)
        if (!source.exists()) return null
        val folder = File(cacheDir, "laporan").apply { mkdirs() }
        return source.copyTo(File(folder, "laporan_${index + 1}.jpg"), overwrite = true)
    }
}
