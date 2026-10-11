package com.morphinealonely.arast_alarm;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** dart entry to the alarm pipeline and only scheduling crosses here because firing goes straight to the receiver with no engine */
public class ArastAlarmPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {

    private static final String CHANNEL = "com.morphinealonely.arast_alarm/scheduler";

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
    @SuppressWarnings("unchecked")
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (context == null) {
            result.error("no_context", "Plugin is detached from the engine", null);
            return;
        }

        switch (call.method) {
            case "schedule": {
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                if (args == null) {
                    result.error("bad_args", "An alarm payload is required", null);
                    return;
                }
                try {
                    AlarmPayload payload = AlarmPayload.fromMethodCall(args);
                    result.success(AlarmScheduler.schedule(context, payload));
                } catch (IllegalArgumentException error) {
                    result.error("bad_args", error.getMessage(), null);
                }
                break;
            }
            case "cancel": {
                Integer id = call.argument("id");
                if (id == null) {
                    result.error("bad_args", "An alarm id is required", null);
                    return;
                }
                AlarmScheduler.cancel(context, id);
                result.success(null);
                break;
            }
            case "canScheduleExactAlarms":
                result.success(AlarmScheduler.canScheduleExact(context));
                break;
            case "requestExactAlarmPermission":
                result.success(openExactAlarmSettings());
                break;
            default:
                result.notImplemented();
        }
    }

    /** opens the settings screen that grants exact alarms on android 12 only */
    private boolean openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false;
        try {
            Intent intent = new Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:" + context.getPackageName()))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            return true;
        } catch (RuntimeException error) {
            // some oem builds lack the settings screen
            return false;
        }
    }
}
