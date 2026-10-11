package com.morphinealonely.arast_alarm;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;

/**
 * entry point for a fired alarm and it grabs the wake lock and starts
 * the ringer then returns because a receiver only lives for seconds and
 * when the background start is refused it rings through AlarmFallback
 * instead of going silent
 */
public class AlarmReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(@NonNull Context context, @NonNull Intent intent) {
        if (!AlarmScheduler.ACTION_ALARM.equals(intent.getAction())) return;

        AlarmPayload payload = AlarmPayload.readFrom(intent);
        if (payload == null) return;

        // hold the cpu across the handoff until the service takes over
        AlarmWakeLock.acquire(context);

        AlarmStore.remove(context, payload.id);

        Intent service = new Intent(context, AlarmRingerService.class)
                .setAction(AlarmRingerService.ACTION_RING)
                .putExtra(AlarmPayload.EXTRA, intent.getStringExtra(AlarmPayload.EXTRA));

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service);
            } else {
                context.startService(service);
            }
        } catch (RuntimeException error) {
            // the service path is dead so ring the fallback and release the lock
            AlarmFallback.notify(context, payload);
            AlarmWakeLock.release();
        }
    }
}
