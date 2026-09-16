import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';
import 'users_welcome_screen.dart';
import 'notification_service.dart';
import 'session_manager.dart';
import 'database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await NotificationService.init();
    }
  } catch (e) {
    debugPrint("Firebase/Notification init error: $e");
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Docloy Vet App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB8860B)),
        useMaterial3: true,
        primaryColor: const Color(0xFFB8860B),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Color(0xFFB8860B),
          foregroundColor: Colors.white,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToLogin();
  }

  void _navigateToLogin() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString(SessionManager.keyUserId);
    String? username = prefs.getString(SessionManager.keyUsername);

    if (userId != null && username != null) {
      String deviceId = await SessionManager.getDeviceId();
      bool isAdmin = await SessionManager.isAdmin();
      String path = isAdmin ? "admins" : "users";

      try {
        // GUMAGAMIT NA NG DATABASE HELPER PARA LIGTAS SA WINDOWS
        final sessionData = await DatabaseHelper.getData("$path/$userId/devices/$deviceId");

        if (sessionData != null) {
          if (!mounted) return;
          if (isAdmin) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => WelcomeScreen(username: username)));
          } else {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UsersWelcomeScreen(username: username, userId: userId)));
          }
          return;
        } else {
          await SessionManager.clearSession();
        }
      } catch (e) {
        debugPrint("Session check error: $e");
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB8860B), Color(0xFFFBDB83), Color(0xFF8A6E2F)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/DVC.png',
                height: 150,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, size: 100, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'DOCLOY VETERINARY CLINIC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 30),
              const CupertinoActivityIndicator(radius: 12, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
