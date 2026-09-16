import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'product_reservation_screen.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class UserOrdersScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? fullName;

  const UserOrdersScreen({
    super.key, 
    required this.userId, 
    required this.username,
    this.fullName,
  });

  @override
  State<UserOrdersScreen> createState() => _UserOrdersScreenState();
}

class _UserOrdersScreenState extends State<UserOrdersScreen> {
  String _activeFilter = "Default";
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);
  final _formatter = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final database = FirebaseDatabase.instance.ref();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My reservations', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.black),
            onSelected: (value) => setState(() => _activeFilter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: "Default", child: Text("Upcoming & Reserved")),
              const PopupMenuItem(value: "Completed", child: Text("Completed/Received")),
              const PopupMenuItem(value: "Cancelled", child: Text("Cancelled")),
              const PopupMenuItem(value: "Rejected", child: Text("Rejected")),
            ],
          ),
        ],
      ),
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: Center(
          child: ResponsiveConstraints(
            maxWidth: 900,
            child: Column(
              children: [
                const SizedBox(height: 10),
                if (_activeFilter != "Default")
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Chip(
                          label: Text("Filter: $_activeFilter", style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setState(() => _activeFilter = "Default"),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          backgroundColor: lightGold.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder(
                    stream: database.child('product_reservations').orderByChild('userId').equalTo(widget.userId).onValue,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                        Map data = snapshot.data!.snapshot.value as Map;
                        List<MapEntry<dynamic, dynamic>> allOrders = data.entries.map((e) => MapEntry(e.key, e.value)).toList();
                        
                        allOrders.sort((a, b) => (b.value['timestamp'] ?? 0).compareTo(a.value['timestamp'] ?? 0));

                        if (_activeFilter == "Default") {
                          var upcoming = allOrders.where((e) {
                            String s = e.value['status'] ?? '';
                            return s == "To Pick Up" || s == "Accepted";
                          }).toList();
                          var reserved = allOrders.where((e) => e.value['status'] == "Reserved").toList();

                          if (upcoming.isEmpty && reserved.isEmpty) {
                            return const Center(child: Text("No upcoming or reserved products."));
                          }

                          return ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            children: [
                              if (upcoming.isNotEmpty) ...[
                                _sectionHeader("Upcoming (To Pick Up)"),
                                ...upcoming.map((e) => _buildOrderCard(e.value, e.key)),
                              ],
                              if (reserved.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _sectionHeader("Reserved"),
                                ...reserved.map((e) => _buildOrderCard(e.value, e.key)),
                              ],
                              const SizedBox(height: 20),
                            ],
                          );
                        } else {
                          var filtered = allOrders.where((e) {
                            String s = e.value['status'] ?? '';
                            if (_activeFilter == "Completed") return s == "Received" || s == "Completed";
                            return s == _activeFilter;
                          }).toList();

                          if (filtered.isEmpty) {
                            return Center(child: Text("No $_activeFilter reservations."));
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              var order = filtered[index].value;
                              var orderId = filtered[index].key;
                              return _buildOrderCard(order, orderId);
                            },
                          );
                        }
                      }
                      return const Center(child: Text('No reservations yet.'));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            title,
            style: TextStyle(
              color: darkGold,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Divider(color: primaryGold.withOpacity(0.3), thickness: 1),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildOrderCard(dynamic order, String orderId) {
    String status = order['status'] ?? 'To Pick Up';
    Color statusColor = Colors.blue;
    if (status == 'Accepted') statusColor = const Color(0xFF2E7D32);
    if (status == 'Completed' || status == 'Received') statusColor = const Color(0xFF1565C0);
    if (status == 'Rejected') statusColor = const Color(0xFFB71C1C);
    if (status == 'Cancelled') statusColor = const Color(0xFF757575);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          const Positioned(top: 0, right: 0, child: Icon(Icons.shopping_cart, color: Colors.black, size: 28)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Transaction # ${orderId.toString().substring(orderId.length - 6).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text("Product name: ${order['productName']}", style: const TextStyle(fontSize: 14)),
              Text("Pick Up Date: ${order['pickupDate'] ?? 'N/A'}", style: const TextStyle(fontSize: 14)),
              Text("Price: ₱${_formatter.format((order['totalPrice'] ?? 0).round())}", style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _showProductDetails(order, orderId),
                      child: const Text("See details", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showProductDetails(dynamic order, String orderId) async {
    List<dynamic> items = order['items'] ?? [{
      'productName': order['productName'],
      'quantity': order['quantity'] ?? 1,
      'totalPrice': order['totalPrice'],
    }];

    String clientName = order['clientName'] ?? widget.username;
    final userSnap = await FirebaseDatabase.instance.ref().child('users/${order['userId']}').get();
    if (userSnap.exists) {
      Map userData = userSnap.value as Map;
      String fName = userData['firstName'] ?? '';
      String mName = (userData['middleName'] != null && userData['middleName'].toString().isNotEmpty) 
          ? "${userData['middleName'].toString()[0].toUpperCase()}." 
          : "";
      String lName = userData['lastName'] ?? '';
      String fullName = [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
      if (fullName.isNotEmpty) clientName = fullName;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => ResponsiveConstraints(
        maxWidth: 500,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: primaryGold, width: 3),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Product Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  _detailRow("Transaction # :", orderId.toString().substring(orderId.length - 6).toUpperCase()),
                  _detailRow("Client :", clientName),
                  
                  const Divider(),
                  ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${item['productName']} (x${item['quantity']})", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              if (item['variationName'] != null)
                                Text(item['variationName'], style: TextStyle(fontSize: 11, color: primaryGold, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Text("₱${_formatter.format((item['totalPrice'] ?? 0).round())}", style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  )),
                  const Divider(),

                  _detailRow("Total Price :", "₱${_formatter.format((order['totalPrice'] ?? 0).round())}"),
                  _detailRow("Date :", order['pickupDate'] ?? 'N/A'),
                  _detailRow("Pick Up Time :", order['pickupTime'] ?? 'N/A'),
                  
                  if (order['status'] == 'Rejected' && order['rejectionReason'] != null)
                    _detailRow("Reason for Rejection :", order['rejectionReason'], color: Colors.red),

                  if (order['status'] == 'Received' || order['status'] == 'Completed') ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const Center(
                      child: Text(
                        "For Medical Support & Follow-ups Please Contact Us!",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder(
                      future: FirebaseDatabase.instance.ref().child('admins').limitToFirst(1).get(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          Map admin = (snapshot.data!.value as Map).values.first;
                          return Column(
                            children: [
                              _contactRow(
                                Icons.phone, 
                                admin['contactNumber'] ?? 'N/A',
                                onTap: admin['contactNumber'] != null 
                                  ? () => _launchURL("tel:${admin['contactNumber'].toString().replaceAll(RegExp(r'[^0-9+]'), '')}") 
                                  : null,
                              ),
                              _contactRow(
                                Icons.facebook, 
                                "Facebook Page",
                                iconColor: const Color(0xFF1877F2),
                                onTap: admin['facebook'] != null ? () => _launchURL(admin['facebook']) : null,
                              ),
                              _contactRow(
                                Icons.chat_bubble, 
                                "Chat on Messenger",
                                iconColor: const Color(0xFF0084FF),
                                onTap: admin['messenger'] != null ? () => _launchURL(admin['messenger']) : null,
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const Divider(),
                  ],

                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (order['status'] == 'Reserved' || order['status'] == 'Accepted' || order['status'] == 'To Pick Up')
                        _actionButton(Icons.block, "Cancel", Colors.red, () => _confirmAction("cancel", order, orderId)),
                      if (order['status'] == 'Cancelled' || order['status'] == 'Rejected')
                        _actionButton(Icons.calendar_month, "Reschedule", Colors.indigo, () => _confirmAction("reschedule", order, orderId)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
                        ),
                      ),
                      child: const Center(child: Text("Close", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
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

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: color != null ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $urlString')),
        );
      }
    }
  }

  Widget _contactRow(IconData icon, String value, {Color? iconColor, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: (iconColor ?? primaryGold).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: (iconColor ?? primaryGold).withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: iconColor ?? primaryGold),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  value, 
                  style: TextStyle(
                    fontSize: 13, 
                    color: Colors.blueGrey.shade800, 
                    fontWeight: FontWeight.w500,
                    decoration: onTap != null ? TextDecoration.underline : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              ),
              if (onTap != null)
                Icon(Icons.open_in_new, size: 14, color: (iconColor ?? primaryGold).withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _confirmAction(String action, dynamic order, String orderId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Transaction?'),
        content: Text('Are you sure you want to $action this reservation?'),
        actions: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(c, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: const Center(
                      child: Text("No", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(c, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: const Center(
                      child: Text("Yes", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = FirebaseDatabase.instance.ref();
      if (action == "cancel") {
        await db.child('product_reservations/$orderId').update({'status': 'Cancelled'});
        // Return stock for all items
        List<dynamic> items = order['items'] ?? [{
          'productName': order['productName'],
          'baseName': order['baseName'],
          'variationName': order['variationName'],
          'quantity': order['quantity'] ?? 1,
        }];

        for (var item in items) {
          final baseName = item['baseName'] ?? item['productName'];
          final productSnap = await db.child('products').orderByChild('name').equalTo(baseName).get();
          if (productSnap.exists) {
            String pKey = productSnap.children.first.key!;
            Map pData = productSnap.children.first.value as Map;

            if (item['variationName'] != null && pData['variations'] != null) {
              var vars = pData['variations'];
              if (vars is List) {
                for (int i = 0; i < vars.length; i++) {
                  if (vars[i]['name'] == item['variationName']) {
                    vars[i]['quantity'] = (vars[i]['quantity'] ?? 0) + (item['quantity'] as int);
                    break;
                  }
                }
              } else if (vars is Map) {
                for (var key in vars.keys) {
                  if (vars[key]['name'] == item['variationName']) {
                    vars[key]['quantity'] = (vars[key]['quantity'] ?? 0) + (item['quantity'] as int);
                    break;
                  }
                }
              }
              await db.child('products/$pKey').update({'variations': vars});
            } else {
              int currentStock = pData['quantity'] ?? 0;
              await db.child('products/$pKey').update({'quantity': currentStock + (item['quantity'] as int)});
            }
          }
        }
        
        if (mounted) {
          Navigator.pop(context); // Close details dialog
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reservation Cancelled")));
        }
      } else {
        // Reschedule
        if (mounted) {
          Navigator.pop(context); // Close details dialog
          
          List<Map<String, dynamic>> productsToReschedule = [];
          if (order['items'] != null) {
            for (var item in order['items']) {
              productsToReschedule.add({
                'productName': item['productName'],
                'baseName': item['baseName'],
                'variationName': item['variationName'],
                'quantity': item['quantity'],
                'price': item['unitPrice'],
                'description': '',
                'imageUrl': null,
              });
            }
          } else {
            productsToReschedule.add({
              'productName': order['productName'],
              'baseName': order['baseName'],
              'variationName': order['variationName'],
              'quantity': order['quantity'] ?? 1,
              'price': (order['totalPrice'] / (order['quantity'] ?? 1)).toDouble(),
              'description': "",
              'imageUrl': null,
            });
          }

          Navigator.push(context, MaterialPageRoute(builder: (c) => ProductReservationScreen(
            userId: widget.userId,
            username: widget.username,
            fullName: widget.fullName,
            initialProducts: productsToReschedule,
          )));
        }
      }
    }
  }
}
