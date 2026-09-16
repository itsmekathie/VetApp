import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'users_welcome_screen.dart';
import 'email_service.dart';
import 'cloudinary_service.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String firstName;
  final String middleName;
  final String lastName;
  final String? suffix;
  final String contactNumber;
  final String email;
  final String password;
  final File? profileImage;

  const VerifyEmailScreen({
    super.key,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.suffix,
    required this.contactNumber,
    required this.email,
    required this.password,
    this.profileImage,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    debugPrint("VerifyEmailScreen initialized for: ${widget.email}");
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    // Force hide keyboard to ensure the action is visible
    FocusScope.of(context).unfocus();
    
    String inputOtp = _otpControllers.map((c) => c.text).join();

    if (inputOtp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter the complete 6-digit code")),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // Securely fetch OTP from Firebase
      final String encodedEmail = widget.email.replaceAll('.', ',');
      final otpSnap = await FirebaseDatabase.instance.ref('otp_verifications/$encodedEmail').get();
      
      if (!otpSnap.exists) {
        throw "OTP expired or not found. Please resend.";
      }

      final String dbOtp = (otpSnap.value as Map)['otp'].toString();

      if (inputOtp != dbOtp) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid code. Please try again.")),
        );
        setState(() => _isVerifying = false);
        return;
      }

      // If OTP is correct, proceed with registration
      final userRef = FirebaseDatabase.instance.ref('users').push();
      final String userId = userRef.key!;
      
      String? profileImageUrl;
      if (widget.profileImage != null) {
        profileImageUrl = await CloudinaryService.uploadImage(widget.profileImage!);
      }

      String fullName = "${widget.firstName} ${widget.lastName}";

      await userRef.set({
        'firstName': widget.firstName,
        'middleName': widget.middleName,
        'lastName': widget.lastName,
        'suffix': widget.suffix,
        'contactNumber': widget.contactNumber,
        'username': fullName,
        'email': widget.email,
        'password': widget.password,
        'profileImage': profileImageUrl,
        'isVerified': true, 
        'createdAt': ServerValue.timestamp,
        'settings': {
          'notifications': {
            'push_enabled': true,
            'promotions_enabled': true,
            'order_updates_enabled': true,
          }
        },
      });

      // Cleanup: Delete OTP record after successful verification
      await FirebaseDatabase.instance.ref('otp_verifications/$encodedEmail').remove();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${userId}_push_enabled', true);
      await prefs.setBool('${userId}_promotions_enabled', true);
      await prefs.setBool('${userId}_order_updates_enabled', true);

      debugPrint("Verification successful. Navigating to Welcome Screen...");

      if (!mounted) return;
      
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => UsersWelcomeScreen(username: fullName, userId: userId)),
        (route) => false,
      );
    } catch (e) {
      debugPrint("Verification Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isResending = true);
    try {
      String newOtp = (Random().nextInt(900000) + 100000).toString();
      
      // Save new OTP to Firebase
      final String encodedEmail = widget.email.replaceAll('.', ',');
      await FirebaseDatabase.instance.ref('otp_verifications/$encodedEmail').set({
        'otp': newOtp,
        'timestamp': ServerValue.timestamp,
      });

      await EmailService.sendOTP(widget.email, newOtp);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("A new code has been sent to your email."))
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _cancelRegistration() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Registration?"),
        content: const Text("If you cancel now, your registration progress will be lost."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Back")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Exit", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _cancelRegistration();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false, // FIXED: Background stays stable
        body: GoldBlobsBackground(
          useSafeArea: false,
          child: SafeArea(
            child: ResponsiveConstraints(
              maxWidth: 500, // Limit width for Tablet/Desktop
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "A code was sent to your\nemail (${widget.email})", 
                          textAlign: TextAlign.center, 
                          style: TextStyle(
                            fontSize: ResponsiveLayout.isMobile(context) ? 20 : 26, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                        const SizedBox(height: 40),
                        // OTP Input Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                          children: List.generate(6, (index) => _buildOtpBox(index))
                        ),
                        const SizedBox(height: 80),
                        // Action Row: resent on left, register on right
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _isResending ? null : _resendOtp,
                              child: Text(
                                _isResending ? "sending..." : "resent", 
                                style: TextStyle(
                                  color: const Color(0xFF0000FF), 
                                  fontSize: ResponsiveLayout.isMobile(context) ? 20 : 24, 
                                  fontWeight: FontWeight.bold
                                )
                              ),
                            ),
                            _isVerifying 
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 40),
                                  child: CircularProgressIndicator(color: Color(0xFFB8860B)),
                                )
                              : _buildGradientButton("register", _verifyOtp),
                          ],
                        ),
                        const SizedBox(height: 100),
                        TextButton(
                          onPressed: _cancelRegistration, 
                          child: const Text("Cancel and delete info", style: TextStyle(color: Colors.red))
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 45, height: 60,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: "",
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15), 
            borderSide: const BorderSide(color: Color(0xFFFBDB83), width: 2)
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15), 
            borderSide: const BorderSide(color: Color(0xFFB8860B), width: 3)
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }

  Widget _buildGradientButton(String text, VoidCallback onPressed) {
    return Container(
      width: 150, height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15), 
        gradient: const LinearGradient(
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)]
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
        ]
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, 
          shadowColor: Colors.transparent, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
        ),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }
}
