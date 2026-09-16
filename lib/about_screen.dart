import 'package:flutter/material.dart';
import 'widgets/gold_blobs_background.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // App Logo
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryGold.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Image.asset(
                    'assets/icon/DVC.png',
                    height: 120,
                    errorBuilder: (c, e, s) => Icon(Icons.pets, size: 100, color: primaryGold),
                  ),
                ),

                const SizedBox(height: 20),

                // App Name
                Text(
                  "DocLoy Vet App",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: darkGold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 8),

                // Version Number - shortly below app name
                Text(
                  "Version 1.0.0.1",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const Spacer(flex: 3),

                // Copyright Info at the bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Text(
                    "© 2026 DocLoy Veterinary Clinic",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
