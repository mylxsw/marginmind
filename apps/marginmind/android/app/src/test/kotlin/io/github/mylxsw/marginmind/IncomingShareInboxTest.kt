package io.github.mylxsw.marginmind

import android.content.ClipData
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
class IncomingShareInboxTest {
    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) { callback?.reply(null) }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        fun invoke(method: String, arguments: Any? = null): Any? {
            val codec = StandardMethodCodec.INSTANCE
            val buffer = codec.encodeMethodCall(MethodCall(method, arguments)).apply { flip() }
            val done = CountDownLatch(1)
            var answer: Any? = null
            handlers.getValue("marginmind/incoming_share").onMessage(buffer) { response ->
                response?.flip()
                answer = codec.decodeEnvelope(requireNotNull(response))
                done.countDown()
            }
            for (attempt in 0 until 500) {
                shadowOf(Looper.getMainLooper()).idle()
                if (done.await(10, TimeUnit.MILLISECONDS)) return answer
            }
            fail("Native inbox did not reply")
            return null
        }
    }

    @Test fun coldAndWarmInboxRetainsUntilAcknowledgement() {
        val messenger = Messenger()
        val inbox = IncomingShareInbox(RuntimeEnvironment.getApplication(), messenger)
        try {
            inbox.capture(Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "文章 https://example.com/read。"))
            val first = messenger.invoke("pending") as List<*>
            assertEquals("https://example.com/read", (first.single() as Map<*, *>)["url"])
            assertEquals(first, messenger.invoke("pending"))
            val id = (first.single() as Map<*, *>)["id"] as String
            messenger.invoke("complete", mapOf("id" to id))
            messenger.invoke("complete", mapOf("id" to id))
            assertTrue((messenger.invoke("pending") as List<*>).isEmpty())
            inbox.capture(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "file:///private/a.pdf"))
            assertEquals("unsupported", ((messenger.invoke("pending") as List<*>).single() as Map<*, *>)["error"])
        } finally { inbox.close() }
    }

    @Test fun copiesContentUrisFromClipDataAndRejectsPrivateFilePaths() {
        val app = RuntimeEnvironment.getApplication()
        val original = File(app.cacheDir, "source.md").apply { writeText("# Shared document") }
        val provider = object : ContentProvider() {
            override fun onCreate() = true
            override fun getType(uri: Uri) = "text/markdown"
            override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, order: String?): Cursor =
                MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME)).apply { addRow(arrayOf("../../资料.md")) }
            override fun openFile(uri: Uri, mode: String) = ParcelFileDescriptor.open(original, ParcelFileDescriptor.MODE_READ_ONLY)
            override fun insert(uri: Uri, values: ContentValues?): Uri? = null
            override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = 0
            override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
        }
        provider.attachInfo(app, android.content.pm.ProviderInfo().apply { authority = "foliarc-test" })
        ShadowContentResolver.registerProviderInternal("foliarc-test", provider)
        val messenger = Messenger()
        val inbox = IncomingShareInbox(app, messenger)
        try {
            inbox.capture(Intent(Intent.ACTION_SEND).setType("text/markdown").apply {
                clipData = ClipData.newRawUri("document", Uri.parse("content://foliarc-test/book"))
            })
            val batch = (messenger.invoke("pending") as List<*>).single() as Map<*, *>
            val file = (batch["files"] as List<*>).single() as Map<*, *>
            assertFalse((file["name"] as String).contains('/'))
            assertEquals("# Shared document", File(file["path"] as String).readText())
            original.delete()
            assertTrue(File(file["path"] as String).exists())
            messenger.invoke("complete", mapOf("id" to batch["id"]))
            assertFalse(File(file["path"] as String).exists())
            inbox.capture(Intent(Intent.ACTION_VIEW, Uri.parse("file:///private/a.pdf")))
            assertEquals("unsupported", ((messenger.invoke("pending") as List<*>).single() as Map<*, *>)["error"])
        } finally { inbox.close() }
    }

    @Test fun enforcesFormatCountAndUrlPolicy() {
        assertEquals(256L * 1024 * 1024, IncomingSharePolicy.limit("a.PDF"))
        assertEquals(500L * 1024 * 1024, IncomingSharePolicy.limit("a.mobi"))
        assertEquals(64L * 1024 * 1024, IncomingSharePolicy.limit("a.epub"))
        assertThrows(IllegalArgumentException::class.java) { IncomingSharePolicy.limit("a.exe") }
        assertNull(IncomingSharePolicy.url("https://user:password@example.com"))
        assertNull(IncomingSharePolicy.url("javascript:alert(1)"))
        assertEquals("https://example.com/a", IncomingSharePolicy.url("链接 https://example.com/a。"))
        assertEquals("https://example.com/Foo_(bar)", IncomingSharePolicy.url("https://example.com/Foo_(bar)"))
        val messenger = Messenger()
        val inbox = IncomingShareInbox(RuntimeEnvironment.getApplication(), messenger)
        try {
            inbox.capture(Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((0..20).map { Uri.parse("content://test/$it.pdf") }))
            })
            assertEquals("limit", ((messenger.invoke("pending") as List<*>).single() as Map<*, *>)["error"])
        } finally { inbox.close() }
    }
}
