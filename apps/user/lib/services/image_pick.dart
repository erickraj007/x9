import 'package:image_picker/image_picker.dart';

/// Photo for a KYC document: the camera ([camera] true) or the gallery. Returns the file path, or null if cancelled.
Future<String?> pickKycImage(bool camera) async {
  final x = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  return x?.path;
}
