import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'widgets/gold_blobs_background.dart';

class AdminNotificationCenter extends StatefulWidget {
  final String adminKey;
  const AdminNotificationCenter({super.key, required this.adminKey});

  @override
  State<AdminNotificationCenter> createState() => _AdminNotificationCenterState();
}

class _AdminNotificationCenterState extends State<AdminNotificationCenter> {
  final _database = FirebaseDatabase.instance.ref();
  bool _isPushEnabled = true;
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPushEnabled = prefs.getBool('admin_push_enabled') ?? true;
    });

    final snapshot = await _database.child('admins/${widget.adminKey}/settings/notifications').get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      setState(() {
        _isPushEnabled = data['push_enabled'] ?? true;
      });
      await prefs.setBool('admin_push_enabled', _isPushEnabled);
    }
  }

  Future<void> _togglePush(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('admin_push_enabled', value);
    await _database.child('admins/${widget.adminKey}/settings/notifications').update({
      'push_enabled': value,
    });
    setState(() => _isPushEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Notification Center"),
        backgroundColor: primaryGold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GoldBlobsBackground(
        child: Column(
          children: [
            // Settings Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [darkGold, primaryGold]),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Push Notifications",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: _isPushEnabled,
                        activeColor: Colors.white,
                        activeTrackColor: lightGold,
                        onChanged: _togglePush,
                      ),
                    ],
                  ),
                  const Text(
                    "Enable this to receive sound alerts for new requests even when the app is in background.",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.all(15.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Activity Log", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),

            Expanded(
              child: StreamBuilder(
                stream: _database.child('admin_notifications').limitToLast(20).onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                    Map data = snapshot.data!.snapshot.value as Map;
                    var logs = data.entries.toList();
                    logs.sort((a, b) => b.value['timestamp'].compareTo(a.value['timestamp']));

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      itemCount: logs.length,
                      separatorBuilder: (c, i) => const Divider(),
                      itemBuilder: (context, index) {
                        var log = logs[index].value;
                        return _buildLogItem(log);
                      },
                    );
                  }
                  return const Center(child: Text("No recent activities."));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(dynamic log) {
    IconData icon = Icons.notifications;
    Color iconColor = primaryGold;
    String type = log['type'] ?? '';

    if (type.contains('Booking')) {
      icon = Icons.calendar_month;
      iconColor = Colors.blue;
    } else if (type.contains('Reservation')) {
      icon = Icons.shopping_bag;
      iconColor = Colors.orange;
    } else if (type.contains('Stock')) {
      icon = Icons.warning;
      iconColor = Colors.red;
    }

    DateTime date = DateTime.fromMillisecondsSinceEpoch(log['timestamp'] ?? 0);
    String time = DateFormat('hh:mm a').format(date);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withOpacity(0.1),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(log['title'] ?? 'Update', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(log['message'] ?? ''),
      trailing: Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }
}
