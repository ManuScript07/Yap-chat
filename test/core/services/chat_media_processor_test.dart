import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:yap_chat/core/services/chat_media_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps an already compliant chat JPEG unchanged', () async {
    final source = image.Image(width: 1200, height: 800);
    image.fill(source, color: image.ColorRgb8(3, 165, 224));
    final sourceBytes = Uint8List.fromList(
      image.encodeJpg(source, quality: 88),
    );
    final file = await _temporaryImage(sourceBytes);

    try {
      final result = await const ChatMediaProcessor().processImage(file.path);

      expect(result.bytes, orderedEquals(sourceBytes));
      expect(result.width, 1200);
      expect(result.height, 800);
    } finally {
      await file.parent.delete(recursive: true);
    }
  });

  test('limits chat image dimensions and upload size', () async {
    final source = image.Image(width: 2600, height: 1800);
    image.fill(source, color: image.ColorRgb8(3, 165, 224));
    final file = await _temporaryImage(
      Uint8List.fromList(image.encodePng(source)),
    );

    try {
      final result = await const ChatMediaProcessor().processImage(file.path);

      expect(
        result.bytes.lengthInBytes,
        lessThanOrEqualTo(ChatMediaProcessor.maxImageBytes),
      );
      expect(
        result.width,
        lessThanOrEqualTo(ChatMediaProcessor.maxImageDimension),
      );
      expect(
        result.height,
        lessThanOrEqualTo(ChatMediaProcessor.maxImageDimension),
      );
    } finally {
      await file.parent.delete(recursive: true);
    }
  });
}

Future<File> _temporaryImage(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('yap-chat-image-');
  final file = File('${directory.path}/image');
  await file.writeAsBytes(bytes);
  return file;
}
