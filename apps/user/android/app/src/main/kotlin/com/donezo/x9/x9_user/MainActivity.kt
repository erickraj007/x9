package com.donezo.x9.x9_user

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// FlutterFragmentActivity (not FlutterActivity) is required for fingerprint / face unlock (local_auth).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // v6.13: list the UPI apps installed on this phone and open one of them with a upi:// payment link.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "x9/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "apps" -> {
                    try {
                        val uri = call.argument<String>("uri") ?: "upi://pay"
                        val pm = packageManager
                        val list = pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse(uri)), 0)
                        val out = list.map {
                            val icon = try {
                                val d = it.loadIcon(pm)
                                val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                                val c = Canvas(bmp)
                                d.setBounds(0, 0, 96, 96)
                                d.draw(c)
                                val bos = ByteArrayOutputStream()
                                bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
                                bos.toByteArray()
                            } catch (e: Exception) {
                                null
                            }
                            mapOf("name" to it.loadLabel(pm).toString(), "package" to it.activityInfo.packageName, "icon" to icon)
                        }.distinctBy { it["package"] }
                        result.success(out)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any?>>())
                    }
                }
                "launch" -> {
                    try {
                        val pkg = call.argument<String>("package")
                        val uri = call.argument<String>("uri")
                        val i = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                        if (pkg != null) i.setPackage(pkg)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
