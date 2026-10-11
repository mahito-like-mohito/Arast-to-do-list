package com.morphinealonely.arast_alarm;

import android.content.Context;
import android.os.PowerManager;

/** one partial lock bridging the gap between broadcast and service so a dozing device stays up */
final class AlarmWakeLock {

    private static final String TAG = "arast:alarm";
    private static final long TIMEOUT_MILLIS = 2 * 60 * 1000L;

    private static PowerManager.WakeLock wakeLock;

    private AlarmWakeLock() {}

    static synchronized void acquire(Context context) {
        if (wakeLock == null) {
            PowerManager power =
                    (PowerManager) context.getSystemService(Context.POWER_SERVICE);
            if (power == null) return;
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG);
            wakeLock.setReferenceCounted(false);
        }
        if (!wakeLock.isHeld()) {
            // time the lock so a crash cannot pin the cpu
            wakeLock.acquire(TIMEOUT_MILLIS);
        }
    }

    static synchronized void release() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
    }
}
