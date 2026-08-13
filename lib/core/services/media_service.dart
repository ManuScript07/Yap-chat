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
    final fileName = path.basename(imagePath);

    final result = await SaverGallery.saveFile(
      filePath: imagePath,
      fileName: fileName,
      albumPath: 'DCIM/Camera',
      skipIfExists: false,
    );

    return result.isSuccess;
  }
}
