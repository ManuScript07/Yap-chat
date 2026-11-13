import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:yap_chat/core/services/avatar_image_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps an already compliant JPEG unchanged', () async {
    final source = image.Image(width: 800, height: 800);
    image.fill(source, color: image.ColorRgb8(3, 165, 224));
    final sourceBytes = Uint8List.fromList(
      image.encodeJpg(source, quality: 88),
    );

    final result = await const AvatarImageProcessor().compress(sourceBytes);

    expect(result, orderedEquals(sourceBytes));
  });

  test('compresses an avatar below the Storage limit', () async {
    final source = image.Image(width: 2400, height: 1600);
    image.fill(source, color: image.ColorRgb8(3, 165, 224));
    final sourceBytes = Uint8List.fromList(image.encodePng(source));

    final result = await const AvatarImageProcessor().compress(sourceBytes);
    final decoded = image.decodeImage(result);

    expect(result.lengthInBytes, lessThanOrEqualTo(1800 * 1024));
    expect(decoded, isNotNull);
    expect(
      decoded!.width,
      lessThanOrEqualTo(AvatarImageProcessor.maxDimension),
    );
    expect(
      decoded.height,
      lessThanOrEqualTo(AvatarImageProcessor.maxDimension),
    );
  });
}
