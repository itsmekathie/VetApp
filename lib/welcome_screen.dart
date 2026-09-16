import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'admin_appointments_screen.dart';
import 'admin_products_screen.dart';
import 'admin_services_screen.dart';
import 'admin_promotions_screen.dart';
import 'admin_notification_center.dart';
import 'admin_ratings_screen.dart';
import 'admin_settings_screen.dart';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'cloudinary_service.dart';
import 'notification_service.dart';
import 'detailed_analytics_screen.dart';
import 'create_prescription_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/gold_blobs_background.dart';
import 'widgets/marquee_text.dart';

class WelcomeScreen extends StatefulWidget {
  final String username;
  const WelcomeScreen({super.key, required this.username});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  int _selectedIndex = 0;
  final _database = FirebaseDatabase.instance.ref();
  Map<String, dynamic> _adminData = {};
  String? _adminKey;
  
  // Listeners for notifications
  StreamSubscription<DatabaseEvent>? _apptSubscription;
  StreamSubscription<DatabaseEvent>? _orderSubscription;
  StreamSubscription<DatabaseEvent>? _changeSubscription;
  StreamSubscription<DatabaseEvent>? _stockSubscription;
  StreamSubscription<DatabaseEvent>? _ratingSubscription;
  bool _isInitialLoad = true;
  final Map<String, String> _lastStatus = {};
  final Map<String, int> _lastStock = {};

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
    _setupNotificationListeners();
  }

  @override
  void dispose() {
    _apptSubscription?.cancel();
    _orderSubscription?.cancel();
    _changeSubscription?.cancel();
    _stockSubscription?.cancel();
    _ratingSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListeners() {
    Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isInitialLoad = false);
    });

    // 1. New Appointment Requests
    _apptSubscription = _database.child('appointments').onChildAdded.listen((event) async {
      if (_isInitialLoad || !mounted) return;
      final data = event.snapshot.value as Map?;
      if (data != null && data['status'] == 'Pending') {
        String serviceNames = "Service";
        if (data['services'] != null && data['services'] is List) {
          serviceNames = (data['services'] as List).map((s) => s['name'] ?? 'Service').join(', ');
        } else if (data['serviceName'] != null) {
          serviceNames = data['serviceName'];
        }

        String msg = "${data['username']} booked for $serviceNames";
        _showTopNotification("New Appointment!", msg, const AdminAppointmentsScreen());
        
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('admin_push_enabled') ?? true) {
          NotificationService.showNotification("New Appointment Request", msg);
        }

        // Log to Activity Log
        _database.child('admin_notifications').push().set({
          'type': 'Booking',
          'title': 'New Appointment Request',
          'message': msg,
          'timestamp': ServerValue.timestamp,
        });
      }
    });

    // 2. New Product Reservations
    _orderSubscription = _database.child('product_reservations').onChildAdded.listen((event) async {
      if (_isInitialLoad || !mounted) return;
      final data = event.snapshot.value as Map?;
      if (data != null && data['status'] == 'Reserved') {
        String msg = "${data['username']} reserved ${data['productName']}";
        _showTopNotification("New Order!", msg, const AdminAppointmentsScreen());

        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('admin_push_enabled') ?? true) {
          NotificationService.showNotification("New Product Reservation", msg);
        }

        // Log to Activity Log
        _database.child('admin_notifications').push().set({
          'type': 'Reservation',
          'title': 'New Product Reservation',
          'message': msg,
          'timestamp': ServerValue.timestamp,
        });
      }
    });

    // 3. Status Changes (Cancellations)
    _changeSubscription = _database.onValue.listen((event) async {
      if (!mounted || event.snapshot.value == null) return;
      
      Map root = event.snapshot.value as Map;
      final prefs = await SharedPreferences.getInstance();
      bool pushEnabled = prefs.getBool('admin_push_enabled') ?? true;
      
      // Check Appointments for Cancellations
      if (root['appointments'] != null) {
        Map appts = root['appointments'] as Map;
        appts.forEach((key, val) {
          String status = val['status'] ?? '';
          if (!_isInitialLoad && _lastStatus.containsKey(key) && _lastStatus[key] != status && status == 'Cancelled') {
             String serviceNames = "Service";
             if (val['services'] != null && val['services'] is List) {
               serviceNames = (val['services'] as List).map((s) => s['name'] ?? 'Service').join(', ');
             } else if (val['serviceName'] != null) {
               serviceNames = val['serviceName'];
             }
             String msg = "${val['username']} cancelled their appointment for $serviceNames";
             if (pushEnabled) {
                NotificationService.showNotification("Booking Cancelled", msg);
             }
             _database.child('admin_notifications').push().set({
               'type': 'Booking',
               'title': 'Booking Cancelled',
               'message': msg,
               'timestamp': ServerValue.timestamp,
             });
          }
          _lastStatus[key] = status;
        });
      }

      // Check Reservations for Cancellations
      if (root['product_reservations'] != null) {
        Map res = root['product_reservations'] as Map;
        res.forEach((key, val) {
          String status = val['status'] ?? '';
          if (!_isInitialLoad && _lastStatus.containsKey(key) && _lastStatus[key] != status && status == 'Cancelled') {
             String msg = "${val['username']} cancelled their reservation for ${val['productName']}";
             if (pushEnabled) {
                NotificationService.showNotification("Reservation Cancelled", msg);
             }
             _database.child('admin_notifications').push().set({
               'type': 'Reservation',
               'title': 'Reservation Cancelled',
               'message': msg,
               'timestamp': ServerValue.timestamp,
             });
          }
          _lastStatus[key] = status;
        });
      }
    });

    // 4. Low Stock Alerts
    _stockSubscription = _database.child('products').onValue.listen((event) async {
      if (!mounted || !event.snapshot.exists) return;
      
      Map data = event.snapshot.value as Map;
      final prefs = await SharedPreferences.getInstance();
      bool pushEnabled = prefs.getBool('admin_push_enabled') ?? true;

      data.forEach((prodKey, val) {
        String name = val['name'] ?? 'Product';
        
        if (val['variations'] != null) {
          var vars = val['variations'];
          List varList = (vars is List) ? vars : (vars is Map ? vars.values.toList() : []);
          
          for (int i = 0; i < varList.length; i++) {
            var v = varList[i];
            if (v == null) continue;
            int vQty = v['quantity'] ?? 0;
            String vName = v['name'] ?? 'Variation';
            String vKey = "${prodKey}_v$i";
            
            if (!_isInitialLoad && vQty < 5 && (!_lastStock.containsKey(vKey) || _lastStock[vKey]! >= 5)) {
              String msg = "$name ($vName) only has $vQty left!";
              if (pushEnabled) {
                NotificationService.showNotification("Low Stock Warning", msg);
              }
              _database.child('admin_notifications').push().set({
                'type': 'Stock',
                'title': 'Low Stock Warning',
                'message': msg,
                'timestamp': ServerValue.timestamp,
              });
            }
            _lastStock[vKey] = vQty;
          }
        } else {
          int qty = val['quantity'] ?? 0;
          if (!_isInitialLoad && qty < 5 && (!_lastStock.containsKey(prodKey) || _lastStock[prodKey]! >= 5)) {
            String msg = "$name only has $qty left!";
            if (pushEnabled) {
              NotificationService.showNotification("Low Stock Warning", msg);
            }
            _database.child('admin_notifications').push().set({
              'type': 'Stock',
              'title': 'Low Stock Warning',
              'message': msg,
              'timestamp': ServerValue.timestamp,
            });
          }
          _lastStock[prodKey] = qty;
        }
      });
    });

    // 5. User Ratings Alerts
    _ratingSubscription = _database.child('ratings').onChildAdded.listen((event) async {
      if (_isInitialLoad || !mounted) return;
      final data = event.snapshot.value as Map?;
      if (data != null) {
        String msg = "New rating from ${data['username'] ?? 'User'}: ${data['rating']} stars";
        _showTopNotification("New Rating Received!", msg, const AdminRatingsScreen());

        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('admin_push_enabled') ?? true) {
          NotificationService.showNotification("New User Feedback", msg);
        }

        _database.child('admin_notifications').push().set({
          'type': 'Rating',
          'title': 'New User Feedback',
          'message': msg,
          'timestamp': ServerValue.timestamp,
        });
      }
    });
  }

  void _showTopNotification(String title, String message, Widget destination) {
    OverlayState? overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 15,
        right: 15,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              overlayEntry.remove();
              Navigator.push(context, MaterialPageRoute(builder: (c) => destination));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8A6E2F), Color(0xFFB8860B)],
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => overlayEntry.remove(),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);
    Timer(const Duration(seconds: 5), () {
      if (overlayEntry.mounted) overlayEntry.remove();
    });
  }

  void _fetchAdminData() async {
    final snapshot = await _database.child('admins').get();
    if (snapshot.exists) {
      final admins = snapshot.value as Map;
      admins.forEach((key, value) {
        if (value['username'] == widget.username) {
          if (mounted) {
            setState(() {
              _adminKey = key;
              _adminData = Map<String, dynamic>.from(value);
            });
          }
        }
      });
    }
  }

  void _refreshAdminData() async {
    if (_adminKey == null) return;
    final snapshot = await _database.child('admins/$_adminKey').get();
    if (snapshot.exists) {
      if (mounted) {
        setState(() {
          _adminData = Map<String, dynamic>.from(snapshot.value as Map);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            DashboardTab(username: widget.username, adminKey: _adminKey ?? ''),
            SchedulesTab(adminData: _adminData, username: widget.username),
            const SalesTab(),
            ProfileTab(
              username: widget.username, 
              adminData: _adminData, 
              adminKey: _adminKey,
              onRefresh: _refreshAdminData,
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 70,
        decoration: const BoxDecoration(
          color: Colors.black,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -2),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(child: _buildNavItem(0, Icons.home, 'home')),
            Expanded(child: _buildNavItem(1, Icons.calendar_month, 'schedules')),
            Expanded(child: _buildNavItem(2, Icons.bar_chart, 'sales')),
            Expanded(child: _buildNavItem(3, Icons.person_outline, 'profile')),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 28),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }
}

// --- COMMON WIDGETS ---

class GoldenCard extends StatelessWidget {
  final Widget child;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const GoldenCard({super.key, required this.child, this.height, this.width, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        width: width,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
          ),
        ),
        child: child,
      ),
    );
  }
}

