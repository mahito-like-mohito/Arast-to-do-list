package com.morphinealonely.arast_alarm;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.List;

/**
 * plays one alarm in the foreground the moment it is asked to and the
 * sound uri arrives resolved at schedule time so ringing needs no engine
 * and no database and startForeground runs before any media work because
 * the os kills a service that shows no notification in seconds
 */
public class AlarmRingerService extends Service {

    static final String ACTION_RING = "com.morphinealonely.arast_alarm.RING";
    static final String ACTION_STOP = "com.morphinealonely.arast_alarm.STOP";

    private static final String CHANNEL_ID = "arast_alarm_ringer_v1";
    private static final String CHANNEL_NAME = "Task alarms";
    private static final int NOTIFICATION_ID = 0x4152; // stable, one at a time

    @Nullable
    private MediaPlayer player;
    @Nullable
    private AudioFocusRequest focusRequest;
    @Nullable
    private Vibrator vibrator;
    @Nullable
    private Handler stopHandler;
    @Nullable
    private Runnable stopCallback;

    @Override
    public int onStartCommand(@Nullable Intent intent, int flags, int startId) {
        if (intent == null || ACTION_STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }

        AlarmPayload payload = AlarmPayload.readFrom(intent);
        if (payload == null) {
            stopSelf();
            return START_NOT_STICKY;
        }

        // post the notification first with an explicit type because media setup can block
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                    NOTIFICATION_ID,
                    buildNotification(payload),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        } else {
            startForeground(NOTIFICATION_ID, buildNotification(payload));
        }

        if (payload.vibrate && payload.vibrationPattern.length > 0) {
            vibrate(payload.vibrationPattern);
        }
        if (payload.playAudio) {
            startPlayback(payload);
        }

        // every ring ends at the tone end or the ceiling
        scheduleStop(payload.playAudio ? payload.maxDurationMillis : 4_000L);
        return START_NOT_STICKY;
    }

    private void startPlayback(@NonNull AlarmPayload payload) {
        AudioAttributes attributes = new AudioAttributes.Builder()
                // the alarm stream ignores silent mode and do not disturb
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();

        requestAudioFocus(attributes);

        for (Uri candidate : candidateSounds(payload)) {
            if (play(candidate, attributes)) return;
        }
    }

    /** tries the chosen sound first then the device tones so a lost file still rings */
    @NonNull
    private List<Uri> candidateSounds(@NonNull AlarmPayload payload) {
        List<Uri> candidates = new ArrayList<>(3);
        if (payload.soundUri != null && !payload.soundUri.isEmpty()) {
            try {
                candidates.add(Uri.parse(payload.soundUri));
            } catch (RuntimeException ignored) {
                // a bad uri just falls through to the next sound
            }
        }
        Uri deviceAlarm = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        if (deviceAlarm != null) candidates.add(deviceAlarm);
        Uri notification =
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        if (notification != null) candidates.add(notification);
        return candidates;
    }

    private boolean play(@NonNull Uri uri, @NonNull AudioAttributes attributes) {
        MediaPlayer candidate = new MediaPlayer();
        try {
            candidate.setAudioAttributes(attributes);
            candidate.setDataSource(this, uri);
            // prepare inline because every candidate is local and fast
            candidate.prepare();
            candidate.setOnCompletionListener(mp -> stopSelf());
            candidate.setOnErrorListener((mp, what, extra) -> {
                stopSelf();
                return true;
            });
            candidate.start();
            player = candidate;
            return true;
        } catch (Exception error) {
            candidate.release();
            return false;
        }
    }

    private void requestAudioFocus(@NonNull AudioAttributes attributes) {
        AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (audio == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest =
                    new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                            .setAudioAttributes(attributes)
                            .build();
            audio.requestAudioFocus(focusRequest);
        } else {
            audio.requestAudioFocus(
                    null, AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
        }
    }

    private void abandonAudioFocus() {
        AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (audio == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest != null) audio.abandonAudioFocusRequest(focusRequest);
        } else {
            audio.abandonAudioFocus(null);
        }
        focusRequest = null;
    }

    private void vibrate(@NonNull long[] pattern) {
        Vibrator device = resolveVibrator();
        if (device == null || !device.hasVibrator()) return;
        vibrator = device;

        AudioAttributes attributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                device.vibrate(VibrationEffect.createWaveform(pattern, -1), attributes);
            } else {
                device.vibrate(pattern, -1, attributes);
            }
        } catch (RuntimeException ignored) {
            // a refusing vibrator must not stop the sound
        }
    }

    @Nullable
    private Vibrator resolveVibrator() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager manager =
                    (VibratorManager) getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            return manager == null ? null : manager.getDefaultVibrator();
        }
        return (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
    }

    private Notification buildNotification(@NonNull AlarmPayload payload) {
        createChannel();

        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent content = launch == null ? null : PendingIntent.getActivity(
                this, payload.id, launch, pendingFlags(PendingIntent.FLAG_UPDATE_CURRENT));

        PendingIntent stop = PendingIntent.getService(
                this,
                payload.id,
                new Intent(this, AlarmRingerService.class).setAction(ACTION_STOP),
                pendingFlags(PendingIntent.FLAG_UPDATE_CURRENT));

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);

        builder.setContentTitle(payload.title)
                .setContentText(payload.body)
                .setSmallIcon(getApplicationInfo().icon)
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
        }
        return builder.build();
    }

    /** keeps the channel silent because this service owns sound and buzz itself */
    private void createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null || manager.getNotificationChannel(CHANNEL_ID) != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("Sounds when a task is about to start.");
        channel.setSound(null, null);
        channel.enableVibration(false);
        channel.setShowBadge(false);
        manager.createNotificationChannel(channel);
    }

    private int pendingFlags(int base) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                ? base | PendingIntent.FLAG_IMMUTABLE
                : base;
    }

    private void scheduleStop(long delayMillis) {
        cancelScheduledStop();
        stopHandler = new Handler(Looper.getMainLooper());
        stopCallback = this::stopSelf;
        stopHandler.postDelayed(stopCallback, Math.max(1_000L, delayMillis));
    }

    private void cancelScheduledStop() {
        if (stopHandler != null && stopCallback != null) {
            stopHandler.removeCallbacks(stopCallback);
        }
        stopHandler = null;
        stopCallback = null;
    }

    @Override
    public void onDestroy() {
        cancelScheduledStop();
        if (player != null) {
            try {
                if (player.isPlaying()) player.stop();
            } catch (IllegalStateException ignored) {
            }
            player.release();
            player = null;
        }
        if (vibrator != null) {
            vibrator.cancel();
            vibrator = null;
        }
        abandonAudioFocus();
        // release the lock last because the cpu is only needed while ringing
        AlarmWakeLock.release();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
