class AlarmSchedule {
  const AlarmSchedule({
    required this.audioAt,
    required this.warnAt,
  });

  final DateTime audioAt;

  final DateTime? warnAt;

  factory AlarmSchedule.forStart({
    required DateTime startAt,
    required Duration warningLead,
    required Duration audioLead,
  }) {
    final audioAt = startAt.subtract(audioLead);
    final warnAt = warningLead > audioLead
        ? startAt.subtract(warningLead)
        : null;
    return AlarmSchedule(audioAt: audioAt, warnAt: warnAt);
  }

  bool shouldArmWarning(DateTime now) {
    final at = warnAt;
    return at != null && at.isAfter(now);
  }

  bool shouldArmAudio(DateTime now) => audioAt.isAfter(now);

  @override
  String toString() => 'AlarmSchedule(audio: $audioAt, warn: $warnAt)';
}
