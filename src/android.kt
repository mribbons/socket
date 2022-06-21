// vim: set sw=2:
package __BUNDLE_IDENTIFIER__

/**
 * @TODO
 * @see https://developer.android.com/reference/kotlin/android/webkit/WebView
 */
open class WebView(context: android.content.Context): android.webkit.WebView(context);

/**
 * @TODO
 * @see https://developer.android.com/reference/kotlin/android/webkit/WebViewClient
 */
open class WebViewClient(activity: WebViewActivity) : android.webkit.WebViewClient() {
  private val activity = activity;
  private val TAG = "WebViewClient";

  /**
   * Handles URL loading overrides for "file://" based URI schemes.
   */
  override fun shouldOverrideUrlLoading (
    view: android.webkit.WebView,
    request: android.webkit.WebResourceRequest
  ): Boolean {
    val url = request.getUrl();

    if (url.getScheme() != "file") {
      return false;
    }

    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, url);

    try {
      this.activity.startActivity(intent);
    } catch (err: Error) {
      // @TODO(jwelre): handle this error gracefully
      android.util.Log.e(TAG, err.toString());
      return false;
    }

    return true;
  }
}

/**
 * Main `android.app.Activity` class for the `WebViewClient`.
 * @see https://developer.android.com/reference/kotlin/android/app/Activity
 * @TODO(jwerle): look into `androidx.appcompat.app.AppCompatActivity`
 */
open class WebViewActivity : android.app.Activity() {
  private var client: WebViewClient? = null;
  private var view: WebView? = null;
  private val TAG = "WebViewActivity";

  /**
   * Called when the `WebViewActivity` is starting
   * @see https://developer.android.com/reference/kotlin/android/app/Activity#onCreate(android.os.Bundle)
   */
  override fun onCreate (state: android.os.Bundle?) {
    super.onCreate(state);

    // @TODO(jwerle): `webview` needs to be a defined view that can
    // be referenced by an ID
    val view = WebView(findViewById(android.R.id.webview));
    val client = WebViewClient(this);
    val settings = view.getSettings();

    // @TODO(jwerle): `webview_activity` needs to be defined `res/layout/webview_activity.xml`
    this.setContentView(android.R.layout.webview_activity);

    this.client = client;
    this.view = view;

    settings.setJavaScriptEnabled(true);

    view.setWebViewClient(client);
    view.loadUrl("file:///android_asset/index.html");
  }
}

/**
 * @TODO
 */
final class MainWebViewActivity : WebViewActivity();

/**
 * Core bindings externally implemented in JNI/NDK
 */
private final class Core {
  internal pointer: Long;
  external fun initialize ();
  external fun destroy ()

  protected fun finalize () {
    destroy();
  }
}