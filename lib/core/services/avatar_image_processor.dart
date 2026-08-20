import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

class AvatarImageProcessor {
  const AvatarImageProcessor();

  static const maxSourceBytes = 20 * 1024 * 1024;
  static const targetUploadBytes = 1800 * 1024;
  static const maxDimension = 1440;

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
  final jpegInfo = image.JpegDecoder().startDecode(sourceBytes);
  if (jpegInfo != null &&
      jpegInfo.width <= AvatarImageProcessor.maxDimension &&
      jpegInfo.height <= AvatarImageProcessor.maxDimension &&
      sourceBytes.lengthInBytes <= AvatarImageProcessor.targetUploadBytes) {
    return sourceBytes;
  }

  final decoded = image.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const AvatarImageException('Unsupported avatar image');
  }

  final oriented = image.bakeOrientation(decoded);
  final primary = _resizeToFit(oriented, AvatarImageProcessor.maxDimension);
  final primaryResult = _encodeToLimit(primary, const [88, 82, 76, 70]);
  if (primaryResult.fits) return primaryResult.bytes;

  final compact = _resizeToFit(oriented, 1024);
  final compactResult = _encodeToLimit(compact, const [78, 70, 64]);
  if (compactResult.fits) return compactResult.bytes;

  throw const AvatarImageException('Avatar cannot fit the upload limit');
}

({Uint8List bytes, bool fits}) _encodeToLimit(
  image.Image source,
  List<int> qualities,
) {
  late Uint8List encoded;
  for (final quality in qualities) {
    encoded = Uint8List.fromList(image.encodeJpg(source, quality: quality));
    if (encoded.lengthInBytes <= AvatarImageProcessor.targetUploadBytes) {
      return (bytes: encoded, fits: true);
    }
  }
  return (bytes: encoded, fits: false);
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
