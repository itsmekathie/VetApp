import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const String _baseUrl = 'https://my-petcare-app-2e4fe-default-rtdb.firebaseio.com';

  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  /// Kumuha ng data (GET)
  static Future<dynamic> getData(String path) async {
    if (_isWindows) {
      final url = Uri.parse('$_baseUrl/$path.json');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } else {
      final snap = await FirebaseDatabase.instance.ref(path).get();
      return snap.value;
    }
  }

  /// Mag-save ng data (SET/PUT)
  static Future<void> setData(String path, dynamic data) async {
    if (_isWindows) {
      final url = Uri.parse('$_baseUrl/$path.json');
      await http.put(url, body: json.encode(data));
    } else {
      await FirebaseDatabase.instance.ref(path).set(data);
    }
  }

  /// Mag-update ng data (UPDATE/PATCH)
  static Future<void> updateData(String path, Map<String, dynamic> data) async {
    if (_isWindows) {
      final url = Uri.parse('$_baseUrl/$path.json');
      await http.patch(url, body: json.encode(data));
    } else {
      await FirebaseDatabase.instance.ref(path).update(data);
    }
  }
  
  /// Mag-push ng bagong data (PUSH/POST)
  static Future<String?> pushData(String path, dynamic data) async {
    if (_isWindows) {
      final url = Uri.parse('$_baseUrl/$path.json');
      final res = await http.post(url, body: json.encode(data));
      if (res.statusCode == 200) {
        return json.decode(res.body)['name'];
      }
      return null;
    } else {
      final ref = FirebaseDatabase.instance.ref(path).push();
      await ref.set(data);
      return ref.key;
    }
  }
}
