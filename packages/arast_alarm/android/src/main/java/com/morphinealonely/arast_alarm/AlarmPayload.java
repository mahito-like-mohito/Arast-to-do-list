package com.morphinealonely.arast_alarm;

import android.content.Intent;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.List;
import java.util.Map;

/** everything one alarm needs decided at schedule time because no dart and no database exist when it fires */
final class AlarmPayload {

    static final String EXTRA = "com.morphinealonely.arast_alarm.PAYLOAD";

    final int id;
    final long triggerAtMillis;
    final String title;
    final String body;

    /** sound to play already resolved to a file or content uri */
    @Nullable
    final String soundUri;

    final boolean playAudio;
    final boolean vibrate;
    final long[] vibrationPattern;

    /** hard ceiling on one ring so a stuck stream ends on its own */
    final long maxDurationMillis;

    AlarmPayload(
            int id,
            long triggerAtMillis,
            String title,
            String body,
            @Nullable String soundUri,
            boolean playAudio,
            boolean vibrate,
            long[] vibrationPattern,
            long maxDurationMillis) {
        this.id = id;
        this.triggerAtMillis = triggerAtMillis;
        this.title = title;
        this.body = body;
        this.soundUri = soundUri;
        this.playAudio = playAudio;
        this.vibrate = vibrate;
        this.vibrationPattern = vibrationPattern;
        this.maxDurationMillis = maxDurationMillis;
    }

    @SuppressWarnings("unchecked")
    static AlarmPayload fromMethodCall(@NonNull Map<String, Object> args) {
        Object patternArg = args.get("vibrationPattern");
        long[] pattern = new long[0];
        if (patternArg instanceof List) {
            List<Object> values = (List<Object>) patternArg;
            pattern = new long[values.size()];
            for (int i = 0; i < values.size(); i++) {
                Object value = values.get(i);
                pattern[i] = value instanceof Number
                        ? Math.max(0L, ((Number) value).longValue())
                        : 0L;
            }
        }
        return new AlarmPayload(
                ((Number) requireArg(args, "id")).intValue(),
                ((Number) requireArg(args, "triggerAtMillis")).longValue(),
                String.valueOf(args.get("title")),
                String.valueOf(args.get("body")),
                (String) args.get("soundUri"),
                Boolean.TRUE.equals(args.get("playAudio")),
                Boolean.TRUE.equals(args.get("vibrate")),
                pattern,
                args.get("maxDurationMillis") instanceof Number
                        ? ((Number) args.get("maxDurationMillis")).longValue()
                        : 120_000L);
    }

    private static Object requireArg(Map<String, Object> args, String key) {
        Object value = args.get(key);
        if (value == null) {
            throw new IllegalArgumentException("Missing alarm argument: " + key);
        }
        return value;
    }

    String toJson() throws JSONException {
        JSONArray pattern = new JSONArray();
        for (long value : vibrationPattern) {
            pattern.put(value);
        }
        return new JSONObject()
                .put("id", id)
                .put("triggerAtMillis", triggerAtMillis)
                .put("title", title)
                .put("body", body)
                .put("soundUri", soundUri == null ? JSONObject.NULL : soundUri)
                .put("playAudio", playAudio)
                .put("vibrate", vibrate)
                .put("vibrationPattern", pattern)
                .put("maxDurationMillis", maxDurationMillis)
                .toString();
    }

    static AlarmPayload fromJson(String json) throws JSONException {
        JSONObject object = new JSONObject(json);
        JSONArray patternArray = object.optJSONArray("vibrationPattern");
        long[] pattern = new long[patternArray == null ? 0 : patternArray.length()];
        for (int i = 0; i < pattern.length; i++) {
            pattern[i] = patternArray.optLong(i, 0L);
        }
        return new AlarmPayload(
                object.getInt("id"),
                object.getLong("triggerAtMillis"),
                object.optString("title", ""),
                object.optString("body", ""),
                object.isNull("soundUri") ? null : object.optString("soundUri"),
                object.optBoolean("playAudio", true),
                object.optBoolean("vibrate", false),
                pattern,
                object.optLong("maxDurationMillis", 120_000L));
    }

    void writeTo(Intent intent) throws JSONException {
        intent.putExtra(EXTRA, toJson());
    }

    @Nullable
    static AlarmPayload readFrom(Intent intent) {
        String json = intent.getStringExtra(EXTRA);
        if (json == null) return null;
        try {
            return fromJson(json);
        } catch (JSONException error) {
            return null;
        }
    }
}
