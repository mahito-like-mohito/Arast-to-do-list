package com.morphinealonely.arast_alarm;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.json.JSONException;

/**
 * arms alarms with setAlarmClock because it is the only call the os
 * treats as a user visible alarm and it survives doze and standby and
 * shows the alarm icon so an armed alarm stays visible and delivery goes
 * to a receiver because exact broadcasts run at once unlike jobs
 */
final class AlarmScheduler {

    static final String ACTION_ALARM = "com.morphinealonely.arast_alarm.ALARM";

    private AlarmScheduler() {}

    /** arms the payload and returns false when the os refused it */
    static boolean schedule(@NonNull Context context, @NonNull AlarmPayload payload) {
        AlarmManager manager =
                (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null) return false;

        PendingIntent alarmIntent = broadcastIntent(context, payload);
        if (alarmIntent == null) return false;

        try {
            if (canScheduleExact(manager)) {
                manager.setAlarmClock(
                        new AlarmManager.AlarmClockInfo(
                                payload.triggerAtMillis, showIntent(context, payload.id)),
                        alarmIntent);
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, payload.triggerAtMillis, alarmIntent);
            } else {
                manager.setExact(
                        AlarmManager.RTC_WAKEUP, payload.triggerAtMillis, alarmIntent);
            }
        } catch (SecurityException error) {
            // exact alarms can vanish between the check and the call
            return false;
        }

        AlarmStore.put(context, payload);
        return true;
    }

    static void cancel(@NonNull Context context, int id) {
        AlarmManager manager =
                (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        Intent intent = new Intent(context, AlarmReceiver.class).setAction(ACTION_ALARM);
        PendingIntent pending = PendingIntent.getBroadcast(
                context, id, intent, flags(PendingIntent.FLAG_NO_CREATE));
        if (pending != null) {
            if (manager != null) manager.cancel(pending);
            pending.cancel();
        }
        AlarmStore.remove(context, id);
    }

    static boolean canScheduleExact(@NonNull AlarmManager manager) {
        // below android 12 exact alarms need no grant
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S
                || manager.canScheduleExactAlarms();
    }

    static boolean canScheduleExact(@NonNull Context context) {
        AlarmManager manager =
                (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        return manager != null && canScheduleExact(manager);
    }

    @Nullable
    private static PendingIntent broadcastIntent(
            @NonNull Context context, @NonNull AlarmPayload payload) {
        Intent intent = new Intent(context, AlarmReceiver.class).setAction(ACTION_ALARM);
        try {
            payload.writeTo(intent);
        } catch (JSONException error) {
            return null;
        }
        // reuse the alarm id so rescheduling replaces instead of stacking
        return PendingIntent.getBroadcast(
                context, payload.id, intent, flags(PendingIntent.FLAG_UPDATE_CURRENT));
    }

    /** opens the task list when the status bar alarm entry is tapped */
    private static PendingIntent showIntent(@NonNull Context context, int id) {
        Intent launch = context.getPackageManager()
                .getLaunchIntentForPackage(context.getPackageName());
        if (launch == null) launch = new Intent();
        return PendingIntent.getActivity(
                context, id, launch, flags(PendingIntent.FLAG_UPDATE_CURRENT));
    }

    private static int flags(int base) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                ? base | PendingIntent.FLAG_IMMUTABLE
                : base;
    }
}
