package id.kkn.ewslumeneng

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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
                val whatsApp = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull(::isInstalled)
                if (whatsApp == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val phone = call.argument<String>("phone")!!
                val text = call.argument<String>("text")!!
                val imagePaths = call.argument<List<String>>("imagePaths").orEmpty()
                val intent = when (call.method) {
                    "openChat" -> chatIntent(whatsApp, phone, text)
                    "send" -> reportIntent(whatsApp, phone, text, imagePaths)
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                result.success(
                    try {
                        startActivity(intent)
                        true
                    } catch (_: ActivityNotFoundException) {
                        false
                    },
                )
            }
    }

    /**
     * Chat [phone] dengan teks terisi lewat tautan wa.me. Selalu langsung ke
     * chat walau nomornya tidak ada di kontak, tapi tanpa foto.
     */
    private fun chatIntent(whatsApp: String, phone: String, text: String): Intent {
        val link = Uri.parse("https://api.whatsapp.com/send?phone=$phone&text=${Uri.encode(text)}")
        return Intent(Intent.ACTION_VIEW, link).setPackage(whatsApp)
    }

    /**
     * Chat [phone] dengan teks dan foto. WhatsApp hanya menuruti `jid` bila
     * nomornya ada di kontak atau sudah pernah chat; selain itu muncul menu
     * "Kirim ke...".
     */
    private fun reportIntent(
        whatsApp: String,
        phone: String,
        text: String,
        imagePaths: List<String>,
    ): Intent {
        val uris = ArrayList(
            imagePaths.mapIndexedNotNull { index, path ->
                copyForSharing(path, index)?.let {
                    FileProvider.getUriForFile(this, "$packageName.reportfiles", it)
                }
            },
        )
        val action = if (uris.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND
        return Intent(action).apply {
            setPackage(whatsApp)
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra("jid", "$phone@s.whatsapp.net")
            when {
                uris.size > 1 -> putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                uris.size == 1 -> putExtra(Intent.EXTRA_STREAM, uris.first())
            }
            type = if (uris.isEmpty()) "text/plain" else "image/jpeg"
            if (uris.isNotEmpty()) addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
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
