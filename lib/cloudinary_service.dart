import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class CloudinaryService {
  // IMPORTANT: Replace these with your actual Cloudinary credentials
  static const String cloudName = "qpkjzslq";
  static const String uploadPreset = "ml_default"; 

  static Future<String?> uploadImage(File imageFile) async {
    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonMap = jsonDecode(responseString);
        return jsonMap['secure_url'];
      } else {
        print("Cloudinary Upload Failed: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Cloudinary Error: $e");
      return null;
    }
  }
}
