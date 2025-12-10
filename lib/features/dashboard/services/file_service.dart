import 'package:file_picker/file_picker.dart';

abstract class IFileService {
  Future<String?> pickFileName();
}

class FileService implements IFileService {
  @override
  Future<String?> pickFileName() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      return result.files.single.name;
    }
    return null;
  }
}
