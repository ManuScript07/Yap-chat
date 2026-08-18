import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

class AvatarImageProcessor {
  const AvatarImageProcessor();

  static const maxSourceBytes = 20 * 1024 * 1024;
  static const targetUploadBytes = 1800 * 1024;

  Future<Uint8List> compress(Uint8List sourceBytes) {
    if (sourceBytes.lengthInBytes > maxSourceBytes) {
      throw const AvatarImageException('Avatar source file is too large');
    }
    return compute(_compressAvatar, sourceBytes);
  }
}

class AvatarImageException implements Exception {
  const AvatarImageException(this.message);

  final String message;

  @override
  String toString() => 'AvatarImageException: $message';
}

Uint8List _compressAvatar(Uint8List sourceBytes) {
  final decoded = image.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const AvatarImageException('Unsupported avatar image');
  }

  final oriented = image.bakeOrientation(decoded);
  const attempts = <(int, int)>[
    (1440, 90),
    (1280, 88),
    (1024, 86),
    (896, 82),
    (768, 78),
    (640, 72),
    (512, 65),
  ];

  Uint8List? smallest;
  for (final (maxDimension, quality) in attempts) {
    final resized = _resizeToFit(oriented, maxDimension);
    final encoded = Uint8List.fromList(
      image.encodeJpg(resized, quality: quality),
    );
    smallest = encoded;
    if (encoded.lengthInBytes <= AvatarImageProcessor.targetUploadBytes) {
      return encoded;
    }
  }

  if (smallest == null ||
      smallest.lengthInBytes > AvatarImageProcessor.targetUploadBytes) {
    throw const AvatarImageException('Avatar cannot fit the upload limit');
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
