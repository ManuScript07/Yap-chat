import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ChatMediaProcessor {
  const ChatMediaProcessor();

  static const maxImageBytes = 2 * 1024 * 1024;
  static const maxAudioBytes = 5 * 1024 * 1024;
  static const maxSourceImageBytes = 40 * 1024 * 1024;

  Future<ProcessedChatImage> processImage(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    if (bytes.lengthInBytes > maxSourceImageBytes) {
      throw const ChatMediaException('Image source file is too large');
    }
    return compute(_compressChatImage, bytes);
  }

  Future<PersistentChatAudio> persistAudio(
    String sourcePath,
    List<double> waveform,
  ) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty || bytes.lengthInBytes > maxAudioBytes) {
      throw const ChatMediaException('Audio file exceeds the upload limit');
    }
    final directory = await getApplicationSupportDirectory();
    final outbox = Directory(path.join(directory.path, 'chat_outbox'));
    await outbox.create(recursive: true);
    final extension = path.extension(sourcePath).toLowerCase();
    final safeExtension = extension.isEmpty ? '.m4a' : extension;
    final destination = File(
      path.join(
        outbox.path,
        'voice_${DateTime.now().microsecondsSinceEpoch}$safeExtension',
      ),
    );
    if (source.absolute.path != destination.absolute.path) {
      await source.copy(destination.path);
    }
    return PersistentChatAudio(
      path: destination.path,
      sizeBytes: bytes.lengthInBytes,
      mimeType: _audioMimeType(safeExtension),
      waveform: downsampleWaveform(waveform),
    );
  }

  Future<Uint8List> readAudio(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    if (bytes.isEmpty || bytes.lengthInBytes > maxAudioBytes) {
      throw const ChatMediaException('Audio file exceeds the upload limit');
    }
    return bytes;
  }

  Future<void> deletePersistentAudio(String? sourcePath) async {
    if (sourcePath == null || sourcePath.isEmpty) return;
    final file = File(sourcePath);
    if (await file.exists()) await file.delete();
  }

  List<double> downsampleWaveform(
    List<double> source, {
    int targetLength = 96,
  }) {
    if (source.length <= targetLength) return List.unmodifiable(source);
    final result = <double>[];
    final bucketSize = source.length / targetLength;
    for (var index = 0; index < targetLength; index++) {
      final start = (index * bucketSize).floor();
      final end = ((index + 1) * bucketSize).ceil().clamp(1, source.length);
      var peak = 0.0;
      for (var itemIndex = start; itemIndex < end; itemIndex++) {
        if (source[itemIndex] > peak) peak = source[itemIndex];
      }
      result.add(peak.clamp(0.04, 1));
    }
    return List.unmodifiable(result);
  }

  String _audioMimeType(String extension) => switch (extension) {
    '.webm' => 'audio/webm',
    '.ogg' || '.opus' => 'audio/ogg',
    '.aac' => 'audio/aac',
    _ => 'audio/mp4',
  };
}

class ProcessedChatImage {
  const ProcessedChatImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  String get mimeType => 'image/jpeg';
}

class PersistentChatAudio {
  const PersistentChatAudio({
    required this.path,
    required this.sizeBytes,
    required this.mimeType,
    required this.waveform,
  });

  final String path;
  final int sizeBytes;
  final String mimeType;
  final List<double> waveform;
}

class ChatMediaException implements Exception {
  const ChatMediaException(this.message);

  final String message;

  @override
  String toString() => 'ChatMediaException: $message';
}

ProcessedChatImage _compressChatImage(Uint8List sourceBytes) {
  final decoded = image.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const ChatMediaException('Unsupported image format');
  }
  final oriented = image.bakeOrientation(decoded);
  const attempts = <(int, int)>[
    (2560, 92),
    (2304, 90),
    (2048, 88),
    (1920, 86),
    (1728, 84),
    (1536, 82),
    (1280, 80),
    (1080, 76),
  ];
  ProcessedChatImage? smallest;
  for (final (maxDimension, quality) in attempts) {
    final resized = _resizeToFit(oriented, maxDimension);
    final bytes = Uint8List.fromList(
      image.encodeJpg(resized, quality: quality),
    );
    final result = ProcessedChatImage(
      bytes: bytes,
      width: resized.width,
      height: resized.height,
    );
    smallest = result;
    if (bytes.lengthInBytes <= ChatMediaProcessor.maxImageBytes) return result;
  }
  if (smallest == null ||
      smallest.bytes.lengthInBytes > ChatMediaProcessor.maxImageBytes) {
    throw const ChatMediaException('Image cannot fit the upload limit');
  }
  return smallest;
}

image.Image _resizeToFit(image.Image source, int maxDimension) {
  if (source.width <= maxDimension && source.height <= maxDimension) {
    return source;
  }
  return source.width >= source.height
      ? image.copyResize(
          source,
          width: maxDimension,
          interpolation: image.Interpolation.cubic,
        )
      : image.copyResize(
          source,
          height: maxDimension,
          interpolation: image.Interpolation.cubic,
        );
}
