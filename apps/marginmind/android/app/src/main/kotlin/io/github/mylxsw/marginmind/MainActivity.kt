package io.github.mylxsw.marginmind

import android.content.Intent
import android.content.ClipData
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger
        engine.platformViewsController.registry.registerViewFactory("marginmind/browser", BrowserFactory(this, messenger))
        MethodChannel(messenger, "marginmind/secret_store").setMethodCallHandler { call, result ->
            if (call.method !in listOf("read", "write", "delete")) {
                result.notImplemented(); return@setMethodCallHandler
            }
            val account = call.argument<String>("account")
            if (account.isNullOrEmpty() || account.length > 256) {
                result.error("invalid_request", null, null); return@setMethodCallHandler
            }
            try {
                val prefs = getSharedPreferences("encrypted_secrets", MODE_PRIVATE)
                when (call.method) {
                    "read" -> {
                        val stored = prefs.getString(account, null)
                        if (stored == null) result.success(null) else {
                            val parts = stored.split(":")
                            require(parts.size == 2)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                            cipher.updateAAD(account.toByteArray(Charsets.UTF_8))
                            result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                        }
                    }
                    "write" -> {
                        val value = requireNotNull(call.argument<String>("value"))
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
                        cipher.updateAAD(account.toByteArray(Charsets.UTF_8))
                        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                        val stored = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(encrypted, Base64.NO_WRAP)
                        check(prefs.edit().putString(account, stored).commit())
                        result.success(null)
                    }
                    "delete" -> {
                        check(prefs.edit().remove(account).commit()); result.success(null)
                    }
                }
            } catch (_: Exception) { result.error("unavailable", null, null) }
        }
        MethodChannel(messenger, "marginmind/external_link").setMethodCallHandler { call, result ->
            if (call.method != "open") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val uri = Uri.parse(call.argument<String>("url") ?: "")
                if (uri.scheme !in listOf("https", "http") || uri.host.isNullOrEmpty()) result.success(false)
                else { startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(true) }
            } catch (_: Exception) { result.success(false) }
        }
        MethodChannel(messenger, "marginmind/file_share").setMethodCallHandler { call, result ->
            if (call.method != "share") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val name = requireNotNull(call.argument<String>("name"))
                val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                require(name.isNotEmpty() && name.none { it == '/' || it == '\\' || it.code < 32 } && bytes.isNotEmpty())
                val root = File(cacheDir, "shares").apply { mkdirs() }
                // Receivers may read after the chooser closes. Retain for one day,
                // then prune on the next export; the OS may also reclaim cache.
                root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000 }?.forEach { it.deleteRecursively() }
                val directory = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
                val file = File(directory, name).apply { writeBytes(bytes) }
                val uri = FileProvider.getUriForFile(this, "$packageName.exports", file)
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = if (name.endsWith(".opml")) "text/x-opml" else "text/markdown"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri(name, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(intent, null))
                // Android reports handoff, not whether the receiver saved a file.
                result.success(true)
            } catch (_: Exception) { result.error("share_failed", null, null) }
        }
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("marginmind.credentials", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("marginmind.credentials", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }
}
