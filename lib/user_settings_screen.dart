import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'session_manager.dart';
import 'package:firebase_database/firebase_database.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

import 'account_security_screen.dart';
import 'pet_management_screens.dart';
import 'notification_settings_screen.dart';
import 'about_screen.dart';
import 'policies_screen.dart';
import 'rate_us_screen.dart';
// import 'package:firebase_auth/firebase_auth.dart';

class UserSettingsScreen extends StatelessWidget {
  final String userId;
  final String username;

  const UserSettingsScreen({super.key, required this.userId, required this.username});

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 10),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: Center(
                  child: ResponsiveConstraints(
                    maxWidth: 900,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          _buildSettingsSection("Account", [
                            _buildSettingsItem("Account & Security", () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => AccountSecurityScreen(userId: userId, username: username)));
                            }),
                            _buildSettingsItem("Pet Informations", () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => PetListScreen(userId: userId)));
                            }),
                          ]),
                          const SizedBox(height: 25),
                          _buildSettingsSection("Settings", [
                            _buildSettingsItem("Notification Settings", () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => NotificationSettingsScreen(userId: userId)));
                            }),
                            // _buildSettingsItem("Languages", () {}),
                          ]),
                          const SizedBox(height: 25),
                          _buildSettingsSection("Support", [
                            _buildSettingsItem("Doc Loy Vet App Policies", () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => const PoliciesScreen()));
                            }),
                            _buildSettingsItem("Rate Us!", () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => RateUsScreen(userId: userId, username: username)));
                            }),
                            _buildSettingsItem("About", () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => const AboutScreen()));
                            }),
                            // _buildSettingsItem("Request account deletion", () {}),
                          ]),
                          const SizedBox(height: 50),
                          // Log Out Button
                          _buildLogoutButton(context),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // Show confirmation dialog
        bool? confirm = await showDialog(
          context: context,
          builder: (context) => ResponsiveConstraints(
            maxWidth: 400,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Log Out", style: TextStyle(fontWeight: FontWeight.bold)),
              content: const Text("Are you sure you want to log out?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: Colors.black))),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Log Out", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        );

        if (confirm == true) {
          // 1. Remove device from Firebase to prevent auto-login
          String deviceId = await SessionManager.getDeviceId();
          await FirebaseDatabase.instance.ref().child("users").child(userId).child("devices").child(deviceId).remove();
          
          // 2. Clear local session preference
          await SessionManager.clearSession();
          
          if (!context.mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (c) => LoginScreen()),
            (route) => false,
          );
        }
      },
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: const Center(
          child: Text(
            "Log Out",
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _buildSettingsItem(String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.chevron_right, size: 28),
          ],
        ),
      ),
    );
  }
}
