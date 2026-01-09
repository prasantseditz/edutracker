package com.pglive.edutracker

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.util.Base64
import android.widget.Toast
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.Charset

class MainActivity : FlutterFragmentActivity() {

    private val MAIL_CHANNEL = "com.edutracker/mail"
    private val SAF_CHANNEL = "com.edutracker/saf"
    private val REQ_OPEN_DOCUMENT_TREE = 1001
    private var pendingOpenTreeResult: MethodChannel.Result? = null
    private lateinit var safChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

       

        // Mail channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAIL_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "composeEmail") {
                    val to = call.argument<String>("to") ?: ""
                    val subject = call.argument<String>("subject") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val opened = openMailApp(to, subject, body)
                    result.success(opened)
                } else {
                    result.notImplemented()
                }
            }

        // SAF channel
        safChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL)
        safChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocumentTree" -> openDocumentTree(result)
                "listFiles" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    if (treeUriStr == null) result.error("ARG_NULL", "treeUri is null", null)
                    else result.success(listFilesInTree(Uri.parse(treeUriStr)))
                }
                "createFileInTree" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    val filename = call.argument<String>("filename") ?: "file.txt"
                    val mime = call.argument<String>("mime") ?: "application/json"
                    val base64Data = call.argument<String>("base64Data") ?: ""
                    if (treeUriStr == null) {
                        result.error("ARG_NULL", "treeUri is null", null)
                    } else {
                        val createdUri = createFileInTree(Uri.parse(treeUriStr), filename, mime, base64Data)
                        if (createdUri != null) result.success(createdUri.toString())
                        else result.error("CREATE_FAILED", "Could not create file", null)
                    }
                }
                "readFile" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) result.error("ARG_NULL", "uri is null", null)
                    else {
                        val content = readFileContent(Uri.parse(uriStr))
                        if (content != null) result.success(content)
                        else result.error("READ_FAILED", "Could not read file", null)
                    }
                }
                "deleteFile" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) result.error("ARG_NULL", "uri is null", null)
                    else result.success(deleteFile(Uri.parse(uriStr)))
                }
                else -> result.notImplemented()
            }
        }
    }

    // SAF helpers
    private fun openDocumentTree(result: MethodChannel.Result) {
        if (pendingOpenTreeResult != null) {
            result.error("IN_PROGRESS", "Another openDocumentTree request is in progress", null)
            return
        }
        pendingOpenTreeResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            startActivityForResult(intent, REQ_OPEN_DOCUMENT_TREE)
        } catch (e: Exception) {
            pendingOpenTreeResult = null
            result.error("INTENT_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_OPEN_DOCUMENT_TREE) {
            val res = pendingOpenTreeResult
            pendingOpenTreeResult = null
            if (res == null) return
            if (resultCode == Activity.RESULT_OK && data != null) {
                val treeUri: Uri? = data.data
                if (treeUri != null) {
                    try {
                        val flags = data.flags
                        val takeFlags = (flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
                        contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                    } catch (_: Exception) {}
                    res.success(treeUri.toString())
                    return
                }
            }
            res.error("CANCELED", "User canceled folder selection or returned no uri", null)
        }
    }

    private fun listFilesInTree(treeUri: Uri): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        try {
            val pickedDir = DocumentFile.fromTreeUri(this, treeUri)
            if (pickedDir != null && pickedDir.exists()) {
                for (child in pickedDir.listFiles()) {
                    result.add(
                        mapOf(
                            "name" to child.name,
                            "uri" to child.uri.toString(),
                            "isDirectory" to child.isDirectory,
                            "length" to try { child.length() } catch (_: Throwable) { null }
                        )
                    )
                }
            }
        } catch (_: Exception) {}
        return result
    }

    private fun createFileInTree(treeUri: Uri, filename: String, mime: String, base64Data: String): Uri? {
        return try {
            val pickedDir = DocumentFile.fromTreeUri(this, treeUri) ?: return null
            pickedDir.findFile(filename)?.delete()
            val created = pickedDir.createFile(mime, filename) ?: return null
            contentResolver.openOutputStream(created.uri)?.use { out ->
                val bytes = if (base64Data.isEmpty()) ByteArray(0) else Base64.decode(base64Data, Base64.DEFAULT)
                ByteArrayInputStream(bytes).copyTo(out)
                out.flush()
            }
            created.uri
        } catch (_: Exception) {
            null
        }
    }

    private fun readFileContent(uri: Uri): String? {
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                val bytes = input.readBytes()
                String(bytes, Charset.forName("UTF-8"))
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteFile(uri: Uri): Boolean {
        return try {
            DocumentFile.fromSingleUri(this, uri)?.delete() ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openMailApp(to: String, subject: String, body: String): Boolean {
        val gmailPackage = "com.google.android.gm"
        if (isPackageInstalled(gmailPackage)) {
            return try {
                val intent = Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("mailto:")
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                    `package` = gmailPackage
                }
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }
        return try {
            val uri = Uri.parse("mailto:${Uri.encode(to)}?subject=${Uri.encode(subject)}&body=${Uri.encode(body)}")
            startActivity(Intent.createChooser(Intent(Intent.ACTION_SENDTO, uri), "Send email"))
            true
        } catch (_: Exception) {
            Toast.makeText(this, "No email app found", Toast.LENGTH_SHORT).show()
            false
        }
    }
}
