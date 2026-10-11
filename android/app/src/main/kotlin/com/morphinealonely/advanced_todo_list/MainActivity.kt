package com.morphinealonely.advanced_todo_list

import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * hosts flutter plus the ringtone catalogue and the secure screen
 * channels and FragmentActivity hosts the biometric prompt
 */
class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "com.morphinealonely.advanced_todo_list/ringtones"
        const val DEVICE_CHANNEL = "com.morphinealonely.advanced_todo_list/device"

        /** how often a preview is polled for finishing */
        const val COMPLETION_POLL_MS = 300L

        /** grace after play before silence counts as finished because playback starts late */
        const val PLAYBACK_START_GRACE_MS = 1500L
    }

    private var activeRingtone: Ringtone? = null
    private var activeUri: String? = null
    private var startedPlaying = false
    private var playRequestedAt = 0L
    private var ringtoneChannel: MethodChannel? = null

    /**
     * polls isPlaying because ringtone has no finish callback before api
     * 33 and only while a preview plays
     */
    private val mainHandler = Handler(Looper.getMainLooper())
    private val completionWatcher = object : Runnable {
        override fun run() {
            val ringtone = activeRingtone ?: return
            if (ringtone.isPlaying) {
                startedPlaying = true
                mainHandler.postDelayed(this, COMPLETION_POLL_MS)
                return
            }
            // not playing yet means still starting or broken so wait out the grace
            if (!startedPlaying &&
                SystemClock.uptimeMillis() - playRequestedAt < PLAYBACK_START_GRACE_MS
            ) {
                mainHandler.postDelayed(this, COMPLETION_POLL_MS)
                return
            }
            val finishedUri = activeUri
            activeRingtone = null
            activeUri = null
            startedPlaying = false
            if (finishedUri != null) {
                ringtoneChannel?.invokeMethod("onPreviewComplete", finishedUri)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        ringtoneChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> result.success(listRingtones())
                "play" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrEmpty()) {
                        result.error("bad_args", "Missing ringtone uri", null)
                    } else {
                        playRingtone(uri)
                        result.success(null)
                    }
                }
                "stop" -> {
                    stopRingtone()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // secure screen blanks the app in recents and blocks screenshots
                "setSecureScreen" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** lists device alarm sounds and falls back to ringtones when empty */
    private fun listRingtones(): List<Map<String, String>> {
        val ringtones = queryRingtones(RingtoneManager.TYPE_ALARM)
        if (ringtones.isNotEmpty()) return ringtones
        return queryRingtones(RingtoneManager.TYPE_RINGTONE)
    }

    private fun queryRingtones(type: Int): List<Map<String, String>> {
        // use the context query because the activity one caches a cursor that crashes on return
        val manager = RingtoneManager(applicationContext).apply { setType(type) }
        val results = mutableListOf<Map<String, String>>()
        // the cursor here must close or its window leaks
        val cursor = try {
            manager.cursor
        } catch (error: Exception) {
            // a refusing provider must not crash the app
            Log.w(TAG, "Ringtone query failed for type $type", error)
            null
        } ?: return results

        cursor.use {
            while (it.moveToNext()) {
                val title = it.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri = manager.getRingtoneUri(it.position)
                if (title != null && uri != null) {
                    results.add(mapOf("title" to title, "uri" to uri.toString()))
                }
            }
        }
        return results
    }

    private fun playRingtone(uriString: String) {
        stopRingtone()
        val ringtone = RingtoneManager.getRingtone(this, Uri.parse(uriString))
        activeRingtone = ringtone
        activeUri = if (ringtone == null) null else uriString
        ringtone?.play()
        if (ringtone != null) {
            startedPlaying = false
            playRequestedAt = SystemClock.uptimeMillis()
            mainHandler.postDelayed(completionWatcher, COMPLETION_POLL_MS)
        }
    }

    private fun stopRingtone() {
        mainHandler.removeCallbacks(completionWatcher)
        activeRingtone?.takeIf { it.isPlaying }?.stop()
        activeRingtone = null
        activeUri = null
        startedPlaying = false
    }

    override fun onDestroy() {
        stopRingtone()
        ringtoneChannel?.setMethodCallHandler(null)
        ringtoneChannel = null
        super.onDestroy()
    }
}
