import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';
import 'users_welcome_screen.dart';
import 'register_screen.dart';
import 'session_manager.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'forgot_password_screens.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _canCheckBiometrics = false;
  String? _lastUsername;
  String? _lastUserId;
  bool _lastIsAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  Future<void> _checkBiometricSupport() async {
    if (kIsWeb || Platform.isWindows) return;
    
    final localAuth = LocalAuthentication();
    final prefs = await SharedPreferences.getInstance();
    
    bool canCheck = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
    String? lastId = prefs.getString(SessionManager.keyLastUserId);
    bool fingerEnabled = false;
    
    if (lastId != null) {
      fingerEnabled = prefs.getBool('fingerprint_enabled_$lastId') ?? false;
    }

    setState(() {
      _canCheckBiometrics = canCheck && fingerEnabled;
      _lastUserId = lastId;
      _lastUsername = prefs.getString(SessionManager.keyLastUsername);
      _lastIsAdmin = prefs.getBool(SessionManager.keyLastIsAdmin) ?? false;
    });
  }

  Future<void> _handleFingerprintLogin() async {
    if (_lastUserId == null) return;
    
    final localAuth = LocalAuthentication();
    try {
      bool authenticated = await localAuth.authenticate(
        localizedReason: 'Login to Docloy Vet App using fingerprint',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (authenticated) {
        setState(() => _isLoading = true);
        
        String path = _lastIsAdmin ? "admins" : "users";
        final val = await DatabaseHelper.getData("$path/$_lastUserId");

        if (val != null) {
          if (_lastIsAdmin || val['isVerified'] == true) {
            await SessionManager.saveSession(_lastUserId!, val['username'] ?? val['firstName'] ?? val['email'], val['email'], isAdmin: _lastIsAdmin);
            await _registerDevice(_lastUserId!, isAdmin: _lastIsAdmin);

            if (!mounted) return;
            if (_lastIsAdmin) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => WelcomeScreen(username: val['username'] ?? val['email'])),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => UsersWelcomeScreen(username: val['username'] ?? val['firstName'], userId: _lastUserId!)),
              );
            }
          } else {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account not verified.')));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User record not found.')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Biometric Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerDevice(String userId, {bool isAdmin = false}) async {
    String deviceId = await SessionManager.getDeviceId();
    String deviceName = await SessionManager.getDeviceName();
    
    String path = isAdmin ? "admins" : "users";
    Map<String, dynamic> deviceData = {
      'deviceName': deviceName,
      'lastLogin': DateTime.now().toIso8601String(),
      'platform': Platform.isWindows ? 'Windows' : (Platform.isAndroid ? 'Android' : 'iOS'),
    };

    await DatabaseHelper.setData("$path/$userId/devices/$deviceId", deviceData);
  }

  void _login() async {
    String input = _emailController.text.trim();
    String passwordInput = _passwordController.text.trim();

    if (input.isEmpty || passwordInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter both email and password')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. CHECK ADMINS
      final adminsData = await DatabaseHelper.getData("admins");
      if (adminsData != null && adminsData is Map) {
        for (var key in adminsData.keys) {
          final data = adminsData[key];
          if (data['email'] == input || data['username'] == input) {
            if (data['password'] == passwordInput) {
              await SessionManager.saveSession(key, data['username'] ?? input, data['email'] ?? '', isAdmin: true);
              await _registerDevice(key, isAdmin: true);
              if (!mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => WelcomeScreen(username: data['username'] ?? input)));
              return;
            }
          }
        }
      }

      // 2. CHECK USERS
      final usersData = await DatabaseHelper.getData("users");
      if (usersData != null && usersData is Map) {
        for (var key in usersData.keys) {
          final data = usersData[key];
          if (data['email'] == input || data['username'] == input) {
            if (data['password'] == passwordInput) {
              if (data['isVerified'] != true) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account not verified.')));
                return;
              }
              await SessionManager.saveSession(key, data['username'] ?? data['firstName'], data['email']);
              await _registerDevice(key);
              if (!mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => UsersWelcomeScreen(username: data['username'] ?? data['firstName'], userId: key)));
              return;
            }
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid credentials')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goRegister() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
            ),
          ),
          child: Center(
            child: ResponsiveConstraints(
              maxWidth: 500,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/DVC.png', 
                      height: ResponsiveLayout.isMobile(context) ? 120 : 160,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Icon(Icons.pets, size: 100, color: Colors.white)
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'DOCLOY VETERINARY CLINIC',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: ResponsiveLayout.isMobile(context) ? 22 : 28,
                        fontWeight: FontWeight.bold, 
                        color: Colors.white, 
                        shadows: const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(2, 2))]
                      ),
                    ),
                    const SizedBox(height: 32),
                    Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveLayout.isMobile(context) ? 32 : 48, 
                          horizontal: 24
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Email/Username',
                                prefixIcon: const Icon(Icons.person, color: Color(0xFFB8860B)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock, color: Color(0xFFB8860B)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const ForgotPasswordRequestScreen()),
                                ),
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(color: Color(0xFFB8860B), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF8A6E2F), Color(0xFFB8860B)]),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16)),
                                child: _isLoading 
                                    ? const CircularProgressIndicator(color: Colors.white) 
                                    : const Text('LOGIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                            ),
                            if (_canCheckBiometrics) ...[
                              const SizedBox(height: 15),
                              Text(
                                'Login as $_lastUsername?',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              IconButton(
                                icon: const Icon(Icons.fingerprint, size: 50, color: Color(0xFFB8860B)),
                                onPressed: _handleFingerprintLogin,
                              ),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("Don't have an account?"),
                                TextButton(onPressed: _goRegister, child: const Text('Register', style: TextStyle(color: Color(0xFFB8860B), fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
