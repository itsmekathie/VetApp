import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_service.dart';
import 'dart:math';
import 'login_screen.dart';
import 'session_manager.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

// --- SHARED UI WIDGETS ---
class UpdateBaseScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const UpdateBaseScreen({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: Center(
            child: ResponsiveConstraints(
              maxWidth: 600, // Constrain width for all update screens
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, size: 30), onPressed: () => Navigator.pop(context)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title, 
                            style: TextStyle(
                              fontSize: ResponsiveLayout.isMobile(context) ? 22 : 28, 
                              fontWeight: FontWeight.bold
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GoldGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isEnabled;

  const GoldGradientButton({super.key, required this.label, this.onTap, this.isEnabled = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: isEnabled 
            ? const LinearGradient(colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)])
            : null,
          color: isEnabled ? null : Colors.grey.shade400,
        ),
        child: Center(
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// --- PHONE UPDATE ---
class ChangePhoneScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;
  const ChangePhoneScreen({super.key, required this.userId, this.isAdmin = false});
  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _controller = TextEditingController();
  bool _isFilled = false;

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Change Phone Number",
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneNumberFormatter()],
              onChanged: (v) {
                String digits = v.replaceAll(RegExp(r'\D'), '');
                setState(() => _isFilled = digits.length == 10);
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.phone, color: Colors.grey),
                prefixText: '+63 ',
                hintText: "9XX XXX XXXX",
              ),
            ),
            const SizedBox(height: 30),
            GoldGradientButton(
              label: "Next",
              isEnabled: _isFilled,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => VerificationScreen(
                userId: widget.userId, 
                target: '+63 ${_controller.text.trim()}', 
                type: 'Phone',
                isAdmin: widget.isAdmin,
              ))),
            ),
          ],
        ),
      ),
    );
  }
}

// --- EMAIL UPDATE ---
class ChangeEmailScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;
  const ChangeEmailScreen({super.key, required this.userId, this.isAdmin = false});
  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _controller = TextEditingController();
  bool _isFilled = false;

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Change Email",
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) {
                setState(() {
                  _isFilled = v.toLowerCase().endsWith('@gmail.com') && v.trim() != '@gmail.com';
                });
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.email, color: Colors.grey),
                hintText: "Email Address (@gmail.com)",
              ),
            ),
            const SizedBox(height: 30),
            GoldGradientButton(
              label: "Next",
              isEnabled: _isFilled,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => VerificationScreen(
                userId: widget.userId, 
                target: _controller.text.trim(), 
                type: 'Email',
                isAdmin: widget.isAdmin,
              ))),
            ),
          ],
        ),
      ),
    );
  }
}

// --- OTP VERIFICATION ---
class VerificationScreen extends StatefulWidget {
  final String userId;
  final String target;
  final String type; // 'Phone', 'Email', or 'Password'
  final bool isAdmin;
  const VerificationScreen({
    super.key, 
    required this.userId, 
    required this.target, 
    required this.type,
    this.isAdmin = false,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (i) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (i) => FocusNode());
  String? _generatedOtp;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  Future<void> _sendOtp() async {
    String otp = (Random().nextInt(900000) + 100000).toString();
    setState(() => _generatedOtp = otp);
    
    // Use target for Email, or fetch current email for Password flow
    String recipient = widget.target;
    if (widget.type == 'Password') {
      String path = widget.isAdmin ? 'admins/${widget.userId}/email' : 'users/${widget.userId}/email';
      final snap = await FirebaseDatabase.instance.ref().child(path).get();
      recipient = snap.value.toString();
    }

    try {
      await EmailService.sendOTP(recipient, otp);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("OTP sent to $recipient")));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error sending OTP: $e")));
    }
  }

  void _verify() async {
    String input = _controllers.map((c) => c.text).join();
    if (input != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid code!")));
      return;
    }

    if (widget.type == 'Password') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => ChangePasswordScreen(userId: widget.userId, isAdmin: widget.isAdmin)));
    } else {
      setState(() => _isLoading = true);
      String field = widget.type == 'Phone' ? 'contactNumber' : 'email';
      String path = widget.isAdmin ? 'admins/${widget.userId}' : 'users/${widget.userId}';
      await FirebaseDatabase.instance.ref().child(path).update({field: widget.target});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Update successful!")));
        Navigator.pop(context);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Enter Verification Code",
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text("Your verification code is sent by ${widget.type == 'Phone' ? 'SMS' : 'email'} to", textAlign: TextAlign.center),
            Text(widget.target, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) => _otpBox(i)),
            ),
            const SizedBox(height: 40),
            _isLoading ? const CircularProgressIndicator() : GoldGradientButton(label: "Next", onTap: _verify),
            const SizedBox(height: 20),
            TextButton(onPressed: _sendOtp, child: const Text("Resend Now", style: TextStyle(color: Colors.blue))),
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
          if (v.isNotEmpty && i < 5) _nodes[i+1].requestFocus();
          if (v.isEmpty && i > 0) _nodes[i-1].requestFocus();
        },
      ),
    );
  }
}

