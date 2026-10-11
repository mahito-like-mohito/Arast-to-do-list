# App Critique and Feature Enhancement

Product and engineering review of the to-do list application. Findings were
produced by a multi-perspective review (specification compliance, runtime
correctness, design constraints, Android platform configuration), and every
finding was adversarially re-verified against the code before being
accepted; claims that did not survive verification were discarded. Items
marked FIXED are already implemented on this branch, with tests where the
behavior is testable.

## 1. Critical Flaw Analysis

### 1.1 Sticky headers pinned underneath the transparent top bar (major, FIXED)

The dashboard uses `extendBodyBehindAppBar` with a transparent app bar so
the background image can span the whole screen. Pinned slivers pin at the
scroll viewport's leading edge, and the viewport's only top clearance was a
scrollable spacer, so after the first scroll every pinned header slid
underneath the status bar and the app bar's title and icons were drawn on
top of it.

Fix (`home_screen.dart`): the clearance moved out of the scrollable content
into non-scrolling padding around the `CustomScrollView`. The background
still covers the full screen (it sits outside the padding); the viewport's
leading edge, and with it every pinned header, now sits below the app bar.

### 1.2 Sticky headers accumulated instead of replacing each other (FIXED)

Three sibling `pinned: true` headers stack: after scrolling into the Night
block, Morning and Noon remained pinned above it, consuming about 300
logical pixels. Each block's header and list are now wrapped in a
`SliverMainAxisGroup`, which scopes the pin to its own section: exactly one
header is pinned at a time and the next block's header pushes it away.

### 1.3 Circular controls lost drags to their scrollable parents (major, FIXED)

The nested time dials, the delay ring and the RGB wheel handled gestures
with plain pan callbacks while sitting inside vertical scrollables (the
edit form, the appearance bottom sheet). In Flutter's gesture arena a
vertical drag recognizer accepts at touch slop while a pan recognizer needs
twice that, so any drag steeper than about 30 degrees scrolled the page or
dragged the sheet instead of turning the control. Worse, the dial applied a
value on pointer contact before the arena resolved, so a scroll that merely
started on a dial silently rewrote the selected time; and on the color
wheel a lost gesture skipped the commit callback, so a previewed theme
color was never persisted.

Fix (`eager_pan_recognizer.dart`, used by all three controls): the control
claims the arena the moment a pointer lands on it, making every touch that
starts on a dial belong to the dial. The AM / PM toggle was hoisted above
the gesture detector in the stack so its taps are absorbed before the
eager recognizer sees them (a regression the widget test caught). The
color wheel now also commits on gesture cancel, so no previewed color can
be lost.

### 1.4 Alarm notification channel froze the sound policy of the first alarm (major, FIXED)

Android fixes a notification channel's sound configuration at first
creation. All alarms previously posted to one channel whose `playSound`
flag depended on the task, so whichever task fired first permanently
decided whether every later alarm on that channel made sound.

Fix (`alarm_service.dart`): sounding and silent behaviors live on separate,
pre-created channels; system-ringtone tasks post on a per-sound channel
whose sound is the ringtone itself, played by the OS notification service,
which keeps ringing even if the app process is reclaimed.

### 1.5 Custom alarm audio could be cut off on a sleeping device (FIXED)

The background alarm job previously returned as soon as playback started;
with the screen off, the CPU could suspend or the cached process be
reclaimed moments later, truncating the sound: precisely the minimized
scenario the alarm exists for. The player now routes through the alarm
audio stream with `stayAwake` (holding a partial wake lock during
playback), is retained in a top-level reference, and the job awaits
playback completion with a bounded timeout before finishing.

### 1.6 High-resolution background images decoded at full size (FIXED)

A user-picked photo was decoded at its native resolution: a modern phone
camera image can cost several hundred megabytes of texture memory. The
background image is now decoded at the physical screen width
(`cacheWidth`), and live color-wheel preview notifications are throttled to
one per frame interval so a drag does not rebuild the app faster than the
display refreshes.

### 1.7 Time-overlap edge cases were silent (FIXED)

An end time at or before the start time was silently interpreted as
crossing midnight, and nothing warned when a new task overlapped an
existing one. The editor now shows an explicit "ends after midnight, on
the following day" notice for the first case and a live overlap warning
naming the conflicting task for the second. Overlaps stay allowed:
deliberate parallel tasks are legitimate, so the warning informs rather
than blocks.

### 1.8 Smaller confirmed defects (all FIXED)

- Ringtone preview could call `setState` after the sheet was disposed
  (platform-channel latency); now guarded with `mounted` checks.
- The native ringtone query leaked a content-provider cursor per call;
  now closed with Kotlin's `use` block.
- The appearance sheet was opened through a context belonging to the
  closing drawer; it now uses the navigator's own context.

### 1.9 Verified non-issues

Three review claims were refuted during verification and deliberately not
"fixed": content URIs do play through the Android media player path;
the star badge geometry does straddle the header frame corner as
documented; and the remaining template comments live only in generated
platform files.

## 2. Competitive Feature Proposals

