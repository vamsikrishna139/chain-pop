package com.adbkv.chainpop

import android.content.Context
import com.google.android.gms.games.PlayGames
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Exposes the IAB TCF keys the UMP SDK writes to the default
        // SharedPreferences, so analytics consent can follow the same GDPR
        // choice the player made for ads. Read-only.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.adbkv.chainpop/tcf")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val prefs = getSharedPreferences(
                    "${packageName}_preferences",
                    Context.MODE_PRIVATE,
                )
                val all = prefs.all
                result.success(
                    mapOf(
                        "gdprApplies" to (all["IABTCF_gdprApplies"] as? Int),
                        "purposeConsents" to (all["IABTCF_PurposeConsents"] as? String),
                    ),
                )
            }

        // Queued Play Games achievement writes. The games_services plugin only
        // exposes the *Immediate variants, which need a live connection and
        // fail with 26502 CLIENT_RECONNECT_REQUIRED whenever the games client
        // has gone stale (constantly, on-device). The plain variants hand the
        // update to Play Games, which persists and delivers it itself.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.adbkv.chainpop/achievements")
            .setMethodCallHandler { call, result ->
                val id = call.argument<String>("id")
                if (id.isNullOrEmpty()) {
                    result.error("bad_args", "achievement id missing", null)
                    return@setMethodCallHandler
                }
                try {
                    val client = PlayGames.getAchievementsClient(this)
                    when (call.method) {
                        "setSteps" -> {
                            val steps = call.argument<Int>("steps") ?: 0
                            if (steps > 0) client.setSteps(id, steps)
                        }
                        "unlock" -> client.unlock(id)
                        else -> {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("achievement_queue_failed", e.message, null)
                }
            }
    }
}