// --- PASSWORD FLOW: SECURITY CHECK ---
class SecurityCheckScreen extends StatelessWidget {
  final String userId;
  final bool isAdmin;
  const SecurityCheckScreen({super.key, required this.userId, this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Security Check",
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Text("To protect your account security, please verify your identity with one of the methods below.", textAlign: TextAlign.center),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => VerificationScreen(userId: userId, target: "Email Verification", type: 'Password', isAdmin: isAdmin))),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFFBDB83)),
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.email_outlined, size: 30),
                    SizedBox(width: 15),
                    Text("Send Email Verification", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- SET NEW PASSWORD ---
class ChangePasswordScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;
  const ChangePasswordScreen({super.key, required this.userId, this.isAdmin = false});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  void _submit() async {
    if (_pass.text.length < 8) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 8 characters")));
       return;
    }
    if (_pass.text != _confirm.text) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
       return;
    }

    String path = widget.isAdmin ? 'admins/${widget.userId}' : 'users/${widget.userId}';
    await FirebaseDatabase.instance.ref().child(path).update({'password': _pass.text});
    if (mounted) _showSuccessDialog();
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
            const Text("Password changed successfully!!", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 25),
            GestureDetector(
              onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => LoginScreen()), (r) => false),
              child: const Text("Back to log in", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Change Password",
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Text("\"Ensure your password is at least 8 characters long, includes a mix of letters, numbers, and symbols, and is never shared with anyone.\"", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 30),
            _passField(_pass, "New Password"),
            const SizedBox(height: 20),
            _passField(_confirm, "Confirm Password"),
            const SizedBox(height: 40),
            GoldGradientButton(label: "Next", onTap: _submit),
          ],
        ),
      ),
    );
  }

  Widget _passField(TextEditingController ctrl, String hint) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
      child: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: InputDecoration(hintText: hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFFBDB83)))),
      ),
    );
  }
}

// --- BIOMETRIC SETUP ---
class FingerprintSetupScreen extends StatelessWidget {
  final String userId;
  final VoidCallback onEnabled;
  const FingerprintSetupScreen({super.key, required this.userId, required this.onEnabled});

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Set Up Fingerprint Authentication",
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Text("Verify its you! \"Enable fingerprint authentication to log in quickly and securely using the biometrics saved on your device", textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
            const Spacer(),
            const Icon(Icons.fingerprint, size: 100, color: Colors.grey),
            const Spacer(),
            GoldGradientButton(label: "Next", onTap: () async {
               final localAuth = LocalAuthentication();
               try {
                 bool authenticated = await localAuth.authenticate(
                   localizedReason: 'Please authenticate to enable fingerprint login',
                   options: const AuthenticationOptions(
                     stickyAuth: true,
                     biometricOnly: false, // Allow PIN/Pattern as fallback like Shopee
                   ),
                 );
                 if (authenticated) {
                   final prefs = await SharedPreferences.getInstance();
                   await prefs.setBool('fingerprint_enabled_$userId', true);
                   onEnabled();
                   if (context.mounted) Navigator.pop(context);
                 }
               } catch (e) {
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Authentication Error: $e'))
                   );
                 }
               }
            }),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// --- MANAGE LOGIN DEVICES ---
class ManageLoginDeviceScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;
  const ManageLoginDeviceScreen({super.key, required this.userId, this.isAdmin = false});

  @override
  State<ManageLoginDeviceScreen> createState() => _ManageLoginDeviceScreenState();
}

class _ManageLoginDeviceScreenState extends State<ManageLoginDeviceScreen> {
  final _database = FirebaseDatabase.instance.ref();
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _loadCurrentDeviceId();
  }

  Future<void> _loadCurrentDeviceId() async {
    String id = await SessionManager.getDeviceId();
    setState(() => _currentDeviceId = id);
  }

  Future<void> _logoutDevice(String deviceId, String deviceName) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout Device"),
        content: Text("Are you sure you want to log out from $deviceName?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Log Out", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      String path = widget.isAdmin ? 'admins' : 'users';
      await _database.child(path).child(widget.userId).child('devices').child(deviceId).remove();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Successfully logged out $deviceName")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return UpdateBaseScreen(
      title: "Manage Login Device",
      child: Center(
        child: ResponsiveConstraints(
          maxWidth: 900, // Specific width for device list
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                color: Colors.grey.shade100,
                child: const Text("Login Device(s)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: StreamBuilder(
                  stream: _database.child(widget.isAdmin ? 'admins' : 'users').child(widget.userId).child('devices').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                      return const Center(child: Text("No login devices found"));
                    }

                    Map devices = snapshot.data!.snapshot.value as Map;
                    List deviceList = devices.entries.toList();

                    return ListView.separated(
                      itemCount: deviceList.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        var entry = deviceList[index];
                        String deviceId = entry.key;
                        var data = Map<String, dynamic>.from(entry.value);
                        bool isThisDevice = deviceId == _currentDeviceId;

                        return _deviceItem(
                          deviceId: deviceId,
                          name: data['deviceName'] ?? "Unknown Device",
                          lastLogin: data['lastLogin'] ?? "",
                          isThisDevice: isThisDevice,
                        );
                      },
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "Review the devices that you have logged in Docloy Vet App account. If you see a device you don't recognize, log it out immediately.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceItem({required String deviceId, required String name, required String lastLogin, required bool isThisDevice}) {
    String dateStr = "";
    if (lastLogin.isNotEmpty) {
      DateTime dt = DateTime.parse(lastLogin);
      dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(dt);
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFB8860B).withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(Icons.phone_android, color: isThisDevice ? const Color(0xFFB8860B) : Colors.grey),
      ),
      title: Row(
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (isThisDevice) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(5)),
              child: const Text("This Device", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]
        ],
      ),
      subtitle: Text(dateStr, style: const TextStyle(fontSize: 12)),
      trailing: isThisDevice 
        ? null 
        : IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => _logoutDevice(deviceId, name),
          ),
    );
  }
}

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll(RegExp(r'\D'), '');
    
    if (text.isNotEmpty && (text.startsWith('0') || !text.startsWith('9'))) {
      return oldValue;
    }

    if (text.length > 10) {
      text = text.substring(0, 10);
    }

    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 3) formatted += ' ';
      if (i == 6) formatted += ' ';
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
