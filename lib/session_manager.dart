import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SessionManager {
  static const String keyUserId = 'logged_in_userId';
  static const String keyUsername = 'logged_in_username';
  static const String keyEmail = 'logged_in_email';
  static const String keyDeviceId = 'device_unique_id';
  static const String keyIsAdmin = 'logged_in_is_admin';
  static const String keyLastUserId = 'last_user_id';
  static const String keyLastUsername = 'last_username';
  static const String keyLastEmail = 'last_email';
  static const String keyLastIsAdmin = 'last_is_admin';

  /// Gets a unique ID for this device. Generates one if it doesn't exist.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(keyDeviceId);

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(keyDeviceId, deviceId);
    }
    return deviceId;
  }

  /// Gets the device name/model (e.g., "Samsung SM-G991B")
  static Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return "${androidInfo.manufacturer} ${androidInfo.model}";
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.name;
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return windowsInfo.computerName;
    }
    return "Unknown Device";
  }

  /// Saves the active session
  static Future<void> saveSession(String userId, String username, String email, {bool isAdmin = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUserId, userId);
    await prefs.setString(keyUsername, username);
    await prefs.setString(keyEmail, email);
    await prefs.setBool(keyIsAdmin, isAdmin);
    
    // Also save as last user for fingerprint login
    await prefs.setString(keyLastUserId, userId);
    await prefs.setString(keyLastUsername, username);
    await prefs.setString(keyLastEmail, email);
    await prefs.setBool(keyLastIsAdmin, isAdmin);
  }

  /// Clears the active session (for logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyUserId);
    await prefs.remove(keyUsername);
    await prefs.remove(keyEmail);
    await prefs.remove(keyIsAdmin);
  }

  /// Checks if a user is currently logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(keyUserId);
  }

  /// Checks if the current session is an admin
  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsAdmin) ?? false;
  }

  /// Gets the current logged in user ID
  static Future<String?> getLoggedInUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyUserId);
  }
}
