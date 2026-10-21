import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// Converts local audio files only. Callers are responsible for ensuring the
/// input/output paths are inside their own staging or add-on directory.
Future<void> morneyeConvertAudio({
  required String inputPath,
  required String outputPath,
  String codec = 'copy',
}) async {
  if (!const {'copy', 'flac'}.contains(codec)) {
    throw ArgumentError.value(codec, 'codec', 'Unsupported audio conversion');
  }
  final input = File(inputPath);
  if (!await input.exists() || await input.length() == 0) {
    throw StateError('The audio conversion input is missing or empty.');
  }
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  if (await output.exists()) await output.delete();

  final arguments = <String>[
    '-nostdin',
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    inputPath,
    '-map',
    '0:a:0',
    '-vn',
    '-sn',
    '-dn',
    '-map_metadata',
    '0',
    '-c:a',
    codec,
    outputPath,
  ];
  final session = await FFmpegKit.executeWithArguments(arguments);
  final returnCode = await session.getReturnCode();
  if (!ReturnCode.isSuccess(returnCode)) {
    final outputText = (await session.getOutput())?.trim() ?? '';
    if (await output.exists()) await output.delete();
    // Some muxers do not accept a FLAC bitstream packaged in MP4. Re-encoding
    // FLAC to FLAC is still lossless, so use the FLAC encoder only as fallback.
    if (codec == 'copy' && outputPath.toLowerCase().endsWith('.flac')) {
      return morneyeConvertAudio(
        inputPath: inputPath,
        outputPath: outputPath,
        codec: 'flac',
      );
    }
    final detail = outputText.isEmpty
        ? ''
        : ' ${outputText.length > 500 ? outputText.substring(outputText.length - 500) : outputText}';
    throw StateError('FFmpeg audio conversion failed.$detail');
  }
  if (!await output.exists() || await output.length() == 0) {
    throw StateError('FFmpeg completed without producing audio.');
  }
}
