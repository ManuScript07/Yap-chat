import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:saver_gallery/saver_gallery.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

abstract class MediaService {
  static final ImagePicker _picker = ImagePicker();

  /// Открывает системную камеру.
  static Future<String?> takePhoto() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      return photo?.path;
    }

    return null;
  }

  /// Открывает галерею для выбора изображения.
  static Future<String?> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    return image?.path;
  }

  /// Открывает галерею и возвращает выбранное изображение для локального предпросмотра.
  static Future<Uint8List?> pickImageBytesFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    return image?.readAsBytes();
  }

  /// Возвращает результат камеры, потерянный при пересоздании Activity.
  static Future<String?> retrieveLostPhoto() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;

    return response.file?.path;
  }

  static Future<bool> isCameraPermanentlyDenied() async {
    return await Permission.camera.isPermanentlyDenied;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Сохраняет локальный файл или URL изображения в системную галерею Android.
  static Future<bool> saveImageToGallery(String imagePath) async {
    final uri = Uri.tryParse(imagePath);
    final isNetworkImage =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (isNetworkImage) {
      final networkUri = uri;
      final client = HttpClient();
      try {
        final request = await client.getUrl(networkUri);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return false;
        }
        final bytes = await response.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (builder, chunk) => builder..add(chunk),
        );
        final result = await SaverGallery.saveImage(
          bytes.takeBytes(),
          fileName: 'yap_chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
          albumPath: 'DCIM/Camera',
          skipIfExists: false,
        );
        return result.isSuccess;
      } finally {
        client.close(force: true);
      }
    }

    final file = File(imagePath);
    if (!await file.exists()) return false;
    final extension = path.extension(file.path).toLowerCase();
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final fileName =
        'yap_chat_${DateTime.now().millisecondsSinceEpoch}$safeExtension';

    final result = await SaverGallery.saveFile(
      filePath: file.path,
      fileName: fileName,
      albumPath: 'DCIM/Camera',
      skipIfExists: false,
    );

    return result.isSuccess;
  }
}