class OutlinedGoldCard extends StatelessWidget {
  final Widget child;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const OutlinedGoldCard({super.key, required this.child, this.height, this.width, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        width: width,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFB8860B), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: child,
      ),
    );
  }
}

void _showTransactionDetailsDialog(BuildContext context, dynamic item, Map<String, dynamic> adminData, String adminUsername, {bool isCompletion = true}) {
  final _formatter = NumberFormat('#,###');
  bool isProduct = item['type'] == 'Product';
  String id = item['id'].toString();
  final db = FirebaseDatabase.instance.ref();

  // Color coding
  String status = item['status'] ?? 'Reserved';
  Color statusColor = const Color(0xFFB8860B);
  if (status == 'Accepted') statusColor = const Color(0xFF2E7D32);
  if (status == 'Completed' || status == 'Received') statusColor = const Color(0xFF1565C0);
  if (status == 'Rejected') statusColor = const Color(0xFFB71C1C);
  if (status == 'Cancelled') statusColor = const Color(0xFF757575);

  // Controllers for Admin Input (Service)
  final treatmentCtrl = TextEditingController(text: item['inHouseTreatment'] ?? "");
  final treatmentPriceCtrl = TextEditingController(text: (item['inHousePrice'] ?? 0).toString());
  final labResultCtrl = TextEditingController(text: item['laboratoryResult'] ?? "");
  final prescriptionCtrl = TextEditingController(text: item['prescription'] ?? "");
  String? prescriptionUrl = item['prescriptionUrl'];

  String initialWeightString = "";
  if (item['weight'] != null) {
    initialWeightString = item['weight'].toString();
  } else if (item['petDetails'] != null) {
    if (item['petDetails'] is List) {
      initialWeightString = (item['petDetails'] as List)
          .map((p) => p['weight']?.toString() ?? "")
          .where((w) => w.isNotEmpty)
          .join(', ');
    } else if (item['petDetails'] is Map) {
      initialWeightString = item['petDetails']['weight']?.toString() ?? "";
    }
  }
  final weightCtrl = TextEditingController(text: initialWeightString);

  var pets = item['petDetails'];
  List<dynamic> petList = (pets == null) ? [] : (pets is List ? pets : [pets]);
  List<String> initialWeights = [];
  if (item['weight'] != null) {
    initialWeights = item['weight'].toString().split(',').map((s) => s.trim()).toList();
  }
  final List<TextEditingController> weightCtrls = List.generate(petList.length, (i) => TextEditingController(text: (i < initialWeights.length) ? initialWeights[i] : ''));

  double bookedPrice = (item['price'] ?? item['totalPrice'] ?? 0).toDouble();
  
  List<dynamic> productItems = item['items'] ?? (isProduct ? [{
    'productName': item['productName'],
    'quantity': item['quantity'] ?? 1,
    'totalPrice': item['totalPrice'],
  }] : []);

  String getServiceNames(dynamic data) {
    if (data['services'] != null && data['services'] is List) {
      return (data['services'] as List).map((s) => s['name'] ?? 'N/A').join(', ');
    }
    return data['serviceName'] ?? 'N/A';
  }

  String getEstimatedTimes(dynamic data) {
    if (data['services'] != null && data['services'] is List) {
      return (data['services'] as List).map((s) => s['estimatedTime'] ?? 'N/A').join(', ');
    }
    return data['estimatedTime'] ?? 'N/A';
  }

  bool isEnteringResults = false;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        double addedPrice = double.tryParse(treatmentPriceCtrl.text) ?? 0.0;
        double totalFinal = bookedPrice + addedPrice;

        // Date restriction check
        bool isFuture = false;
        if (isCompletion) {
          try {
            if (isProduct && item['pickupDate'] != null) {
              DateTime pickup = DateFormat('yyyy-MM-dd').parse(item['pickupDate']);
              DateTime now = DateTime.now();
              DateTime today = DateTime(now.year, now.month, now.day);
              if (pickup.isAfter(today)) isFuture = true;
            } else if (!isProduct && item['appointmentDate'] != null) {
              DateTime apptDate = DateTime.parse(item['appointmentDate']);
              if (apptDate.isAfter(DateTime.now())) isFuture = true;
            }
          } catch (e) {
            debugPrint("Date parsing error: $e");
          }
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: const Color(0xFFB8860B), width: 3),
              color: Colors.white,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isEnteringResults ? "Complete Transaction" : (isProduct ? "Product Details" : "Service Details"), 
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  if (!isEnteringResults) ...[
                    // Common Details
                    _dialogDetailRow("Transaction # :", item['referenceNumber'] ?? id.substring(0, min(5, id.length))),
                    if (item['timestamp'] != null)
                      _dialogDetailRow("Date & Time Booked :", DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(item['timestamp']))),
                    FutureBuilder(
                      future: db.child('users/${item['userId']}').get(),
                      builder: (context, snapshot) {
                        String clientDisplay = item['clientName'] ?? item['username'] ?? 'N/A';
                        if (snapshot.hasData && snapshot.data!.exists) {
                          Map userData = snapshot.data!.value as Map;
                          String fName = userData['firstName'] ?? '';
                          String mName = (userData['middleName'] != null && userData['middleName'].toString().isNotEmpty) 
                              ? "${userData['middleName'].toString()[0].toUpperCase()}." 
                              : "";
                          String lName = userData['lastName'] ?? '';
                          String fullName = [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
                          if (fullName.isNotEmpty) clientDisplay = fullName;
                        }
                        return _dialogDetailRow("Client :", clientDisplay);
                      },
                    ),
                    
                    if (isProduct) ...[
                      const Divider(),
                      ...productItems.map((pi) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${pi['productName']} (x${pi['quantity']})", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  if (pi['variationName'] != null)
                                    Text(pi['variationName'], style: TextStyle(fontSize: 11, color: const Color(0xFFB8860B), fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            Text("₱${_formatter.format((pi['totalPrice'] ?? 0).round())}", style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      )),
                      const Divider(),
                      _dialogDetailRow("Pick Up Date :", () {
                        if (item['pickupDate'] == null) return 'N/A';
                        try {
                          return DateFormat('MMM dd, yyyy').format(DateFormat('yyyy-MM-dd').parse(item['pickupDate']));
                        } catch (_) {
                          try {
                            return DateFormat('MMM dd, yyyy').format(DateTime.parse(item['pickupDate']));
                          } catch (_) {
                            return item['pickupDate'].toString();
                          }
                        }
                      }()),
                      _dialogDetailRow("Pick Up Time :", item['pickupTime'] ?? 'N/A'),
                      if (status == 'Rejected' && item['rejectionReason'] != null)
                        _dialogDetailRow("Rejection Reason :", item['rejectionReason'], color: const Color(0xFFB71C1C)),
                      if (!isCompletion && item['completionTimestamp'] != null)
                        _dialogDetailRow("Time Received :",
                          DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(item['completionTimestamp']))),
                    ] else ...[
                      _dialogDetailRow("Service booked :", getServiceNames(item)),
                      _dialogDetailRow("Appointment Date :", () {
                        if (item['appointmentDate'] == null) return 'N/A';
                        try {
                          return DateFormat('MMM dd, yyyy').format(DateTime.parse(item['appointmentDate']));
                        } catch (_) {
                          return item['appointmentDate'].toString();
                        }
                      }()),
                      _dialogDetailRow("Appointment Time :", item['startTime'] ?? 'N/A'),
                      _dialogDetailRow("Estimated Time :", getEstimatedTimes(item)),
                      _dialogDetailRow("Client Type :", item['clientType'] ?? 'N/A'),
                      if (!isCompletion && item['completionTimestamp'] != null)
                        _dialogDetailRow("Time Finished :", 
                          DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(item['completionTimestamp']))),
                      
                      const SizedBox(height: 10),
                      const Align(alignment: Alignment.centerLeft, child: Text("Pet Information:", style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(
                        padding: const EdgeInsets.only(left: 15, top: 5),
                        child: Builder(
                          builder: (context) {
                            if (petList.isEmpty) return const Text("N/A");
                             
                            return Column(
                              children: petList.map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  children: [
                                    if (petList.length > 1) 
                                       Align(alignment: Alignment.centerLeft, child: Text("Pet ${petList.indexOf(p) + 1}", style: const TextStyle(fontSize: 12, color: Color(0xFFB8860B), fontWeight: FontWeight.bold))),
                                    _petDetailRow("Name :", p['name'] ?? 'N/A'),
                                    Row(children: [
                                      Expanded(child: _petDetailRow("Species :", p['type'] ?? 'N/A')),
                                      Expanded(child: _petDetailRow("Breed :", p['breed'] ?? 'N/A')),
                                    ]),
                                    Row(children: [
                                      Expanded(child: _petDetailRow("Sex :", p['sex'] ?? 'N/A')),
                                      Expanded(child: _petDetailRow("Age :", p['age'] ?? 'N/A')),
                                    ]),
                                    _petDetailRow("Weight :", p['weight'] ?? 'N/A'),
                                    _petDetailRow("Birthday :", p['birthday'] ?? 'N/A'),
                                    if (p != petList.last) const Divider(height: 10),
                                  ],
                                ),
                              )).toList(),
                            );
                          }
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Align(alignment: Alignment.centerLeft, child: Text("Patient(s) Condition :", style: TextStyle(fontWeight: FontWeight.bold))),
                      _dialogInputBox(null, item['reason'] ?? '', readOnly: true),
                      
                      if (!isCompletion) ...[
                        const SizedBox(height: 10),
                        if (item['inHouseTreatment'] != null) ...[
                          const Align(alignment: Alignment.centerLeft, child: Text("In-House Treatment :", style: TextStyle(fontWeight: FontWeight.bold))),
                          _dialogInputBox(null, "${item['inHouseTreatment']} (₱${_formatter.format((item['inHousePrice'] ?? 0).round())})", readOnly: true),
                        ],
                        const Align(alignment: Alignment.centerLeft, child: Text("Laboratory Result :", style: TextStyle(fontWeight: FontWeight.bold))),
                        _dialogInputBox(null, item['laboratoryResult'] ?? 'N/A', readOnly: true),
                        const Align(alignment: Alignment.centerLeft, child: Text("Prescriptions :", style: TextStyle(fontWeight: FontWeight.bold))),
                        _dialogInputBox(null, item['prescription'] ?? 'N/A', readOnly: true),
                        const Align(alignment: Alignment.centerLeft, child: Text("Weight :", style: TextStyle(fontWeight: FontWeight.bold))),
                        _dialogInputBox(null, item['weight'] ?? 'N/A', readOnly: true),
                      ],
                    ],
                  ] else ...[
                    // COMPLETION FORM
                    const Align(alignment: Alignment.centerLeft, child: Text("+ Add a In-House Treatment", style: TextStyle(color: Color(0xFFB8860B), fontWeight: FontWeight.bold, fontSize: 13))),
                    Row(
                      children: [
                        Expanded(child: _dialogInputField(treatmentCtrl, "Service(s)")),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogInputField(treatmentPriceCtrl, "Total Price", 
                          onChanged: (v) => setState(() {}), keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerLeft, child: Text("Laboratory Result", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    _dialogInputField(labResultCtrl, ""),
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerLeft, child: Text("Prescriptions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    if (prescriptionUrl != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFB8860B)),
                                color: const Color(0xFFFBDB83).withOpacity(0.1),
                              ),
                              child: Text(
                                "Prescription Generated: ${prescriptionUrl!.split('/').last}",
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8A6E2F)),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() => prescriptionUrl = null),
                          ),
                        ],
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          final String? result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreatePrescriptionScreen(
                                petInfo: {
                                  'name': petList.isNotEmpty ? petList[0]['name'] : 'Pet',
                                  'species': petList.isNotEmpty ? petList[0]['type'] : 'N/A',
                                  'age': petList.isNotEmpty ? petList[0]['age'] : 'N/A',
                                  'sex': petList.isNotEmpty ? petList[0]['sex'] : 'N/A',
                                  'date': DateFormat('MMM dd, yyyy').format(DateTime.now()),
                                },
                                adminInfo: {
                                  'dvmName': adminData['dvmName'] ?? adminUsername,
                                  'licNo': adminData['licNo'] ?? '',
                                  'ptrNo': adminData['ptrNo'] ?? '',
                                  'contactNo': adminData['contactNumber'] ?? '',
                                },
                              ),
                            ),
                          );
                          if (result != null) {
                            setState(() => prescriptionUrl = result);
                          }
                        },
                        icon: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFFB8860B)),
                        label: const Text("Add a Prescription", style: TextStyle(color: Color(0xFFB8860B), fontSize: 13, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                          side: const BorderSide(color: Color(0xFFB8860B)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Align(alignment: Alignment.centerLeft, child: Text("Weight of the patient (kgs)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    if (petList.isNotEmpty) ...[
                      Column(
                        children: petList.asMap().entries.map((entry) {
                          int idx = entry.key;
                          var p = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(alignment: Alignment.centerLeft, child: Text(p['name'] ?? ('Pet ' + (idx + 1).toString()), style: const TextStyle(fontSize: 12))),
                                _dialogInputField(weightCtrls[idx], ""),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ] else
                      _dialogInputField(weightCtrl, ""),
                  ],

                  if (!isEnteringResults) ...[
                    _dialogDetailRow("Status :", status, color: statusColor),
                    const SizedBox(height: 20),
                    Text("₱ ${_formatter.format((isCompletion ? totalFinal : (item['totalFinalPrice'] ?? bookedPrice)).round())}", 
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: statusColor)),
                  ],
                  
                  const SizedBox(height: 20),
                  
                  if (isEnteringResults) ...[
                    GestureDetector(
                      onTap: () async {
                        if (isFuture) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Transaction cannot be completed before the scheduled date.'))
                          );
                          return;
                        }
                        String path = isProduct ? 'product_reservations' : 'appointments';
                        String newStatus = isProduct ? 'Received' : 'Completed';
                        
                        Map<String, dynamic> updates = {
                          'status': newStatus,
                          'completionTimestamp': ServerValue.timestamp,
                          'totalFinalPrice': totalFinal,
                        };

                        if (!isProduct) {
                          String joinedWeights = weightCtrls.isNotEmpty ? weightCtrls.map((c) => c.text.trim()).where((w) => w.isNotEmpty).join(', ') : weightCtrl.text.trim();

                          updates.addAll({
                            'inHouseTreatment': treatmentCtrl.text,
                            'inHousePrice': addedPrice,
                            'laboratoryResult': labResultCtrl.text,
                            'prescription': prescriptionCtrl.text,
                            'prescriptionUrl': prescriptionUrl,
                            'weight': joinedWeights,
                          });

                          try {
                            final userPetsSnap = await db.child('users/${item['userId']}/pets').get();
                            if (userPetsSnap.exists) {
                              List<dynamic> userPets = List.from(userPetsSnap.value as List);
                              for (int i = 0; i < petList.length; i++) {
                                var apptPet = petList[i];
                                String newWeight = (i < weightCtrls.length) ? weightCtrls[i].text.trim() : '';
                                if (newWeight.isEmpty) continue;
                                int matchIndex = userPets.indexWhere((up) => (up['name'] ?? '') == (apptPet['name'] ?? '') && (up['birthday'] ?? '') == (apptPet['birthday'] ?? ''));
                                if (matchIndex == -1) {
                                  matchIndex = userPets.indexWhere((up) => (up['name'] ?? '') == (apptPet['name'] ?? ''));
                                }
                                if (matchIndex != -1) {
                                  await db.child('users/${item['userId']}/pets/$matchIndex').update({'weight': newWeight});
                                }
                              }
                            }
                          } catch (e) {
                            debugPrint("Pet update error: $e");
                          }

                          final prescriptionData = {
                            'userId': item['userId'],
                            'username': item['username'],
                            'petName': (item['petDetails'] is List) 
                                ? (item['petDetails'] as List).map((p) => p['name'] ?? 'Pet').join(', ')
                                : (item['petDetails']?['name'] ?? 'Pet'),
                            'condition': item['reason'] ?? 'N/A',
                            'prescription': prescriptionCtrl.text,
                            'prescriptionUrl': prescriptionUrl,
                            'date': DateFormat('MMM dd, yyyy').format(DateTime.now()),
                            'timestamp': ServerValue.timestamp,
                            'appointmentId': id,
                          };
                          await db.child('prescriptions').push().set(prescriptionData);
                        }

                        await db.child('$path/$id').update(updates);

                        final String todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
                        final statsRef = db.child('stats');
                        
                        await statsRef.child('revenue/daily/$todayKey').runTransaction((Object? current) {
                          double val = (current ?? 0.0) as double;
                          return Transaction.success(val + totalFinal);
                        });

                        await statsRef.child('counts/daily_transactions/$todayKey').runTransaction((Object? current) {
                          int val = (current ?? 0) as int;
                          return Transaction.success(val + 1);
                        });

                        if (!isProduct && petList.isNotEmpty) {
                          try {
                            final userPetsSnap = await db.child('users/${item['userId']}/pets').get();
                            if (userPetsSnap.exists) {
                              List<dynamic> userPets = List.from(userPetsSnap.value as List);
                              for (int i = 0; i < petList.length; i++) {
                                var apptPet = petList[i];
                                String newWeight = (i < weightCtrls.length) ? weightCtrls[i].text.trim() : '';
                                if (newWeight.isEmpty) continue;
                                
                                int matchIndex = -1;
                                if (apptPet['petId'] != null) {
                                  matchIndex = userPets.indexWhere((up) => up['petId'] == apptPet['petId']);
                                }
                                
                                if (matchIndex == -1) {
                                  matchIndex = userPets.indexWhere((up) => (up['name'] ?? '') == (apptPet['name'] ?? '') && (up['birthday'] ?? '') == (apptPet['birthday'] ?? ''));
                                }

                                if (matchIndex != -1) {
                                  await db.child('users/${item['userId']}/pets/$matchIndex').update({'weight': newWeight});
                                }
                              }
                            }
                          } catch (e) {
                            debugPrint("Pet weight update error: $e");
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transaction marked as $newStatus')));
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            colors: isFuture 
                              ? [Colors.grey[400]!, Colors.grey[600]!, Colors.grey[700]!]
                              : [const Color(0xFF8A6E2F), const Color(0xFFFBDB83), statusColor],
                          ),
                        ),
                        child: const Center(
                          child: Text("Mark as Success/Completed", 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => isEnteringResults = false),
                      child: const Text("Back to Summary", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ] else ...[
                    if (isCompletion && (status == 'Approved' || status == 'Accepted')) ...[
                      GestureDetector(
                        onTap: () => setState(() => isEnteringResults = true),
                        child: Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
                            ),
                          ),
                          child: const Center(
                            child: Text("Complete Transaction", 
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          color: Colors.grey[200],
                        ),
                        child: const Center(
                          child: Text("Close", 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    ),
  );

}

Widget _dialogDetailRow(String label, String value, {Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: color != null ? FontWeight.bold : FontWeight.normal))),
      ],
    ),
  );
}

Widget _petDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(width: 5),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

Widget _dialogInputField(TextEditingController ctrl, String hint, {Function(String)? onChanged, TextInputType? keyboardType}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFB8860B)),
    ),
    child: TextField(
      controller: ctrl,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(hintText: hint, border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8)),
    ),
  );
}

