import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/component/upload_api.dart';

/// The microphone for the voice intro (RN expo-av `Audio.Recording`, HIGH
/// QUALITY preset): AAC in an .m4a, kept in the app's own storage so a saved
/// draft still finds it after a restart.
abstract class HostVoiceRecorder {
  const HostVoiceRecorder();

  /// Swap in tests: `HostVoiceRecorder.create = _FakeRecorder.new;`.
  static HostVoiceRecorder Function() create = _DeviceVoiceRecorder.new;

  /// Uploads a finished recording (AAC, `audio/mp4`); the media node. Swap
  /// in tests.
  static Future<JsonMap> Function(String path) upload = (path) =>
      UploadApi.uploadFile(
        path,
        fileName: 'audio-intro-${DateTime.now().millisecondsSinceEpoch}.m4a',
        mimeType: 'audio/mp4',
      );

  /// Asks for the microphone the first time; false when refused.
  Future<bool> hasPermission();

  /// Starts a new recording; returns where it is written.
  Future<String> start();

  /// Stops it; the file's path, or null when nothing was recorded.
  Future<String?> stop();

  /// Stops and deletes it (left the step while recording).
  Future<void> cancel();

  Future<void> dispose();
}

class _DeviceVoiceRecorder extends HostVoiceRecorder {
  _DeviceVoiceRecorder();

  final _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<String> start() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/voice_intro',
    );
    await dir.create(recursive: true);
    final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(numChannels: 1, bitRate: 96000),
      path: path,
    );
    return path;
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
