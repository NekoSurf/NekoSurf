package com.wrngwrld.chanyan

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/// The folder Save to Photos puts files in, when one's picked
/// (lib/saved/download_folder.dart): any folder Android's folder picker
/// offers, an SD card's too, kept with a lasting grant to write there.
class DownloadFolder(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "nekosurf/download_folder"
        private const val PICK_REQUEST = 0x4e4b
    }

    private var picking: MethodChannel.Result? = null

    // One copy at a time, so saves into a new thread folder at once make one
    // folder, not "Thread (1)" beside it.
    private val copies = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "forget" -> {
                forget(call.argument<String>("folder")!!)
                result.success(null)
            }
            "copy" -> copies.execute {
                copy(
                    call.argument<String>("folder")!!,
                    call.argument<String>("subfolder"),
                    call.argument<String>("path")!!,
                    call.argument<String>("name")!!,
                    result,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result) {
        picking?.success(null)
        picking = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        activity.startActivityForResult(intent, PICK_REQUEST)
    }

    /// Whether this was the picker's answer.
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) {
            return false
        }
        val result = picking ?: return true
        picking = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(uri.toString())
        } catch (e: SecurityException) {
            result.error("denied", e.message, null)
        }
        return true
    }

    /// Gives up the grant for [folder], once another is picked or it's reset.
    private fun forget(folder: String) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                Uri.parse(folder),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Not held any more.
        }
    }

    private fun copy(
        folder: String,
        subfolder: String?,
        path: String,
        name: String,
        result: MethodChannel.Result,
    ) {
        val tree = Uri.parse(folder)
        val granted = activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }
        var dir = if (granted) DocumentFile.fromTreeUri(activity, tree) else null
        if (dir == null || !dir.isDirectory || !dir.canWrite()) {
            // Deleted, on an SD card taken out, or the grant was taken back.
            main.post { result.error("gone", "The download folder can't be reached", null) }
            return
        }
        var made: DocumentFile? = null
        try {
            if (subfolder != null) {
                dir = dir.findFile(subfolder)?.takeIf { it.isDirectory }
                    ?: dir.createDirectory(subfolder)
                    ?: throw IllegalStateException("Couldn't make $subfolder")
            }
            val extension = name.substringAfterLast('.', "").lowercase()
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
            // A name already there gets a number added, by Android.
            made = dir.createFile(mime, name) ?: throw IllegalStateException("Couldn't make $name")
            val out = activity.contentResolver.openOutputStream(made.uri)
                ?: throw IllegalStateException("Couldn't write $name")
            out.use { stream -> File(path).inputStream().use { it.copyTo(stream) } }
            main.post { result.success(null) }
        } catch (e: Exception) {
            made?.delete()
            main.post { result.error("failed", e.message, null) }
        }
    }
}
