package com.morphinealonely.arast_alarm;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import androidx.annotation.NonNull;

import java.util.List;

/** rearms stored alarms after reboot and update because the os drops every registration and past alarms are dropped because ringing late is only noise */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(@NonNull Context context, @NonNull Intent intent) {
        String action = intent.getAction();
        if (action == null) return;
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            return;
        }

        long now = System.currentTimeMillis();
        List<AlarmPayload> stored = AlarmStore.all(context);
        for (AlarmPayload payload : stored) {
            if (payload.triggerAtMillis <= now) {
                AlarmStore.remove(context, payload.id);
                continue;
            }
            AlarmScheduler.schedule(context, payload);
        }
    }
}
