import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';

class EmailService {
  static Future<void> sendOTP(String recipientEmail, String otp) async {
    try {
      final adminsData = await DatabaseHelper.getData('admins');
      
      if (adminsData == null || adminsData is! Map) throw 'Admin settings not found in Firebase.';
      
      // Get the first admin's data for SMTP
      final adminData = adminsData.values.first;
      
      final String adminEmail = (adminData['email'] ?? '').toString().trim();
      final String smtpPassword = (adminData['smtpPassword'] ?? adminData['password'] ?? '').toString().replaceAll(' ', '');

      if (adminEmail.isEmpty || smtpPassword.isEmpty) {
        throw 'Admin credentials missing in database.';
      }

      // Gagamit tayo ng Port 465 (SSL) dahil mas madalas itong bukas sa mga networks kaysa 587
      final smtpServer = SmtpServer('smtp.gmail.com',
          port: 465,
          ssl: true,
          username: adminEmail,
          password: smtpPassword);

      final message = Message()
        ..from = Address(adminEmail, 'Docloy Vet Clinic')
        ..recipients.add(recipientEmail.trim())
        ..subject = 'Verification Code: $otp'
        ..html = """
          <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #B8860B; border-radius: 10px;">
            <h2 style="color: #8A6E2F;">Docloy Veterinary Clinic</h2>
            <p>Your registration verification code is:</p>
            <div style="background: #FBDB83; padding: 15px; text-align: center; border-radius: 5px;">
              <h1 style="color: #B8860B; letter-spacing: 5px; margin: 0;">$otp</h1>
            </div>
          </div>
        """;

      // Dagdagan ang timeout para hindi agad mag-error kung mabagal ang internet
      await send(message, smtpServer).timeout(const Duration(seconds: 15));
      
    } catch (e) {
      debugPrint('SMTP Error: $e');
      if (e.toString().contains('timed out')) {
        throw 'Connection Timeout: Please check your internet or try a different network (Wi-Fi/Data).';
      } else if (e.toString().contains('Invalid login')) {
        throw 'Gmail Login Rejected: Check your App Password in Firebase.';
      }
      throw 'Failed to send email: $e';
    }
  }
}
