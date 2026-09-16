import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_profile_screen.dart';
import 'account_update_screens.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class AccountSecurityScreen extends StatefulWidget {
  final String userId;
  final String username;
  final bool isAdmin;

  const AccountSecurityScreen({
    super.key, 
    required this.userId, 
    required this.username,
    this.isAdmin = false,
  });

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _isFingerprintEnabled = false;
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
    _loadFingerprintPreference();
  }

  Future<void> _loadFingerprintPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFingerprintEnabled = prefs.getBool('fingerprint_enabled_${widget.userId}') ?? false;
    });
  }

  Future<void> _toggleFingerprint(bool value) async {
    if (!value) {
      // Show Disable Dialog (Pic 2)
      bool? confirm = await showDialog(
        context: context,
        builder: (context) => ResponsiveConstraints(
        maxWidth: 400,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Disable Fingerprint Authentication?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: const Text("Are you sure to disable? Fingerprint Authentication is faster and more secure"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: Colors.black))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
      );

      if (confirm == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('fingerprint_enabled_${widget.userId}', false);
        setState(() => _isFingerprintEnabled = false);
      }
    } else {
      // Navigate to Setup (Pic 11)
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FingerprintSetupScreen(userId: widget.userId, onEnabled: () {
          setState(() => _isFingerprintEnabled = true);
        })),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: Center(
            child: ResponsiveConstraints(
              maxWidth: 800,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, size: 30), onPressed: () => Navigator.pop(context)),
                        const Text("Account & Security", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 10, bottom: 10),
                            child: Text("Account", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          _buildSectionContainer([
                            _buildMenuItem("My Profile", Icons.chevron_right, () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => EditProfileScreen(userId: widget.userId, isAdmin: widget.isAdmin)));
                            }),
                            _buildMenuItem("Phone", Icons.chevron_right, () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => ChangePhoneScreen(userId: widget.userId, isAdmin: widget.isAdmin)));
                            }),
                            _buildMenuItem("Email", Icons.chevron_right, () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => ChangeEmailScreen(userId: widget.userId, isAdmin: widget.isAdmin)));
                            }),
                            _buildMenuItem("Change Password", Icons.chevron_right, () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => SecurityCheckScreen(userId: widget.userId, isAdmin: widget.isAdmin)));
                            }),
                            _buildFingerprintToggle(),
                          ]),
                          const SizedBox(height: 30),
                          const Padding(
                            padding: EdgeInsets.only(left: 10, bottom: 10),
                            child: Text("Security", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          _buildSectionContainer([
                            _buildMenuItem("Manage Login Device", Icons.chevron_right, () {
                              Navigator.push(context, MaterialPageRoute(builder: (c) => ManageLoginDeviceScreen(userId: widget.userId, isAdmin: widget.isAdmin)));
                            }, subtitle: "Review the devices that you have logged in docloy vet app account"),
                          ]),
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
    );
  }

  Widget _buildSectionContainer(List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold, width: 2),
        color: Colors.white,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem(String title, IconData icon, VoidCallback onTap, {String? subtitle}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]
                ],
              ),
            ),
            Icon(icon, size: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildFingerprintToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text("Fingerprint Authentication", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(
                value: _isFingerprintEnabled,
                onChanged: _toggleFingerprint,
                activeColor: primaryGold,
              ),
            ],
          ),
          const Text(
            "Your Fingerprint data is on your device and docloy vet app does not store it",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
