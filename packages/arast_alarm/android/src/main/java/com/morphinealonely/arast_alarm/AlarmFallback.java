package com.morphinealonely.arast_alarm;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

/**
 * last resort fire path for when the ringer service cannot start and
 * it posts a loud notification that the system itself plays so no
 * foreground service and no wake lock are needed and sounding alarms
 * get one channel per sound because a channel sound is frozen at creation
 */
final class AlarmFallback {

    private static final String BUZZ_CHANNEL_ID = "arast_alarm_fallback_buzz_v1";
    private static final String BUZZ_CHANNEL_NAME = "Task alarm buzz";
    private static final String SOUND_CHANNEL_PREFIX = "arast_alarm_fallback_sound_";
    private static final String SOUND_CHANNEL_NAME = "Task alarm sound";

    // share the ringer id so only one alarm shows at a time
    private static final int NOTIFICATION_ID = 0x4152;

    private AlarmFallback() {}

    static void notify(@NonNull Context context, @NonNull AlarmPayload payload) {
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;

        Uri sound = systemSound(payload);
        String channelId;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            channelId = ensureChannel(manager, payload, sound);
            if (channelId == null) return;
        } else {
            channelId = null;
        }

        if (payload.vibrate && payload.vibrationPattern.length > 0) {
            buzz(context, payload.vibrationPattern);
        }
        manager.notify(NOTIFICATION_ID, buildNotification(context, payload, channelId, sound));
    }

    @Nullable
    private static String ensureChannel(
            @NonNull NotificationManager manager,
            @NonNull AlarmPayload payload,
            @Nullable Uri sound) {
        if (sound != null) {
            String channelId =
                    SOUND_CHANNEL_PREFIX + Integer.toHexString(sound.toString().hashCode());
            if (manager.getNotificationChannel(channelId) == null) {
                NotificationChannel channel = new NotificationChannel(
                        channelId, SOUND_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH);
                channel.setDescription("Sounds when a task is about to start.");
                channel.setSound(sound, alarmAttributes());
                channel.enableVibration(false);
                channel.setShowBadge(false);
                manager.createNotificationChannel(channel);
            }
            return channelId;
        }

        if (manager.getNotificationChannel(BUZZ_CHANNEL_ID) == null) {
            NotificationChannel channel = new NotificationChannel(
                    BUZZ_CHANNEL_ID, BUZZ_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("Buzzes when a task is about to start.");
            channel.setSound(null, null);
            channel.enableVibration(true);
            channel.setVibrationPattern(new long[]{0, 400, 200, 400});
            channel.setShowBadge(false);
            manager.createNotificationChannel(channel);
        }
        return BUZZ_CHANNEL_ID;
    }

    /** picks a sound the system process can open and falls back to the device alarm tone */
    @Nullable
    private static Uri systemSound(@NonNull AlarmPayload payload) {
        if (!payload.playAudio) return null;
        Uri candidate = null;
        if (payload.soundUri != null && !payload.soundUri.isEmpty()) {
            try {
                candidate = Uri.parse(payload.soundUri);
            } catch (RuntimeException ignored) {
                // a bad uri just falls through to the next sound
            }
        }
        if (candidate != null && isSystemPlayable(candidate)) return candidate;
        Uri deviceAlarm = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        if (deviceAlarm != null) return deviceAlarm;
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
    }

    private static boolean isSystemPlayable(@NonNull Uri uri) {
        String scheme = uri.getScheme();
        if (ContentResolver.SCHEME_ANDROID_RESOURCE.equals(scheme)) return true;
        if (ContentResolver.SCHEME_CONTENT.equals(scheme)) {
            String authority = uri.getAuthority();
            return authority != null && authority.startsWith("media");
        }
        return false;
    }

    private static AudioAttributes alarmAttributes() {
        return new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
    }

    private static void buzz(@NonNull Context context, @NonNull long[] pattern) {
        Vibrator device = resolveVibrator(context);
        if (device == null || !device.hasVibrator()) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                device.vibrate(VibrationEffect.createWaveform(pattern, -1), alarmAttributes());
            } else {
                device.vibrate(pattern, -1);
            }
        } catch (RuntimeException ignored) {
            // a refusing vibrator must not stop the sound
        }
    }

    @Nullable
    private static Vibrator resolveVibrator(@NonNull Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager manager =
                    (VibratorManager) context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            return manager == null ? null : manager.getDefaultVibrator();
        }
        return (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
    }

    private static Notification buildNotification(
            @NonNull Context context,
            @NonNull AlarmPayload payload,
            @Nullable String channelId,
            @Nullable Uri legacySound) {
        Intent launch =
                context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent content = launch == null ? null : PendingIntent.getActivity(
                context, payload.id, launch, pendingFlags(PendingIntent.FLAG_UPDATE_CURRENT));

        PendingIntent stop = PendingIntent.getService(
                context,
                payload.id,
                new Intent(context, AlarmRingerService.class)
                        .setAction(AlarmRingerService.ACTION_STOP),
                pendingFlags(PendingIntent.FLAG_UPDATE_CURRENT));

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(context, channelId)
                : new Notification.Builder(context);

        builder.setContentTitle(payload.title)
                .setContentText(payload.body)
                .setSmallIcon(context.getApplicationInfo().icon)
                .setAutoCancel(false)
                .setOngoing(true)
                .setWhen(payload.triggerAtMillis)
                .addAction(new Notification.Action.Builder(
                        null, "Stop", stop).build());

        if (content != null) {
            builder.setContentIntent(content);
            // show over the lock screen like an alarm should
            builder.setFullScreenIntent(content, true);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_ALARM);
            builder.setVisibility(Notification.VISIBILITY_PUBLIC);
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder.setPriority(Notification.PRIORITY_MAX);
            if (legacySound != null) {
                builder.setSound(legacySound, android.media.AudioManager.STREAM_ALARM);
            }
            if (payload.vibrate && payload.vibrationPattern.length > 0) {
                builder.setVibrate(payload.vibrationPattern);
            }
        }
        return builder.build();
    }

    private static int pendingFlags(int base) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                ? base | PendingIntent.FLAG_IMMUTABLE
                : base;
    }
}
