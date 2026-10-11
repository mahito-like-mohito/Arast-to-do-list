package com.morphinealonely.arast_alarm;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;

import org.json.JSONException;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** on disk record of armed alarms so reboot and update can rearm them with no ui and it uses device storage so it reads before first unlock */
final class AlarmStore {

    private static final String PREFS = "com.morphinealonely.arast_alarm.store";
    private static final String KEY_IDS = "alarm_ids";
    private static final String KEY_PREFIX = "alarm_";

    private AlarmStore() {}

    private static SharedPreferences prefs(Context context) {
        Context storageContext = context;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            Context protectedContext = context.createDeviceProtectedStorageContext();
            if (protectedContext != null) storageContext = protectedContext;
        }
        return storageContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static void put(@NonNull Context context, @NonNull AlarmPayload payload) {
        try {
            SharedPreferences preferences = prefs(context);
            Set<String> ids = new HashSet<>(
                    preferences.getStringSet(KEY_IDS, new HashSet<>()));
            ids.add(String.valueOf(payload.id));
            preferences.edit()
                    .putStringSet(KEY_IDS, ids)
                    .putString(KEY_PREFIX + payload.id, payload.toJson())
                    .apply();
        } catch (JSONException error) {
            // a payload that will not serialise skips the reboot store only
        }
    }

    static void remove(@NonNull Context context, int id) {
        SharedPreferences preferences = prefs(context);
        Set<String> ids = new HashSet<>(
                preferences.getStringSet(KEY_IDS, new HashSet<>()));
        ids.remove(String.valueOf(id));
        preferences.edit()
                .putStringSet(KEY_IDS, ids)
                .remove(KEY_PREFIX + id)
                .apply();
    }

    // read back every stored payload and skip the broken ones
    @NonNull
    static List<AlarmPayload> all(@NonNull Context context) {
        SharedPreferences preferences = prefs(context);
        Set<String> ids = preferences.getStringSet(KEY_IDS, new HashSet<>());
        List<AlarmPayload> payloads = new ArrayList<>();
        for (String id : ids) {
            String json = preferences.getString(KEY_PREFIX + id, null);
            if (json == null) continue;
            try {
                payloads.add(AlarmPayload.fromJson(json));
            } catch (JSONException error) {
                // skip the broken entry and keep the rest
            }
        }
        return payloads;
    }
}
