package com.example.nontontv_flutter

import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import com.example.nontontv_flutter.player.NontonTvPlayerViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "nontontv/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "nontontv/native_player",
            NontonTvPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val width = call.argument<Int>("width") ?: 16
                    val height = call.argument<Int>("height") ?: 9
                    val params = PictureInPictureParams.Builder()
                        .setAspectRatio(Rational(width, height))
                        .build()
                    result.success(enterPictureInPictureMode(params))
                }

                "setAutoStartOnBoot" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val component = ComponentName(this, BootReceiver::class.java)
                    packageManager.setComponentEnabledSetting(
                        component,
                        if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP
                    )
                    result.success(null)
                }

                "getApplicationFilesDirectory" -> {
                    result.success(filesDir.absolutePath)
                }

                "getAutoStartOnBoot" -> {
                    val component = ComponentName(this, BootReceiver::class.java)
                    val state = packageManager.getComponentEnabledSetting(component)
                    result.success(state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
                }

                "getPlayerCapabilities" -> {
                    val ffmpegAvailable = try {
                        val clazz = Class.forName("androidx.media3.decoder.ffmpeg.FfmpegLibrary")
                        val method = clazz.getMethod("isAvailable")
                        method.invoke(null) as? Boolean ?: false
                    } catch (_: Throwable) {
                        false
                    }
                    result.success(
                        mapOf(
                            "media3Version" to "1.11.1",
                            "ffmpegAvailable" to ffmpegAvailable
                        )
                    )
                }

                else -> result.notImplemented()
            }
        }
    }
}
