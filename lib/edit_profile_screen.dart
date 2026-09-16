import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'cloudinary_service.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';
import 'widgets/marquee_text.dart';

class EditProfileScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;

  const EditProfileScreen({super.key, required this.userId, this.isAdmin = false});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _database = FirebaseDatabase.instance.ref();
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;

  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    String path = widget.isAdmin ? "admins/${widget.userId}" : "users/${widget.userId}";
    final snapshot = await _database.child(path).get();
    if (snapshot.exists) {
      setState(() {
        _userData = Map<String, dynamic>.from(snapshot.value as Map);
        _isLoading = false;
      });
    }
  }

  Future<void> _updateField(String field, String value) async {
    String path = widget.isAdmin ? "admins/${widget.userId}" : "users/${widget.userId}";
    await _database.child(path).update({field: value});
    _fetchUserData();
  }

  void _showEditBottomSheet(String title, String field, String initialValue) {
    final controller = TextEditingController(text: initialValue);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ResponsiveConstraints(
        maxWidth: 500,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Edit $title", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    suffixIcon: IconButton(icon: const Icon(Icons.cancel_outlined), onPressed: () => controller.clear()),
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    _updateField(field, controller.text.trim());
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: LinearGradient(colors: [darkGold, lightGold, primaryGold]),
                    ),
                    child: const Center(child: Text("Save", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updating profile picture...')));
    String? imageUrl = await CloudinaryService.uploadImage(File(image.path));
    if (imageUrl != null) {
      await _updateField('profileImage', imageUrl);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: Center(
            child: ResponsiveConstraints(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, size: 30), onPressed: () => Navigator.pop(context)),
                        const Text("Edit Profile", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickAndUploadImage,
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: _userData['profileImage'] != null ? NetworkImage(_userData['profileImage']) : null,
                                  child: _userData['profileImage'] == null ? const Icon(Icons.person, size: 60, color: Colors.grey) : null,
                                ),
                                const SizedBox(height: 8),
                                const Text("Tap to upload or change", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          _buildInfoBox(widget.isAdmin ? [
                            _buildProfileItem("Username", _userData['username'] ?? '', () => _showEditBottomSheet("Username", "username", _userData['username'] ?? '')),
                            _buildProfileItem("Doctor Name", _userData['dvmName'] ?? 'Not set', () => _showEditBottomSheet("Doctor Name", "dvmName", _userData['dvmName'] ?? '')),
                            _buildProfileItem("License No.", _userData['licNo'] ?? 'Not set', () => _showEditBottomSheet("License No.", "licNo", _userData['licNo'] ?? '')),
                            _buildProfileItem("PTR No.", _userData['ptrNo'] ?? 'Not set', () => _showEditBottomSheet("PTR No.", "ptrNo", _userData['ptrNo'] ?? '')),
                            _buildProfileItem("Facebook", _userData['facebook'] ?? 'Not set', () => _showEditBottomSheet("Facebook Link", "facebook", _userData['facebook'] ?? ''), useMarquee: true),
                            _buildProfileItem("Messenger", _userData['messenger'] ?? 'Not set', () => _showEditBottomSheet("Messenger Link", "messenger", _userData['messenger'] ?? ''), useMarquee: true),
                            _buildProfileItem("Phone", _maskInfo(_userData['contactNumber']), null, isNav: true),
                            _buildProfileItem("Email", _maskInfo(_userData['email']), null, isNav: true),
                          ] : [
                            _buildProfileItem("First Name", _userData['firstName'] ?? '', () => _showEditBottomSheet("First Name", "firstName", _userData['firstName'] ?? '')),
                            _buildProfileItem("MiddleName", _userData['middleName'] ?? '', () => _showEditBottomSheet("Middle Name", "middleName", _userData['middleName'] ?? '')),
                            _buildProfileItem("LastName", _userData['lastName'] ?? '', () => _showEditBottomSheet("Last Name", "lastName", _userData['lastName'] ?? '')),
                            _buildProfileItem("Suffix", _userData['suffix'] ?? 'None', () => _showEditBottomSheet("Suffix", "suffix", _userData['suffix'] ?? '')),
                            _buildProfileItem("Phone", _maskInfo(_userData['contactNumber']), null, isNav: true),
                            _buildProfileItem("Email", _maskInfo(_userData['email']), null, isNav: true),
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

  Widget _buildInfoBox(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold, width: 2),
        color: Colors.white,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildProfileItem(String label, String value, VoidCallback? onTap, {bool isNav = false, bool useMarquee = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Expanded(
              child: useMarquee
                  ? MarqueeText(
                      text: value,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.right,
                    )
                  : Text(
                      value,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 24),
          ],
        ),
      ),
    );
  }

  String _maskInfo(String? info) {
    if (info == null || info.isEmpty) return "N/A";
    if (info.contains('@')) {
      // email: daxxxxxxxxial.com
      var parts = info.split('@');
      var user = parts[0];
      if (user.length > 2) return "${user.substring(0, 2)}xxxxxxxx.${parts[1].split('.').last}";
      return info;
    }
    // phone: 09xxxxxxx650
    if (info.length > 5) return "${info.substring(0, 2)}xxxxxxx${info.substring(info.length - 3)}";
    return info;
  }
}