1. **On-device schedule prediction** (IMPLEMENTED): the app learns from the
   user's own history which time blocks they reliably complete and how long
   their tasks typically run, then proposes conflict-free slots when
   creating a task. Fully local, explainable and deterministic; each
   suggestion carries its reasoning ("82 percent of your Peaceful Rest
   tasks get done"). Surfaces as three tappable chips in the editor, so
   the minimal interface gains no new screens.

2. **Time-management insights** (IMPLEMENTED): a dashboard computing
   completion rate, a seven-day planned-versus-done bar chart, per-block
   reliability, streaks and total overtime, all from local SQLite. Charts
   are custom-painted vector work in the palette's single magnitude hue,
   with every figure also shown as text so nothing is readable by color
   alone. Reached through the hamburger drawer.

3. **Recurring tasks and templates** (PROPOSED): a recurrence rule per task
   (daily, weekdays, weekly), materialized lazily when a day is first
   viewed, so the database stores rules rather than infinite copies.

4. **Encrypted offline backup and device-to-device sync** (PROPOSED):
   export the database as an encrypted snapshot with per-row modification
   clocks; import merges by newest-wins per field. Keeps the offline-first
   promise while surviving a lost phone.

5. **Focus mode** (PROPOSED): starting a task pins a live progress
   notification with the exact remaining time (including overtime) and
   optionally enables do-not-disturb until the task concludes, driven by
   the same alarm infrastructure.

## 3. Solution and Implementation Strategy

### 3.1 The light blue and brown adaptive theme (IMPLEMENTED)

The default aesthetic is a light blue and brown palette; the previous
hard-coded dark-surface styling could not satisfy "text adjusts to remain
readable" because foregrounds were fixed. The architecture change is a
semantic palette registered as a `ThemeExtension`:

```dart
// core/app_palette.dart (excerpt)
factory AppPalette.fromSeeds({
  required Color accent,          // wheel-controlled; light blue default
  required bool hasBackdropImage,
}) {
  final onAccent = _foregroundFor(accent);      // derived, never declared
  const surface = Color(0xF5F7F1E8);            // warm cream card fill
  final surfaceInk = _inkSetFor(surface);       // espresso inks on light
  ...
}

static Color _foregroundFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.light
        ? _darkInk   // espresso on light fills
        : _lightInk; // warm cream on dark fills
```

Every widget reads `AppPalette.of(context)` instead of naming colors, so:
the default gradient (pale blue into cream into sand) carries dark espresso
text; a photo background switches the on-backdrop ink to light (the photo
sits under a dark scrim); and any accent chosen on the RGB wheel gets its
foreground recomputed (`onAccent`), which the test suite pins down with
brightness assertions. Status-bar icon brightness follows the same
derivation, so even system chrome stays readable.

### 3.2 Recurrence (proposed design)

Schema migration (version 2) plus lazy materialization:

```sql
ALTER TABLE tasks ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none';
ALTER TABLE tasks ADD COLUMN recurrence_parent_id INTEGER;

CREATE INDEX idx_tasks_recurrence
  ON tasks (recurrence) WHERE recurrence != 'none';
```

```dart
/// Called when the dashboard loads a date: instantiates any recurring
/// templates that should exist on that date but do not yet.
Future<void> materializeFor(String date) async {
  final templates = await repository.findRecurringTemplates();
  for (final template in templates) {
    if (template.recursOn(date) &&
        !await repository.instanceExists(template.id!, date)) {
      await repository.insert(template.copyWith(
        id: null, date: date, recurrenceParentId: template.id));
    }
  }
}
```

Editing an instance offers "this occurrence" (edit the row) or "all
future" (edit the template). Deleting the template cascades via
`recurrence_parent_id`.

### 3.3 Encrypted backup and sync (proposed design)

```dart
class SyncEnvelope {
  final int schemaVersion;
  final String deviceId;
  final List<TaskRecord> tasks;   // each with updatedAtMillis
}
// Export: JSON -> AES-GCM (key from user passphrase via PBKDF2) -> file.
// Import: decrypt, then merge newest-wins per row id; ties favor local.
```

A `updated_at` column (added in the same migration as recurrence) gives
each row its modification clock. No server is required; the file travels
by share sheet, drive or local Wi-Fi.

### 3.4 Focus mode (proposed design)

A foreground service notification driven by the existing alarm
infrastructure: starting a task schedules a "conclude" alarm at the
effective end (end plus overtime) and posts an ongoing chronometer
notification (`usesChronometer`, `ongoing: true`) on a silent channel.
The delay clock's overtime edits reschedule the conclude alarm, reusing
`AlarmService.scheduleForTask`'s cancel-then-register pattern, so focus
mode inherits exactness and reboot recovery for free.

### 3.5 Verification approach

`flutter analyze` is clean and the test suite covers the fixes with
observable behavior: gesture math, AM / PM toggling through the hoisted
button, midnight rollover, palette contrast derivation, and the suggestion
engine's conflict avoidance and block ranking. The remaining confirmed
fixes (channel policy, wake-lock playback, cursor lifecycle) are
device-level behaviors documented in code comments at their call sites.
