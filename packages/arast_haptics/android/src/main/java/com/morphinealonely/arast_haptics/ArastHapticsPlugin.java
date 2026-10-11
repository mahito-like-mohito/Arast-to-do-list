package com.morphinealonely.arast_haptics;

import android.content.Context;
import android.media.AudioAttributes;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;

import androidx.annotation.NonNull;

import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * thin bridge to the vibrator for the in app buzz and the settings
 * preview and closed app alarms vibrate from arast_alarm instead and
 * the alarm usage survives do not disturb with no permission
 */
public class ArastHapticsPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {

    private static final String CHANNEL = "com.morphinealonely.arast_haptics/vibrate";

    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        context = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "vibrate": {
                List<Integer> pattern = call.argument("pattern");
                if (pattern == null || pattern.isEmpty()) {
                    result.error("bad_args", "A vibration pattern is required", null);
                    return;
                }
                result.success(vibrate(toTimings(pattern)));
                break;
            }
            default:
                result.notImplemented();
        }
    }

    /** picks the vibrator api for the running android version */
    private Vibrator resolveVibrator() {
        if (context == null) return null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager manager =
                    (VibratorManager) context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            return manager == null ? null : manager.getDefaultVibrator();
        }
        return (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
    }

    /** plays the pattern once and returns false when the device refused it */
    private boolean vibrate(long[] timings) {
        Vibrator vibrator = resolveVibrator();
        if (vibrator == null || !vibrator.hasVibrator()) return false;

        AudioAttributes attributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(timings, -1), attributes);
            } else {
                vibrator.vibrate(timings, -1, attributes);
            }
            return true;
        } catch (RuntimeException error) {
            // a refused effect must not kill the alarm job
            return false;
        }
    }

    /** converts the dart pattern to the long array the platform wants */
    private static long[] toTimings(List<Integer> pattern) {
        long[] timings = new long[pattern.size()];
        for (int i = 0; i < pattern.size(); i++) {
            Integer value = pattern.get(i);
            timings[i] = value == null || value < 0 ? 0L : value.longValue();
        }
        return timings;
    }
}
