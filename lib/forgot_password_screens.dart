import 'package:flutter/material.dart';
import 'dart:math';
import 'database_helper.dart';
import 'email_service.dart';
import 'login_screen.dart';
import 'account_update_screens.dart'; // To reuse GoldGradientButton and UpdateBaseScreen style

class ForgotPasswordRequestScreen extends StatefulWidget {
  const ForgotPasswordRequestScreen({super.key});

  @override
  State<ForgotPasswordRequestScreen> createState() => _ForgotPasswordRequestScreenState();
}

class _ForgotPasswordRequestScreenState extends State<ForgotPasswordRequestScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  void _sendResetCode() async {
    String email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid email address")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Check if user exists in admins or users
      String? foundUserId;
      bool isAdmin = false;

      final adminsData = await DatabaseHelper.getData("admins");
      if (adminsData != null && adminsData is Map) {
        for (var key in adminsData.keys) {
          if (adminsData[key]['email'] == email) {
            foundUserId = key;
            isAdmin = true;
            break;
          }
        }
      }

      if (foundUserId == null) {
        final usersData = await DatabaseHelper.getData("users");
        if (usersData != null && usersData is Map) {
          for (var key in usersData.keys) {
            if (usersData[key]['email'] == email) {
              foundUserId = key;
              isAdmin = false;
              break;
            }
          }
        }
      }

      if (foundUserId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email not found")));
        setState(() => _isLoading = false);
        return;
      }

      // 2. Generate OTP
      String otp = (Random().nextInt(900000) + 100000).toString();
      
      // 3. Send Email
      await EmailService.sendOTP(email, otp);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ForgotPasswordVerificationScreen(
              userId: foundUserId!,
              email: email,
              otp: otp,
              isAdmin: isAdmin,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Forgot Password",
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Text(
              "Enter your email address to receive a verification code to reset your password.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.email, color: Colors.grey),
                hintText: "Email Address",
              ),
            ),
            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator()
                : GoldGradientButton(label: "Send Code", onTap: _sendResetCode),
          ],
        ),
      ),
    );
  }
}

class ForgotPasswordVerificationScreen extends StatefulWidget {
  final String userId;
  final String email;
  final String otp;
  final bool isAdmin;

  const ForgotPasswordVerificationScreen({
    super.key,
    required this.userId,
    required this.email,
    required this.otp,
    required this.isAdmin,
  });

  @override
  State<ForgotPasswordVerificationScreen> createState() => _ForgotPasswordVerificationScreenState();
}

class _ForgotPasswordVerificationScreenState extends State<ForgotPasswordVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (i) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (i) => FocusNode());
  late String _currentOtp;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _currentOtp = widget.otp;
  }

  void _verify() {
    String input = _controllers.map((c) => c.text).join();
    if (input != _currentOtp) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid verification code")));
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ForgotPasswordNewPasswordScreen(
          userId: widget.userId,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
  }

  Future<void> _resendOtp() async {
    setState(() => _isResending = true);
    try {
      String newOtp = (Random().nextInt(900000) + 100000).toString();
      await EmailService.sendOTP(widget.email, newOtp);
      setState(() => _currentOtp = newOtp);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("A new code has been sent")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Verification",
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text("Please enter the 6-digit verification code sent to", textAlign: TextAlign.center),
            Text(widget.email, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) => _otpBox(i)),
            ),
            const SizedBox(height: 40),
            GoldGradientButton(label: "Verify", onTap: _verify),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _isResending ? null : _resendOtp,
              child: Text(
                _isResending ? "Sending..." : "Resend Code",
                style: const TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _otpBox(int i) {
    return SizedBox(
      width: 40,
      child: TextField(
        controller: _controllers[i],
        focusNode: _nodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(counterText: ""),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
        },
      ),
    );
  }
}

class ForgotPasswordNewPasswordScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;

  const ForgotPasswordNewPasswordScreen({
    super.key,
    required this.userId,
    required this.isAdmin,
  });

  @override
  State<ForgotPasswordNewPasswordScreen> createState() => _ForgotPasswordNewPasswordScreenState();
}

class _ForgotPasswordNewPasswordScreenState extends State<ForgotPasswordNewPasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _isLoading = false;

  void _submit() async {
    if (_pass.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 8 characters")));
      return;
    }
    if (_pass.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String path = widget.isAdmin ? 'admins/${widget.userId}' : 'users/${widget.userId}';
      await DatabaseHelper.updateData(path, {'password': _pass.text});
      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            const Text(
              "Password Reset Successful!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Your password has been reset successfully. You can now log in with your new password.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 25),
            GoldGradientButton(
              label: "Back to Login",
              onTap: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (c) => LoginScreen()),
                (r) => false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "New Password",
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Text(
              "Please create a strong password that you don't use for other accounts.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            _passField(_pass, "New Password"),
            const SizedBox(height: 20),
            _passField(_confirm, "Confirm Password"),
            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator()
                : GoldGradientButton(label: "Reset Password", onTap: _submit),
          ],
        ),
      ),
    );
  }

  Widget _passField(TextEditingController ctrl, String hint) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFFBDB83)),
          ),
        ),
      ),
    );
  }
}