Widget _dialogInputBox(TextEditingController? ctrl, String text, {bool readOnly = false}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFB8860B)),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12)),
  );
}

// --- TAB 1: DASHBOARD ---

class DashboardTab extends StatefulWidget {
  final String username;
  final String adminKey;
  const DashboardTab({super.key, required this.username, required this.adminKey});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _formatter = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    String formattedDate = DateFormat('MMMM dd, yyyy').format(DateTime.now());

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFE0E0E0),
                  child: Icon(Icons.person, size: 40, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Admin Portal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(formattedDate, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                StreamBuilder(
                  stream: db.onValue,
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                      Map data = snapshot.data!.snapshot.value as Map;
                      if (data['appointments'] != null) {
                        Map appts = data['appointments'] as Map;
                        count += appts.values.where((v) => v['status'] == 'Pending').length;
                      }
                      if (data['product_reservations'] != null) {
                        Map res = data['product_reservations'] as Map;
                        count += res.values.where((v) => v['status'] == 'Reserved').length;
                      }
                    }

                    return Badge(
                      label: Text('$count'),
                      isLabelVisible: count > 0,
                      child: IconButton(
                        icon: const Icon(Icons.notifications_none),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => AdminNotificationCenter(adminKey: widget.adminKey),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 25),
            _buildSalesGraph(db),
            const SizedBox(height: 25),
            const Text('Dashboard Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.0, // Changed from 1.1 to be more square/flexible
              children: [
                _buildStatBox(context, 'Bookings', 'appointments', Icons.calendar_today, 'Pending Requests', screen: const AdminAppointmentsScreen()),
                _buildStatBox(context, 'Products', 'products', Icons.shopping_cart_outlined, 'Total Products', screen: const AdminProductsScreen()),
                _buildStatBox(context, 'Promotions', 'promotions', Icons.campaign_outlined, 'Manage Ads', screen: const AdminPromotionsScreen()),
                _buildStatBox(context, 'Services', 'services', Icons.medical_services_outlined, 'Total Services', screen: const AdminServicesScreen()),
              ],
            ),

            const SizedBox(height: 30),
            _buildAlertSection(db),
            const SizedBox(height: 25),
            _buildSectionTitle('Today\'s Schedules'),
            _buildIncomingSchedules(db),
            const SizedBox(height: 80), // Space for bottom bar
          ],
        ),
      ),
    );
  }


  Widget _buildSalesGraph(DatabaseReference db) {
    return StreamBuilder(
      stream: db.child('stats/revenue/daily').onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const SizedBox(height: 200, child: Center(child: Text("Waiting for sales data...")));
        }

        Map data = snapshot.data!.snapshot.value as Map;
        List<FlSpot> spots = [];
        double totalRevenue = 0;
        
        DateTime now = DateTime.now();
        List<DateTime> last7Days = List.generate(7, (index) => now.subtract(Duration(days: 6 - index)));
        
        // Use the pre-aggregated daily stats instead of raw data
        for (int i = 0; i < 7; i++) {
          String dateStr = DateFormat('yyyy-MM-dd').format(last7Days[i]);
          double dayTotal = (data[dateStr] ?? 0.0).toDouble();
          spots.add(FlSpot(i.toDouble(), dayTotal));
          totalRevenue += dayTotal;
        }

        return GoldenCard(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sales Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 10),
              Text('Total Revenue (Last 7 Days): ₱${_formatter.format(totalRevenue.round())}', style: const TextStyle(fontSize: 14, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                height: 200,
                padding: const EdgeInsets.only(top: 20, right: 20, left: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true, 
                      drawVerticalLine: false, 
                      horizontalInterval: totalRevenue > 100 ? totalRevenue / 4 : 100,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.black12, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            int index = value.toInt();
                            if (index >= 0 && index < 7) {
                              String dayName = DateFormat('E').format(last7Days[index]);
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(dayName, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                          reservedSize: 40,
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: const Color(0xFFB8860B), // Using Gold to match theme
                        barWidth: 4,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: const Color(0xFFB8860B),
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true, 
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFB8860B).withOpacity(0.3),
                              const Color(0xFFB8860B).withOpacity(0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatBox(BuildContext context, String title, String path, IconData icon, String subtitle, {Widget? screen, VoidCallback? onTap}) {
    if (title == 'Bookings') {
      return StreamBuilder(
        stream: FirebaseDatabase.instance.ref().child('appointments').onValue,
        builder: (context, apptSnapshot) {
          return StreamBuilder(
            stream: FirebaseDatabase.instance.ref().child('product_reservations').onValue,
            builder: (context, orderSnapshot) {
              int count = 0;
              if (apptSnapshot.hasData && apptSnapshot.data!.snapshot.value != null) {
                Map data = apptSnapshot.data!.snapshot.value as Map;
                count += data.values.where((v) => v['status'] == 'Pending').length;
              }
              if (orderSnapshot.hasData && orderSnapshot.data!.snapshot.value != null) {
                Map data = orderSnapshot.data!.snapshot.value as Map;
                count += data.values.where((v) => v['status'] == 'Reserved').length;
              }
              return _statBoxLayout(context, title, icon, subtitle, count, screen, onTap);
            },
          );
        },
      );
    }

    return StreamBuilder(
      stream: FirebaseDatabase.instance.ref().child(path).onValue,
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          Map data = snapshot.data!.snapshot.value as Map;
          count = data.length;
        }
        return _statBoxLayout(context, title, icon, subtitle, count, screen, onTap);
      },
    );
  }

  Widget _statBoxLayout(BuildContext context, String title, IconData icon, String subtitle, int count, Widget? screen, VoidCallback? onTap) {
    return GoldenCard(
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(builder: (context) => screen!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.black87),
              const SizedBox(width: 5),
              Expanded(
                child: MarqueeText(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          Text('$count', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          MarqueeText(
            text: subtitle,
            style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSection(DatabaseReference db) {
    return StreamBuilder(
      stream: db.child('stats/inventory/low_stock_count').onValue,
      builder: (context, snapshot) {
        int lowStockCount = 0;
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          lowStockCount = (snapshot.data!.snapshot.value as int);
        } else {
          // Fallback if stats node doesn't exist yet
          return const SizedBox.shrink();
        }

        bool hasAlert = lowStockCount > 0;

        return GoldenCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasAlert ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    color: hasAlert ? Colors.orange : Colors.green,
                    size: 24
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasAlert ? '$lowStockCount Active alert' : 'no alert',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  hasAlert ? 'product low on stock!' : 'all product are in good stocks',
                  style: const TextStyle(color: Colors.black54)
                ),
              ),
              if (hasAlert)
                Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminProductsScreen(filterLowStock: true))),
                    child: const Text('view', style: TextStyle(color: Colors.deepOrange)),
                  ),
                )
              else
                const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildIncomingSchedules(DatabaseReference db) {
    return StreamBuilder(
      stream: db.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Text('No schedules for today');
        }
        
        Map data = snapshot.data!.snapshot.value as Map;
        List<Map<String, dynamic>> combinedSchedules = [];
        String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

        // Appointments
        if (data['appointments'] != null) {
          Map appts = data['appointments'] as Map;
          appts.forEach((k, v) {
            if (v['status'] == 'Approved' && (v['appointmentDate']?.toString().startsWith(today) ?? false)) {
              String serviceNames = "Unnamed Service";
              if (v['services'] != null && v['services'] is List) {
                serviceNames = (v['services'] as List).map((s) => s['name'] ?? '').join(', ');
              } else if (v['serviceName'] != null) {
                serviceNames = v['serviceName'];
              }

              combinedSchedules.add({
                ...Map<String, dynamic>.from(v),
                'id': k,
                'type': 'Service',
                'serviceDisplay': serviceNames,
                'time': v['startTime'] ?? v['appointmentDate']?.toString().split(' ').last ?? 'N/A',
              });
            }
          });
        }

        // Product Pickups
        if (data['product_reservations'] != null) {
          Map res = data['product_reservations'] as Map;
          res.forEach((k, v) {
            if (v['status'] == 'To Pick Up' && (v['pickupDate']?.toString().startsWith(today) ?? false)) {
              combinedSchedules.add({
                ...Map<String, dynamic>.from(v),
                'id': k,
                'type': 'Pickup',
                'time': v['pickupTime'] ?? 'N/A',
              });
            }
          });
        }

        if (combinedSchedules.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(child: Text('No accepted schedules for today', style: TextStyle(color: Colors.grey))),
          );
        }

        // Sort by time
        combinedSchedules.sort((a, b) => a['time'].toString().compareTo(b['time'].toString()));

        return Column(
          children: combinedSchedules.map((item) {
            bool isService = item['type'] == 'Service';
            String displayTime = item['time'];
            
            // Try formatting time if it's ISO or raw
            try {
              if (displayTime.contains(':')) {
                // Keep as is if already HH:mm
              } else if (displayTime.length > 5) {
                DateTime dt = DateTime.parse(item['appointmentDate'] ?? item['pickupDate']);
                displayTime = DateFormat('h:mm a').format(dt);
              }
            } catch (_) {}

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: GoldenCard(
                onTap: () {
                  if (isService) {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAppointmentsScreen()));
                  } else {
                    // Navigate to product reservations? 
                    // Current AdminAppointmentsScreen handles both? Let's check.
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminAppointmentsScreen()));
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(displayTime, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isService ? 'SERVICE' : 'PICKUP', 
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['serviceDisplay'] ?? item['productName'] ?? 'Item Name', 
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Client: ${item['username'] ?? 'Anonymous'}",
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    if (isService && item['petDetails'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "Pet: ${item['petDetails'] is List ? (item['petDetails'] as List).map((p) => p['name']).join(', ') : item['petDetails']['name']}",
                          style: const TextStyle(color: Colors.black54, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    const SizedBox(height: 5),
                    const Center(
                      child: Text('view details', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showPromotionManager(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    final picker = ImagePicker();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage Promotions'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    hintText: 'Promotion Title (e.g. 50% Off Vaccines)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a title')));
                       return;
                    }
                    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading promotion...')));
                      String? url = await CloudinaryService.uploadImage(File(image.path));
                      if (url != null) {
                        await db.child('promotions').push().set({
                          'title': titleController.text.trim(),
                          'imageUrl': url,
                          'timestamp': ServerValue.timestamp,
                        });
                        titleController.clear();
                        setDialogState(() {});
                      }
                    }
                  },
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Add Promotion Image'),
                ),
                const Divider(),
                Flexible(
                  child: StreamBuilder(
                    stream: db.child('promotions').onValue,
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                        Map data = snapshot.data!.snapshot.value as Map;
                        var promos = data.entries.toList();
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: promos.length,
                          itemBuilder: (context, index) {
                            var promo = promos[index].value;
                            var promoKey = promos[index].key;
                            return ListTile(
                              leading: Image.network(promo['imageUrl'], width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.broken_image)),
                              title: const Text('Promotion Image'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => db.child('promotions').child(promoKey).remove(),
                              ),
                            );
                          },
                        );
                      }
                      return const Center(child: Text('No promotions added yet.'));
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}

// --- TAB 2: SCHEDULES ---

class SchedulesTab extends StatefulWidget {
  final Map<String, dynamic> adminData;
  final String username;
  const SchedulesTab({super.key, required this.adminData, required this.username});

  @override
  State<SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends State<SchedulesTab> {
  final _formatter = NumberFormat('#,###');
  String _selectedCategory = "All Types";
  String _timeFilter = "All";
  String _statusFilter = "All";
  final _searchController = TextEditingController();
  String _searchQuery = "";

  Widget _buildFilterMenu(String label, List<String> options, Function(String) onSelected) {
    String current = label == "Type" ? _timeFilter : _statusFilter;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => options.map((o) => PopupMenuItem(value: o, child: Text(o))).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83)]),
        ),
        child: Row(
          children: [
            Text(current == "All" ? label : current, style: const TextStyle(fontSize: 12)),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Schedules', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search',
                suffixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFilterMenu("Type", ["upcoming", "tomorrow", "scheduled", "All"], (v) => setState(() => _timeFilter = v)),
              _buildFilterMenu("Product", ["To Pick Up", "All"], (v) => setState(() {
                _selectedCategory = "Products Only";
                _statusFilter = v;
              })),
              _buildFilterMenu("Services", ["Approved", "All"], (v) => setState(() {
                _selectedCategory = "Services Only";
                _statusFilter = v;
              })),
            ],
          ),
          const SizedBox(height: 15),
          Expanded(
            child: StreamBuilder(
              stream: db.onValue,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  Map data = snapshot.data!.snapshot.value as Map;
                  List<dynamic> schedules = [];

                  if (_selectedCategory == "All Types" || _selectedCategory == "Services Only") {
                    if (data['appointments'] != null) {
                      Map appts = data['appointments'] as Map;
                      appts.forEach((k, v) {
                        bool matchesStatus = _statusFilter == "All" || v['status'] == _statusFilter;
                        if (_selectedCategory == "All Types") matchesStatus = v['status'] == 'Approved';

                        if (matchesStatus) {
                          v['id'] = k; v['type'] = 'Service';
                          DateTime? d = DateTime.tryParse(v['appointmentDate'] ?? '');
                          if (_applyTimeFilter(d)) {
                            String serviceNames = v['services'] != null && v['services'] is List 
                                ? (v['services'] as List).map((s) => s['name'] ?? '').join(' ') 
                                : (v['serviceName'] ?? '').toString();
                                
                            if (v['username'].toString().toLowerCase().contains(_searchQuery) ||
                                (v['clientName'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
                                serviceNames.toLowerCase().contains(_searchQuery)) {
                              schedules.add(v);
                            }
                          }
                        }
                      });
                    }
                  }

                  if (_selectedCategory == "All Types" || _selectedCategory == "Products Only") {
                    if (data['product_reservations'] != null) {
                      Map orders = data['product_reservations'] as Map;
                      orders.forEach((k, v) {
                        bool matchesStatus = _statusFilter == "All" || v['status'] == _statusFilter;
                        if (_selectedCategory == "All Types") {
                          matchesStatus = v['status'] == 'To Pick Up' || v['status'] == 'Accepted';
                        }

                        if (matchesStatus) {
                          v['id'] = k; v['type'] = 'Product';
                          DateTime? d = v['timestamp'] != null ? DateTime.fromMillisecondsSinceEpoch(v['timestamp']) : null;
                          if (_applyTimeFilter(d)) {
                            if (v['username'].toString().toLowerCase().contains(_searchQuery) ||
                                (v['clientName'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
                                v['productName'].toString().toLowerCase().contains(_searchQuery)) {
                              schedules.add(v);
                            }
                          }
                        }
                      });
                    }
                  }

                  if (schedules.isEmpty) return const Center(child: Text('No schedules found.'));

                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: schedules.length,
                    itemBuilder: (context, index) {
                      var item = schedules[index];
                      String label = item['type'] == 'Product' ? 'To Pick Up' : 'Booked';
                      DateTime? d = item['type'] == 'Product'
                          ? (item['timestamp'] != null ? DateTime.fromMillisecondsSinceEpoch(item['timestamp']) : null)
                          : DateTime.tryParse(item['appointmentDate'] ?? '');

                      if (d != null) {
                        if (DateFormat('yyyyMMdd').format(d) == DateFormat('yyyyMMdd').format(DateTime.now())) {
                          label = "Upcoming";
                        } else if (DateFormat('yyyyMMdd').format(d) == DateFormat('yyyyMMdd').format(DateTime.now().add(const Duration(days: 1)))) {
                          label = "Tomorrow";
                        }
                      }
                      return _buildTransactionCard(item, label);
                    },
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _applyTimeFilter(DateTime? date) {
    if (_timeFilter == "All") return true;
    if (date == null) return false;
    String dateStr = DateFormat('yyyyMMdd').format(date);
    String nowStr = DateFormat('yyyyMMdd').format(DateTime.now());
    String tomorrowStr = DateFormat('yyyyMMdd').format(DateTime.now().add(const Duration(days: 1)));
    if (_timeFilter == "upcoming") return dateStr == nowStr;
    if (_timeFilter == "tomorrow") return dateStr == tomorrowStr;
    if (_timeFilter == "scheduled") return date.isAfter(DateTime.now().add(const Duration(days: 1)));
    return true;
  }

  Widget _buildTransactionCard(dynamic item, String statusText) {
    double price = (item['type'] == 'Product' ? item['totalPrice'] : item['price'])?.toDouble() ?? 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: GoldenCard(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Transaction Number', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 5),
                    const Icon(Icons.calendar_month, color: Colors.black87, size: 18),
                  ],
                ),
                Text('₱${_formatter.format(price.round())}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            FutureBuilder(
              future: FirebaseDatabase.instance.ref().child('users/${item['userId']}').get(),
              builder: (context, snapshot) {
                String clientDisplay = item['clientName'] ?? item['username'] ?? 'Name';
                if (snapshot.hasData && snapshot.data!.exists) {
                  Map userData = snapshot.data!.value as Map;
                  String fName = userData['firstName'] ?? '';
                  String mName = (userData['middleName'] != null && userData['middleName'].toString().isNotEmpty) 
                      ? "${userData['middleName'].toString()[0].toUpperCase()}." 
                      : "";
                  String lName = userData['lastName'] ?? '';
                  String fullName = [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
                  if (fullName.isNotEmpty) clientDisplay = fullName;
                }
                return Text(clientDisplay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87));
              },
            ),
            Text(item['type'] == 'Service' && item['services'] != null 
                ? (item['services'] as List).map((s) => s['name'] ?? '').join(', ') 
                : (item['serviceName'] ?? item['productName'] ?? 'Item Name'), 
                style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: () => _showTransactionDetailsDialog(context, item, widget.adminData, widget.username, isCompletion: true),
                child: const Text('view details', style: TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- TAB 3: SALES ---

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});

  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  final _formatter = NumberFormat('#,###');
  String _topType = "Products"; // or "Services"

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    String formattedDate = DateFormat('MMM dd, yyyy').format(DateTime.now());

    return SafeArea(
      child: StreamBuilder(
        stream: db.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          Map data = snapshot.data!.snapshot.value as Map;
          double totalRevenue = 0;
          double serviceRev = 0;
          int productPcs = 0;
          Set<String> uniqueCustomers = {};
          int totalTx = 0;

          // Metadata maps for lookup
          Map<String, String> itemImages = {};
          Map<String, String> itemCategories = {};

          // Cache product info
          if (data['products'] != null) {
            Map products = data['products'] as Map;
            products.forEach((k, v) {
              String name = v['name'] ?? '';
              if (name.isNotEmpty) {
                itemImages[name] = v['image'] ?? '';
                itemCategories[name] = v['category'] ?? 'Product';
              }
            });
          }

          // Cache service info
          if (data['services'] != null) {
            Map services = data['services'] as Map;
            services.forEach((k, v) {
              String name = v['name'] ?? '';
              if (name.isNotEmpty) {
                itemImages[name] = v['image'] ?? '';
                itemCategories[name] = v['category'] ?? 'Service';
              }
            });
          }

          Map<String, int> productCounts = {};
          Map<String, int> serviceCounts = {};

          // Process Appointments (Services)
          if (data['appointments'] != null) {
            Map appts = data['appointments'] as Map;
            appts.forEach((k, v) {
              if (v['status'] == 'Completed') {
                double price = (v['totalFinalPrice'] ?? v['price'] ?? 0).toDouble();
                totalRevenue += price;
                serviceRev += price;
                totalTx++;
                uniqueCustomers.add(v['username'] ?? 'Unknown');

                // Improved Service Name Extraction
                List<String> sNames = [];
                if (v['services'] != null && v['services'] is List) {
                  for (var s in (v['services'] as List)) {
                    String name = (s['name'] ?? '').toString();
                    if (name.isNotEmpty) {
                      sNames.add(name);
                      if (!itemImages.containsKey(name) && s['image'] != null) {
                        itemImages[name] = s['image'];
                      }
                    }
                  }
                } else {
                  String sName = v['serviceName'] ?? 'Unknown Service';
                  if (sName != 'Unknown Service') {
                    sNames.add(sName);
                    if (!itemImages.containsKey(sName) && v['imageUrl'] != null) {
                      itemImages[sName] = v['imageUrl'];
                    }
                  }
                }

                if (sNames.isEmpty) sNames.add('Unknown Service');

                for (var sName in sNames) {
                  serviceCounts[sName] = (serviceCounts[sName] ?? 0) + 1;
                  if (!itemCategories.containsKey(sName)) itemCategories[sName] = v['category'] ?? 'Service';
                }
              }
            });
          }

          // Process Product Reservations
          if (data['product_reservations'] != null) {
            Map orders = data['product_reservations'] as Map;
            orders.forEach((k, v) {
              if (v['status'] == 'Received') {
                double price = (v['totalFinalPrice'] ?? v['totalPrice'] ?? 0).toDouble();
                totalRevenue += price;
                totalTx++;
                uniqueCustomers.add(v['username'] ?? 'Unknown');

                if (v['items'] != null && v['items'] is List) {
                  for (var item in (v['items'] as List)) {
                    int qty = (item['quantity'] ?? 1) as int;
                    productPcs += qty;
                    String pName = item['productName'] ?? 'Unknown Product';
                    productCounts[pName] = (productCounts[pName] ?? 0) + qty;
                    if (!itemImages.containsKey(pName) && item['imageUrl'] != null) {
                      itemImages[pName] = item['imageUrl'];
                    }
                  }
                } else {
                  int qty = (v['quantity'] ?? 1) as int;
                  productPcs += qty;
                  String pName = v['productName'] ?? 'Unknown Product';
                  productCounts[pName] = (productCounts[pName] ?? 0) + qty;
                  if (!itemImages.containsKey(pName) && v['imageUrl'] != null) {
                    itemImages[pName] = v['imageUrl'];
                  }
                }
              }
            });
          }

          double avgBooking = totalTx > 0 ? totalRevenue / totalTx : 0;

          // Prepare Top Performing list
          List<MapEntry<String, int>> topItems = (_topType == "Products" ? productCounts : serviceCounts).entries.toList();
          topItems.sort((a, b) => b.value.compareTo(a.value));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sales Overview', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Text(formattedDate, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 5),
                        IconButton(
                          icon: const Icon(Icons.open_in_full, size: 18, color: Colors.grey),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const DetailedAnalyticsScreen()),
                            );
                          },
                        ),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 25),
                
                // Main Revenue Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Earning (Net Revenue)', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₱${_formatter.format(totalRevenue.round())}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87)),
                          // Mini Bar Chart Placeholder
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(6, (i) => Container(
                              width: 8,
                              height: 10.0 + (i * 5) + (i % 2 == 0 ? 10 : 0),
                              margin: const EdgeInsets.only(left: 3),
                              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                            )),
                          )
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(color: Colors.black12),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: _buildKpiItem('Services', '₱${_formatter.format(serviceRev.round())}')),
                          Expanded(child: _buildKpiItem('Product', '$productPcs pcs')),
                          Expanded(child: _buildKpiItem('Customer', '${uniqueCustomers.length}')),
                          Expanded(child: _buildKpiItem('Avg Booking', '₱${_formatter.format(avgBooking.round())}')),
                        ],
                      )
                    ],
                  ),
                ),
                
                const SizedBox(height: 35),
                const Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Top Performing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          _buildToggleBtn("Products"),
                          _buildToggleBtn("Services"),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 25),

                // Top Items List
                ...topItems.take(5).map((item) => _buildTopItemCard(
                  item.key, 
                  item.value, 
                  itemCategories[item.key] ?? (_topType == "Products" ? "Inventory" : "Clinic"),
                  itemImages[item.key] ?? ""
                )),
                
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildToggleBtn(String label) {
    bool isSelected = _topType == label;
    return GestureDetector(
      onTap: () => setState(() => _topType = label),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)] : null,
        ),
        child: MarqueeText(
          text: isSelected ? '*$label*' : label,
          style: TextStyle(
            fontSize: 12, 
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.black : Colors.grey
          ),
        ),
      ),
    );
  }

  Widget _buildKpiItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          text: label,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
        const SizedBox(height: 4),
        MarqueeText(
          text: value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildTopItemCard(String name, int count, String category, String imageUrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFBDB83).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              image: imageUrl.isNotEmpty
                  ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                  : null,
            ),
            child: imageUrl.isEmpty
                ? Icon(_topType == "Products" ? Icons.inventory_2_outlined : Icons.medical_services_outlined, color: const Color(0xFFB8860B))
                : null,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueeText(
                  text: name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text('Category: $category', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Text('▲ 20% Booked', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// --- TAB 4: HISTORY ---

class HistoryTab extends StatefulWidget {
  final Map<String, dynamic> adminData;
  final String username;
  const HistoryTab({super.key, required this.adminData, required this.username});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final _formatter = NumberFormat('#,###');
  String _typeFilter = "All";
  String _statusFilter = "All";
  DateTime? _selectedDate;
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search',
                suffixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFilterMenu("Type", ["Product", "Service", "All"], (v) => setState(() => _typeFilter = v)),
              _buildFilterMenu("Status", ["Cancelled", "Success", "Received", "All"], (v) => setState(() => _statusFilter = v)),
              GestureDetector(
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83)]),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedDate == null ? "Date" : DateFormat('MM/dd/yy').format(_selectedDate!), style: const TextStyle(fontSize: 12)),
                      if (_selectedDate != null) IconButton(icon: const Icon(Icons.close, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() => _selectedDate = null)),
                      const Icon(Icons.keyboard_arrow_down, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GoldenCard(
              padding: const EdgeInsets.all(12),
              child: StreamBuilder(
                stream: db.onValue,
                builder: (context, snapshot) {
                  double totalRev = 0;
                  if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                    Map data = snapshot.data!.snapshot.value as Map;
                    if (data['product_reservations'] != null) {
                      (data['product_reservations'] as Map).values.forEach((v) {
                        if (v['status'] == 'Received') {
                          totalRev += (v['totalFinalPrice'] ?? v['totalPrice'] ?? 0).toDouble();
                        }
                      });
                    }
                    if (data['appointments'] != null) {
                      (data['appointments'] as Map).values.forEach((v) {
                        if (v['status'] == 'Completed') {
                          totalRev += (v['totalFinalPrice'] ?? v['price'] ?? 0).toDouble();
                        }
                      });
                    }
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Rev : ₱${_formatter.format(totalRev.round())}', style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          const Icon(Icons.shopping_cart, color: Colors.black87, size: 20),
                          const SizedBox(width: 20),
                          const Icon(Icons.calendar_month, color: Colors.black87, size: 20),
                        ],
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: StreamBuilder(
              stream: db.onValue,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  Map data = snapshot.data!.snapshot.value as Map;
                  List<dynamic> history = [];
                  if (_typeFilter == "All" || _typeFilter == "Service") {
                    if (data['appointments'] != null) {
                      (data['appointments'] as Map).forEach((k, v) {
                        if (v['status'] == 'Completed' || v['status'] == 'Cancelled') {
                          v['id'] = k; v['type'] = 'Service';
                          if (_applyFilters(v)) history.add(v);
                        }
                      });
                    }
                  }
                  if (_typeFilter == "All" || _typeFilter == "Product") {
                    if (data['product_reservations'] != null) {
                      (data['product_reservations'] as Map).forEach((k, v) {
                        if (v['status'] == 'Received' || v['status'] == 'Cancelled') {
                          v['id'] = k; v['type'] = 'Product';
                          if (_applyFilters(v)) history.add(v);
                        }
                      });
                    }
                  }
                  if (history.isEmpty) return const Center(child: Text('No history found'));
                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: history.length,
                    itemBuilder: (context, index) => _buildHistoryCard(history[index]),
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _applyFilters(dynamic item) {
    if (_searchQuery.isNotEmpty) {
      String user = (item['username'] ?? '').toString().toLowerCase();
      String client = (item['clientName'] ?? '').toString().toLowerCase();
      String itemN = item['type'] == 'Service' && item['services'] != null 
          ? (item['services'] as List).map((s) => (s['name'] ?? '').toString()).join(' ').toLowerCase()
          : (item['serviceName'] ?? item['productName'] ?? '').toString().toLowerCase();
          
      if (!user.contains(_searchQuery) && !client.contains(_searchQuery) && !itemN.contains(_searchQuery)) return false;
    }
    if (_statusFilter != "All") {
      String status = item['status'];
      if (_statusFilter == "Success" && status != "Completed") return false;
      if (_statusFilter == "Received" && status != "Received") return false;
      if (_statusFilter == "Cancelled" && status != "Cancelled") return false;
    }
    if (_selectedDate != null) {
      DateTime? d = item['type'] == 'Product' ? (item['timestamp'] != null ? DateTime.fromMillisecondsSinceEpoch(item['timestamp']) : null) : DateTime.tryParse(item['appointmentDate'] ?? '');
      if (d == null || DateFormat('yyyyMMdd').format(d) != DateFormat('yyyyMMdd').format(_selectedDate!)) return false;
    }
    return true;
  }

  Widget _buildFilterMenu(String label, List<String> options, Function(String) onSelected) {
    String current = label == "Type" ? _typeFilter : _statusFilter;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => options.map((o) => PopupMenuItem(value: o, child: Text(o))).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83)]),
        ),
        child: Row(
          children: [
            Text(current == "All" ? label : current, style: const TextStyle(fontSize: 12)),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(dynamic item) {
    String status = item['status'] == 'Received' || item['status'] == 'Completed' ? 'Success' : item['status'] ?? 'Unknown';
    if (item['type'] == 'Product' && item['status'] == 'Received') status = "Received"; // Fixed typo
    double price = (item['type'] == 'Product' ? (item['totalFinalPrice'] ?? item['totalPrice']) : (item['totalFinalPrice'] ?? item['price']))?.toDouble() ?? 0.0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: GoldenCard(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Transaction Number', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 5),
                    Icon(item['type'] == 'Product' ? Icons.shopping_cart : Icons.calendar_month, color: Colors.black87, size: 18),
                  ],
                ),
                Text('₱${_formatter.format(price.round())}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            FutureBuilder(
              future: FirebaseDatabase.instance.ref().child('users/${item['userId']}').get(),
              builder: (context, snapshot) {
                String clientDisplay = item['clientName'] ?? item['username'] ?? 'Name';
                if (snapshot.hasData && snapshot.data!.exists) {
                  Map userData = snapshot.data!.value as Map;
                  String fName = userData['firstName'] ?? '';
                  String mName = (userData['middleName'] != null && userData['middleName'].toString().isNotEmpty) 
                      ? "${userData['middleName'].toString()[0].toUpperCase()}." 
                      : "";
                  String lName = userData['lastName'] ?? '';
                  String fullName = [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
                  if (fullName.isNotEmpty) clientDisplay = fullName;
                }
                return Text(clientDisplay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87));
              },
            ),
            Text(item['type'] == 'Service' && item['services'] != null 
                ? (item['services'] as List).map((s) => s['name'] ?? '').join(', ') 
                : (item['serviceName'] ?? item['productName'] ?? 'Item Name'), 
                style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: () => _showTransactionDetailsDialog(context, item, widget.adminData, widget.username, isCompletion: false),
                child: const Text('view details', style: TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Text(status, style: TextStyle(color: status == 'Success' || status == 'Received' ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 14)), // Fixed typo
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- TAB 4: PROFILE ---

class ProfileTab extends StatefulWidget {
  final String username;
  final Map<String, dynamic> adminData;
  final String? adminKey;
  final VoidCallback onRefresh;

  const ProfileTab({
    super.key, 
    required this.username, 
    required this.adminData, 
    this.adminKey,
    required this.onRefresh,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  DateTime _calendarDate = DateTime.now();

  Future<void> _launchSocial(String urlString) async {
    if (urlString.isEmpty || urlString == 'Not set') return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $urlString')),
        );
      }
    }
  }

  void _showEditAdminProfileDialog() {
    if (widget.adminKey == null) return;
    
    final contactCtrl = TextEditingController(text: widget.adminData['contactNumber'] ?? '');
    final emailCtrl = TextEditingController(text: widget.adminData['email'] ?? '');
    final fbCtrl = TextEditingController(text: widget.adminData['facebook'] ?? '');
    final msgCtrl = TextEditingController(text: widget.adminData['messenger'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.edit_note, color: const Color(0xFFB8860B)),
            const SizedBox(width: 10),
            const Text('Edit Profile'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Update your contact details and social media links so clients can reach you for follow-ups.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              _dialogTextField(contactCtrl, 'Contact Number', Icons.phone, hint: "e.g. 09123456789"),
              const SizedBox(height: 12),
              _dialogTextField(emailCtrl, 'Email Address', Icons.email, hint: "e.g. clinic@gmail.com"),
              const SizedBox(height: 12),
              _dialogTextField(fbCtrl, 'Facebook Link', Icons.facebook, hint: "Paste your FB profile/page URL"),
              const SizedBox(height: 12),
              _dialogTextField(msgCtrl, 'Messenger Link', Icons.chat_bubble, hint: "Paste your m.me/link"),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB8860B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await FirebaseDatabase.instance.ref().child('admins/${widget.adminKey}').update({
                'contactNumber': contactCtrl.text.trim(),
                'email': emailCtrl.text.trim(),
                'facebook': fbCtrl.text.trim(),
                'messenger': msgCtrl.text.trim(),
              });
              widget.onRefresh();
              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully!')),
                );
              }
            },
            child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _dialogTextField(TextEditingController ctrl, String label, IconData icon, {String? hint}) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Colors.black26),
        prefixIcon: Icon(icon, color: const Color(0xFFB8860B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFB8860B), width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.settings, color: Color(0xFFB8860B)),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AdminSettingsScreen(
                    adminId: widget.adminKey ?? '', 
                    username: widget.username,
                  ))),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GoldenCard(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Color(0xFFE0E0E0),
                    child: Icon(Icons.person, size: 60, color: Colors.grey),
                  ),
                  const SizedBox(height: 15),
                  Text(widget.adminData['username'] ?? widget.username, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text('System Administrator', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 20),
            const SizedBox(height: 20),

            // Clinic Availability Calendar Box
            OutlinedGoldCard(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_busy, color: Color(0xFFB8860B)),
                      const SizedBox(width: 10),
                      Text('Clinic Availability', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF8A6E2F))),
                    ],
                  ),
                  const SizedBox(height: 15),
                  StreamBuilder(
                    stream: db.child('clinic_closure').onValue,
                    builder: (context, snapshot) {
                      Map<String, dynamic> closureData = {};
                      if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                        closureData = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
                      }
                      String? openUntil = closureData['open_until'];
                      List<String> closedDates = closureData['closed_dates'] != null ? List<String>.from(closureData['closed_dates']) : [];
                      Map<String, dynamic> customHours = closureData['custom_hours'] != null ? Map<String, dynamic>.from(closureData['custom_hours']) : {};

                      return Column(
                        children: [
                          _buildMiniCalendar(context, db, openUntil, closedDates, customHours),
                          const Divider(color: Colors.black12, height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Limit bookings until:', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                              Row(
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.edit, size: 14, color: Color(0xFFB8860B)),
                                    label: Text(openUntil ?? 'Set Date', style: const TextStyle(color: Color(0xFFB8860B), fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () async {
                                      DateTime? picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        await db.child('clinic_closure').update({'open_until': DateFormat('yyyy-MM-dd').format(picked)});
                                      }
                                    },
                                  ),
                                  if (openUntil != null)
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                      onPressed: () async {
                                        await db.child('clinic_closure/open_until').remove();
                                      },
                                    )
                                ],
                              ),
                            ],
                          )
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            OutlinedGoldCard(
              width: double.infinity,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(
                        title: const Text("Transaction History"),
                        backgroundColor: const Color(0xFFB8860B),
                        foregroundColor: Colors.white,
                      ),
                      body: HistoryTab(adminData: widget.adminData, username: widget.username),
                    ),
                  ),
                );
              },
              child: const Row(
                children: [
                  Icon(Icons.history, color: Color(0xFFB8860B)),
                  SizedBox(width: 10),
                  Text('Transaction History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF8A6E2F))),
                  Spacer(),
                  Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
            ),
            const SizedBox(height: 15),
            OutlinedGoldCard(
              width: double.infinity,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const AdminRatingsScreen()),
                );
              },
              child: const Row(
                children: [
                  Icon(Icons.star_outline_rounded, color: Color(0xFFB8860B)),
                  SizedBox(width: 10),
                  Text('User Ratings & Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF8A6E2F))),
                  Spacer(),
                  Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildMiniCalendar(BuildContext context, DatabaseReference db, String? openUntil, List<String> closedDates, Map<String, dynamic> customHours) {
    DateTime firstDay = DateTime(_calendarDate.year, _calendarDate.month, 1);
    int daysInMonth = DateTime(_calendarDate.year, _calendarDate.month + 1, 0).day;
    int offset = firstDay.weekday % 7;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left, color: const Color(0xFFB8860B)), onPressed: () => setState(() => _calendarDate = DateTime(_calendarDate.year, _calendarDate.month - 1))),
            Text(DateFormat('MMMM yyyy').format(_calendarDate), style: const TextStyle(color: Color(0xFF8A6E2F), fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.chevron_right, color: const Color(0xFFB8860B)), onPressed: () => setState(() => _calendarDate = DateTime(_calendarDate.year, _calendarDate.month + 1))),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: daysInMonth + offset,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemBuilder: (context, index) {
            if (index < offset) return const SizedBox();
            int day = index - offset + 1;
            DateTime date = DateTime(_calendarDate.year, _calendarDate.month, day);
            String dateKey = DateFormat('yyyy-MM-dd').format(date);

            bool isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
            bool isClosed = closedDates.contains(dateKey) || isWeekend;
            bool hasCustomHours = customHours.containsKey(dateKey);

            return GestureDetector(
              onTap: () => _showDaySettings(context, db, date, isClosed, hasCustomHours ? customHours[dateKey] : null, closedDates),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isClosed ? Colors.red.withOpacity(0.1) : (hasCustomHours ? Colors.blue.withOpacity(0.1) : Colors.grey.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isClosed ? Colors.red.withOpacity(0.3) : (hasCustomHours ? Colors.blue.withOpacity(0.3) : Colors.black12)),
                ),
                child: Center(
                  child: Text('$day', style: TextStyle(color: isClosed ? Colors.red : Colors.black87, fontSize: 10, fontWeight: isClosed ? FontWeight.normal : FontWeight.bold)),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _legend(Colors.grey.shade300, 'Open'),
            _legend(Colors.red.withOpacity(0.3), 'Closed'),
            _legend(Colors.blue.withOpacity(0.3), 'Hours'),
          ],
        )
      ],
    );
  }

  Widget _legend(Color color, String text) {
    return Row(children: [Container(width: 8, height: 8, color: color), const SizedBox(width: 4), Text(text, style: const TextStyle(color: Colors.grey, fontSize: 8))]);
  }

  void _showDaySettings(BuildContext context, DatabaseReference db, DateTime date, bool currentlyClosed, dynamic currentHours, List<String> closedDates) {
    String dateKey = DateFormat('yyyy-MM-dd').format(date);
    bool isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    Map<String, String> parseTime(String? t) {
      if (t == null) return {'time': '08:00', 'period': 'AM'};
      List<String> parts = t.split(':');
      int h = int.parse(parts[0]);
      String m = parts[1];
      String period = h >= 12 ? 'PM' : 'AM';
      int h12 = h % 12;
      if (h12 == 0) h12 = 12;
      return {'time': '$h12:$m', 'period': period};
    }

    var startData = parseTime(currentHours?['start']);
    var endData = parseTime(currentHours?['end']);

    final startCtrl = TextEditingController(text: startData['time']);
    String startPeriod = startData['period']!;
    final endCtrl = TextEditingController(text: endData['time']);
    String endPeriod = endData['period']!;

    String joinTo24h(String t, String p) {
      try {
        List<String> parts = t.split(':');
        if (parts.length != 2) return "08:00";
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        if (p == 'PM' && h < 12) h += 12;
        if (p == 'AM' && h == 12) h = 0;
        return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
      } catch (e) {
        return "08:00";
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text(DateFormat('EEEE, MMM dd').format(date)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isWeekend)
                  const Text('Weekends are permanently closed.', style: TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic))
                else
                  SwitchListTile(
                    title: const Text('Clinic Closed'),
                    value: currentlyClosed,
                    onChanged: (v) => setDState(() => currentlyClosed = v),
                  ),
                if (!currentlyClosed) ...[
                  const SizedBox(height: 10),
                  const Text('Operating Hours:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: startCtrl, decoration: const InputDecoration(labelText: 'Start (H:m)', isDense: true))),
                      const SizedBox(width: 5),
                      DropdownButton<String>(
                        value: startPeriod,
                        items: ['AM', 'PM'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setDState(() => startPeriod = v!),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: endCtrl, decoration: const InputDecoration(labelText: 'End (H:m)', isDense: true))),
                      const SizedBox(width: 5),
                      DropdownButton<String>(
                        value: endPeriod,
                        items: ['AM', 'PM'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setDState(() => endPeriod = v!),
                      )
                    ],
                  ),
                ],
                const Divider(),
                TextButton(
                  onPressed: () async {
                    if (!isWeekend) closedDates.remove(dateKey);
                    await db.child('clinic_closure/closed_dates').set(closedDates);
                    await db.child('clinic_closure/custom_hours/$dateKey').remove();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Clear Day Settings', style: TextStyle(color: Colors.grey)),
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (currentlyClosed) {
                  if (!isWeekend && !closedDates.contains(dateKey)) {
                    closedDates.add(dateKey);
                    await db.child('clinic_closure').update({'closed_dates': closedDates});
                  }
                  await db.child('clinic_closure/custom_hours/$dateKey').remove();
                } else {
                  if (!isWeekend) closedDates.remove(dateKey);
                  await db.child('clinic_closure').update({
                    'closed_dates': closedDates,
                    'custom_hours/$dateKey': {
                      'start': joinTo24h(startCtrl.text.trim(), startPeriod),
                      'end': joinTo24h(endCtrl.text.trim(), endPeriod),
                    }
                  });
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? iconColor, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.white, size: 20),
            const SizedBox(width: 15),
            Expanded(
              child: MarqueeText(
                text: text,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (onTap != null && text != 'Not set')
              const Icon(Icons.open_in_new, color: Colors.white54, size: 12),
          ],
        ),
      ),
    );
  }
}
