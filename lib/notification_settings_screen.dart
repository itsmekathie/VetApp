import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final String userId;
  const NotificationSettingsScreen({super.key, required this.userId});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
  final Color lightGold = const Color(0xFFFBDB83);

  final _database = FirebaseDatabase.instance.ref();
  
  bool _isPushOn = true;
  bool _isPromotionOn = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // 1. Try to load from Local Cache (SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPushOn = prefs.getBool('${widget.userId}_push_enabled') ?? true;
      _isPromotionOn = prefs.getBool('${widget.userId}_promotions_enabled') ?? true;
    });

    // 2. Sync with Firebase to ensure accuracy
    final snapshot = await _database.child('users/${widget.userId}/settings/notifications').get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      setState(() {
        _isPushOn = data['push_enabled'] ?? true;
        _isPromotionOn = data['promotions_enabled'] ?? true;
      });
      // Update local cache
      await prefs.setBool('${widget.userId}_push_enabled', _isPushOn);
      await prefs.setBool('${widget.userId}_promotions_enabled', _isPromotionOn);
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
                    padding: const EdgeInsets.only(left: 10, top: 10),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 30),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          "Notification Settings",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildSettingItem(
                          "Push Notifications",
                          _isPushOn ? "On" : "Off",
                          () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PushNotificationDetailScreen(userId: widget.userId),
                              ),
                            );
                            _loadSettings();
                          },
                        ),
                        const Divider(),
                        _buildSettingItem(
                          "In-App Promotion Notification",
                          _isPromotionOn ? "On" : "Off",
                          () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PromotionNotificationDetailScreen(userId: widget.userId),
                              ),
                            );
                            _loadSettings();
                          },
                        ),
                      ],
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

  Widget _buildSettingItem(String title, String status, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right, size: 28),
        ],
      ),
    );
  }
}

class PushNotificationDetailScreen extends StatefulWidget {
  final String userId;
  const PushNotificationDetailScreen({super.key, required this.userId});

  @override
  State<PushNotificationDetailScreen> createState() => _PushNotificationDetailScreenState();
}

class _PushNotificationDetailScreenState extends State<PushNotificationDetailScreen> {
  final _database = FirebaseDatabase.instance.ref();
  bool _isPushOn = true;
  bool _isOrderOn = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPushOn = prefs.getBool('${widget.userId}_push_enabled') ?? true;
      _isOrderOn = prefs.getBool('${widget.userId}_order_updates_enabled') ?? true;
    });

    final snapshot = await _database.child('users/${widget.userId}/settings/notifications').get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      setState(() {
        _isPushOn = data['push_enabled'] ?? true;
        _isOrderOn = data['order_updates_enabled'] ?? true;
      });
      await prefs.setBool('${widget.userId}_push_enabled', _isPushOn);
      await prefs.setBool('${widget.userId}_order_updates_enabled', _isOrderOn);
    }
  }

  Future<void> _togglePush(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${widget.userId}_push_enabled', value);
    await _database.child('users/${widget.userId}/settings/notifications').update({
      'push_enabled': value,
    });
    setState(() => _isPushOn = value);
  }

  Future<void> _toggleOrder(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${widget.userId}_order_updates_enabled', value);
    await _database.child('users/${widget.userId}/settings/notifications').update({
      'order_updates_enabled': value,
    });
    setState(() => _isOrderOn = value);
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
              maxWidth: 700,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 10),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 30),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          "Push Notifications",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text("Push Notification", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                    value: _isPushOn,
                    activeColor: const Color(0xFFB8860B),
                    onChanged: _togglePush,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text("Order", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                    subtitle: const Text("Latest updates on all order status"),
                    value: _isOrderOn,
                    activeColor: const Color(0xFFB8860B),
                    onChanged: _toggleOrder,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PromotionNotificationDetailScreen extends StatefulWidget {
  final String userId;
  const PromotionNotificationDetailScreen({super.key, required this.userId});

  @override
  State<PromotionNotificationDetailScreen> createState() => _PromotionNotificationDetailScreenState();
}

class _PromotionNotificationDetailScreenState extends State<PromotionNotificationDetailScreen> {
  final _database = FirebaseDatabase.instance.ref();
  bool _isPromotionOn = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPromotionOn = prefs.getBool('${widget.userId}_promotions_enabled') ?? true;
    });

    final snapshot = await _database.child('users/${widget.userId}/settings/notifications').get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      setState(() {
        _isPromotionOn = data['promotions_enabled'] ?? true;
      });
      await prefs.setBool('${widget.userId}_promotions_enabled', _isPromotionOn);
    }
  }

  Future<void> _togglePromotion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${widget.userId}_promotions_enabled', value);
    await _database.child('users/${widget.userId}/settings/notifications').update({
      'promotions_enabled': value,
    });
    setState(() => _isPromotionOn = value);
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
              maxWidth: 700,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 10),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 30),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          "In-App Promotion",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text(
                      "Receive promotion notification using docloy vet app",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    value: _isPromotionOn,
                    activeColor: const Color(0xFFB8860B),
                    onChanged: _togglePromotion,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
