import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../data/models/task.dart';
import '../../services/file_storage_service.dart';
import '../../services/ringtone_service.dart';
import 'frosted_surface.dart';

class AlarmSoundSelection {
  const AlarmSoundSelection({
    required this.type,
    this.uri,
    this.label,
  });

  const AlarmSoundSelection.systemDefault()
      : type = AlarmSoundType.system,
        uri = null,
        label = null;

  final AlarmSoundType type;
  final String? uri;
  final String? label;
}

Future<AlarmSoundSelection?> showSoundPickerSheet(BuildContext context) {
  return showModalBottomSheet<AlarmSoundSelection>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _SoundPickerSheet(),
  );
}

class _SoundPickerSheet extends StatefulWidget {
  const _SoundPickerSheet();

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  final RingtoneService _ringtoneService = RingtoneService();
  final FileStorageService _fileStorage = FileStorageService();

  late Future<List<SystemRingtone>> _ringtonesFuture;

  String? _previewingUri;

  @override
  void initState() {
    super.initState();
    _ringtoneService.onPreviewComplete = _handlePreviewComplete;
    _ringtonesFuture = _ringtoneService.getSystemRingtones();
  }

  void _retryRingtones() {
    setState(() {
      _ringtonesFuture = _ringtoneService.getSystemRingtones();
    });
  }

  void _handlePreviewComplete(String uri) {
    if (!mounted) return;
    if (_previewingUri != uri) return;
    setState(() => _previewingUri = null);
  }

  @override
  void dispose() {
    _ringtoneService.stop();
    _ringtoneService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return FrostedSurface(
      color: palette.surfaceElevated,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Alarm sound',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Pick a system ringtone or use your own audio file',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: FutureBuilder<List<SystemRingtone>>(
                  future: _ringtonesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final ringtones =
                        snapshot.data ?? const <SystemRingtone>[];
                    return ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        _buildOptionTile(
                          icon: Icons.notifications_active_outlined,
                          title: 'Default alarm sound',
                          subtitle: "Use the app's built-in alarm tone",
                          palette: palette,
                          onTap: () => Navigator.of(context)
                              .pop(const AlarmSoundSelection.systemDefault()),
                        ),
                        _buildOptionTile(
                          icon: Icons.library_music_outlined,
                          title: 'Browse device audio',
                          subtitle:
                              'Use any audio file as this task\'s ringtone',
                          palette: palette,
                          onTap: _pickCustomAudio,
                        ),
                        Divider(
                          color: palette.outline,
                          indent: 24,
                          endIndent: 24,
                        ),
                        if (ringtones.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                            child: Column(
                              children: [
                                Text(
                                  'No system ringtones available on this '
                                  'device.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: palette.textFaint,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _retryRingtones,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Try again'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.accent,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final ringtone in ringtones)
                            _buildRingtoneTile(ringtone, palette),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required AppPalette palette,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: palette.support),
      title: Text(
        title,
        style: TextStyle(color: palette.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  Widget _buildRingtoneTile(SystemRingtone ringtone, AppPalette palette) {
    final isPreviewing = _previewingUri == ringtone.uri;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 24, right: 12),
      leading: Icon(
        Icons.music_note_outlined,
        color: palette.textFaint,
      ),
      title: Text(
        ringtone.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.textPrimary, fontSize: 15),
      ),
      trailing: IconButton(
        icon: Icon(
          isPreviewing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          color: palette.accent,
        ),
        onPressed: () => _togglePreview(ringtone),
      ),
      onTap: () => Navigator.of(context).pop(
        AlarmSoundSelection(
          type: AlarmSoundType.system,
          uri: ringtone.uri,
          label: ringtone.title,
        ),
      ),
    );
  }

  Future<void> _togglePreview(SystemRingtone ringtone) async {
    if (_previewingUri == ringtone.uri) {
      await _ringtoneService.stop();
      if (!mounted) return;
      setState(() => _previewingUri = null);
    } else {
      await _ringtoneService.stop();
      await _ringtoneService.play(ringtone.uri);
      if (!mounted) return;
      setState(() => _previewingUri = ringtone.uri);
    }
  }

  Future<void> _pickCustomAudio() async {
    final result = await _fileStorage.pickAndStoreAlarmAudio();
    if (!mounted) return;

    if (result.isCancelled) return;

    final error = result.error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final storedPath = result.path!;
    Navigator.of(context).pop(
      AlarmSoundSelection(
        type: AlarmSoundType.custom,
        uri: storedPath,
        label: FileStorageService.displayName(storedPath),
      ),
    );
  }
}
