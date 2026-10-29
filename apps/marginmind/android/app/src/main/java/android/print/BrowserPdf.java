package android.print;

import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.webkit.WebView;
import java.io.File;

/** Adapts WebView's paginated print output to an app-private PDF.
 * The SDK's callback constructors have package visibility, so the callback
 * adapter lives beside them. No reflection or browser cookie export is used.
 */
public final class BrowserPdf {
  public interface Completion { void complete(byte[] bytes); }
  public static Runnable start(WebView web, File target, Completion completion) {
    final PrintDocumentAdapter adapter = web.createPrintDocumentAdapter("MarginMind");
    final CancellationSignal signal = new CancellationSignal();
    final Handler handler = new Handler(Looper.getMainLooper());
    final Runnable[] timeout = new Runnable[1];
    final class Job {
      boolean finished = false;
      ParcelFileDescriptor output;
      void finish(boolean success) {
        if (Looper.myLooper() != Looper.getMainLooper()) { handler.post(() -> finish(success)); return; }
        if (finished) return;
        finished = true;
        handler.removeCallbacks(timeout[0]);
        byte[] bytes = null;
        try {
          if (output != null) output.close();
          if (success && target.length() > 0 && target.length() <= 128L * 1024 * 1024) {
            bytes = new byte[(int) target.length()];
            try (java.io.DataInputStream input = new java.io.DataInputStream(new java.io.FileInputStream(target))) {
              input.readFully(bytes);
            }
          }
        } catch (Exception ignored) { bytes = null; }
        finally {
          try { adapter.onFinish(); } catch (Exception ignored) { }
          target.delete();
        }
        completion.complete(bytes);
      }
      void cancel() { signal.cancel(); finish(false); }
    }
    final Job job = new Job();
    timeout[0] = job::cancel;
    handler.postDelayed(timeout[0], 40000);
    // Keep one terminal callback, including layout failure and cancellation.
    try {
      adapter.onStart();
      PrintAttributes attributes = new PrintAttributes.Builder()
        .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
        .setResolution(new PrintAttributes.Resolution("pdf", "PDF", 300, 300))
        .setMinMargins(PrintAttributes.Margins.NO_MARGINS).build();
      adapter.onLayout(null, attributes, signal, new PrintDocumentAdapter.LayoutResultCallback() {
        @Override public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
          if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post(() -> onLayoutFinished(info, changed)); return;
          }
          if (job.finished) return;
          if (info.getPageCount() > 2000) { job.finish(false); return; }
          try {
            job.output = ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_CREATE |
              ParcelFileDescriptor.MODE_TRUNCATE | ParcelFileDescriptor.MODE_READ_WRITE);
            adapter.onWrite(new PageRange[]{PageRange.ALL_PAGES}, job.output, signal,
              new PrintDocumentAdapter.WriteResultCallback() {
                @Override public void onWriteFinished(PageRange[] pages) { job.finish(true); }
                @Override public void onWriteFailed(CharSequence error) { job.finish(false); }
                @Override public void onWriteCancelled() { job.finish(false); }
              });
          } catch (Exception error) { job.finish(false); }
        }
        @Override public void onLayoutFailed(CharSequence error) { job.finish(false); }
        @Override public void onLayoutCancelled() { job.finish(false); }
      }, new Bundle());
    } catch (Exception error) { job.finish(false); }
    return job::cancel;
  }
}
