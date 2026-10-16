package com.medstock.med_stock

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Adds "Save PDF": the system Save dialog (Storage Access Framework), so a
 *  file goes where the user picks (Downloads, Drive, ...) with no storage
 *  permission. */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medikabiz/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") return@setMethodCallHandler result.notImplemented()
                if (pending != null) return@setMethodCallHandler result.error("busy", "A save is already open", null)
                pending = result
                pendingBytes = call.argument<ByteArray>("bytes")
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                }
                startActivityForResult(intent, SAVE_REQUEST)
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val result = pending ?: return
        val bytes = pendingBytes
        pending = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) return result.success(null)
        try {
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            result.success(where(uri))
        } catch (e: Exception) {
            result.error("write_failed", e.message, null)
        }
    }

    /** "Download/Invoice-INV-26-27-000001.pdf" for the phone's own storage,
     *  else the file name. */
    private fun where(uri: Uri): String {
        try {
            if (uri.authority == "com.android.externalstorage.documents") {
                val id = DocumentsContract.getDocumentId(uri)
                if (id.contains(':')) return id.substringAfter(':')
            }
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) return it.getString(0)
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment ?: "the chosen folder"
    }

    companion object {
        private const val SAVE_REQUEST = 4711
    }
}
