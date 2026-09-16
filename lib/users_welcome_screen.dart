import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' hide Text, Colors;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'booking_manager.dart';
import 'user_orders_screen.dart';
import 'user_appointments_screen.dart';
import 'user_cart_screen.dart';
import 'pet_chatbot.dart';
import 'login_screen.dart';
import 'session_manager.dart';
import 'responsive_layout.dart';
import 'appointment_scheduling_screen.dart';
import 'user_settings_screen.dart';
import 'product_view_screen.dart';
import 'service_view_screen.dart';
import 'widgets/gold_blobs_background.dart';
import 'widgets/marquee_text.dart';

final Map<String, List<String>> _petBreeds = {
  'Dog': ['Golden Retriever', 'Bulldog', 'Poodle', 'German Shepherd', 'Beagle', 'Chihuahua', 'Labrador', 'Shih Tzu', 'Dachshund', 'Siberian Husky'],
  'Cat': ['Persian', 'Siamese', 'Maine Coon', 'Bengal', 'Ragdoll', 'Sphynx', 'British Shorthair', 'Scottish Fold', 'Abyssinian', 'Burmese'],
};

class UsersWelcomeScreen extends StatefulWidget {
  final String username;
  final String? userId;

  const UsersWelcomeScreen({super.key, required this.username, this.userId});

  @override
  State<UsersWelcomeScreen> createState() => _UsersWelcomeScreenState();
}

class _UsersWelcomeScreenState extends State<UsersWelcomeScreen> with TickerProviderStateMixin {
  final _database = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;
  Map<String, dynamic> _userData = {};
  List<Map<String, dynamic>> _upcomingAppointments = [];
  final List<Map<String, dynamic>> _allAppts = [];
  final List<Map<String, dynamic>> _allRes = [];
  List<Map<String, dynamic>> _prescriptions = [];
  bool _isLoading = true;
  bool _hasShownWelcomeDialog = false;
  
  int _currentTabIndex = 0; // 0: Products, 1: Services, 2: Me
  String? _selectedCategory;
  
  // Colors Palette
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
  final Color lightGold = const Color(0xFFFBDB83);
  final _formatter = NumberFormat('#,###');

  // Search related
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  
  final List<String> _productHints = [
    "Search pet food & accessories...",
    "Vitamins for your pets...",
    "Search bowls & leashes...",
    "Healthy treats for cats & dogs..."
  ];
  
  final List<String> _serviceHints = [
    "Book a grooming session...",
    "Find vet clinics near you...",
    "Search pet checkups...",
    "Vaccination appointments..."
  ];
  
  int _currentHintIndex = 0;
  Timer? _hintTimer;
  bool _isSearchFocused = false;
  
  // Settings related
  bool _dataSaverEnabled = false;

  List<Map<String, dynamic>> _activePromos = [];
  
  // Notification listeners
  StreamSubscription? _apptSubscription;
  StreamSubscription? _resSubscription;
  StreamSubscription? _promoSubscription;
  StreamSubscription? _deviceSessionSubscription;
  final Map<String, String> _lastApptStatus = {};
  final Map<String, String> _lastResStatus = {};
  String? _lastPromoId;

  // Banner slider related
  final PageController _bannerController = PageController();
  late PageController _pageController;
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTabIndex);
    _fetchUserData();
    _fetchUpcomingAppointments();
    _fetchPrescriptions();
    _startHintTimer();
    _initNotificationListeners();
    _initRemoteLogoutListener();
    _loadSystemSettings();
  }

  Future<void> _loadSystemSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dataSaverEnabled = prefs.getBool('data_saver_enabled') ?? false;
    });
  }

  Future<void> _initRemoteLogoutListener() async {
    String? uid = widget.userId;
    if (uid == null) return;
    
    String deviceId = await SessionManager.getDeviceId();
    
    _deviceSessionSubscription = _database.child('users').child(uid).child('devices').child(deviceId).onValue.listen((event) async {
      if (!event.snapshot.exists && _isLoading == false) { 
        if (!context.mounted) return;
        
        await SessionManager.clearSession();
        
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Session Terminated", style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text("This device has been logged out remotely or your session has expired."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => LoginScreen()),
                    (route) => false,
                  );
                },
                child: const Text("Back to Login", style: TextStyle(color: const Color(0xFFB8860B), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hintTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _pageController.dispose();
    _apptSubscription?.cancel();
    _resSubscription?.cancel();
    _promoSubscription?.cancel();
    _deviceSessionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initNotificationListeners() async {
    String? uid = widget.userId ?? _auth.currentUser?.uid;
    if (uid == null) return;

    final prefs = await SharedPreferences.getInstance();

    // 1. Listen for Appointment Status Changes & Reminders
    _apptSubscription = _database.child('appointments').orderByChild('userId').equalTo(uid).onValue.listen((event) {
      _allAppts.clear();
      if (event.snapshot.exists) {
        bool orderNotifEnabled = prefs.getBool('${uid}_order_updates_enabled') ?? true;
        bool pushEnabled = prefs.getBool('${uid}_push_enabled') ?? true;

        Map data = event.snapshot.value as Map;
        data.forEach((key, value) {
          var appt = Map<String, dynamic>.from(value);
          appt['id'] = key;
          _allAppts.add(appt);

          String status = appt['status'] ?? '';
          String serviceName = appt['serviceName'] ?? 'Service';
          if (appt['services'] != null && appt['services'] is List && (appt['services'] as List).isNotEmpty) {
            serviceName = (appt['services'] as List).map((s) => s['name'] ?? 'Service').join(', ');
          }
          String apptDateStr = appt['appointmentDate'] ?? '';

          // Status Change Notification
          if (_lastApptStatus.containsKey(key) && _lastApptStatus[key] != status) {
            if (pushEnabled && orderNotifEnabled) {
              if (status == 'Approved' || status == 'Completed' || status == 'Cancelled' || status == 'Rejected') {
                NotificationService.showNotification(
                  "Booking Update",
                  "Your booking for $serviceName is now $status."
                );
              }
            }
          }
          _lastApptStatus[key] = status;

          // Tomorrow Reminder Logic
          if (apptDateStr.isNotEmpty && status == 'Approved') {
            try {
              DateTime apptDate = DateTime.parse(apptDateStr);
              DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
              if (apptDate.year == tomorrow.year && apptDate.month == tomorrow.month && apptDate.day == tomorrow.day) {
                 String reminderKey = '${uid}_reminder_${key}_${apptDate.day}';
                 if (prefs.getString(reminderKey) == null) {
                    if (pushEnabled && orderNotifEnabled) {
                      NotificationService.showNotification(
                        "Appointment Reminder",
                        "You have an appointment for $serviceName tomorrow!"
                      );
                      prefs.setString(reminderKey, 'shown');
                    }
                 }
              }
            } catch (_) {}
          }
        });
      }
      _updateUpcomingSchedules();
    });

    // 2. Listen for Product Reservation Status Changes
    _resSubscription = _database.child('product_reservations').orderByChild('userId').equalTo(uid).onValue.listen((event) {
      _allRes.clear();
      if (event.snapshot.exists) {
        bool orderNotifEnabled = prefs.getBool('${uid}_order_updates_enabled') ?? true;
        bool pushEnabled = prefs.getBool('${uid}_push_enabled') ?? true;

        Map data = event.snapshot.value as Map;
        data.forEach((key, value) {
          var res = Map<String, dynamic>.from(value);
          res['id'] = key;
          _allRes.add(res);

          String status = res['status'] ?? '';
          String prodName = res['productName'] ?? 'Product';

          if (_lastResStatus.containsKey(key) && _lastResStatus[key] != status) {
            if (pushEnabled && orderNotifEnabled) {
              if (status == 'Accepted' || status == 'Completed' || status == 'Cancelled' || status == 'Rejected') {
                NotificationService.showNotification(
                  "Reservation Update",
                  "Your reservation for $prodName is now $status."
                );
              }
            }
          }
          _lastResStatus[key] = status;
        });
      }
      _updateUpcomingSchedules();
    });

    // 3. Listen for All Active Promotions
    _promoSubscription = _database.child('promotions').onValue.listen((event) {
      if (!mounted) return;
      List<Map<String, dynamic>> promos = [];
      if (event.snapshot.exists) {
        Map data = event.snapshot.value as Map;
        data.forEach((key, value) {
          var promo = Map<String, dynamic>.from(value);
          promo['id'] = key;
          
          bool isActive = promo['isActive'] != false;
          bool isNotExpired = true;
          
          if (promo['validUntil'] != null) {
            isNotExpired = DateTime.now().millisecondsSinceEpoch < (promo['validUntil'] as int);
          }

          if (isActive && isNotExpired) {
            promos.add(promo);
          }
        });
      }
      
      setState(() => _activePromos = promos);

      // Notification Logic for the latest promo
      if (promos.isNotEmpty) {
        // Sort by timestamp to get the latest
        promos.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        var latestPromo = promos.first;
        String promoId = latestPromo['id'];
        
        bool promoNotifEnabled = prefs.getBool('${uid}_promotions_enabled') ?? true;
        bool pushEnabled = prefs.getBool('${uid}_push_enabled') ?? true;
        String? lastSeenPromo = prefs.getString('${uid}_last_seen_promo');

        if (lastSeenPromo != null && lastSeenPromo != promoId) {
          if (pushEnabled && promoNotifEnabled) {
            NotificationService.showNotification(
              "New Promotion!",
              latestPromo['title'] ?? "Check out our latest pet supplies and offers!"
            );
          }
        }
        _lastPromoId = promoId;
        prefs.setString('${uid}_last_seen_promo', promoId);
      }
    });
  }

  void _startHintTimer() {
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && !_isSearchFocused && _searchController.text.isEmpty) {
        setState(() {
          _currentHintIndex++;
        });
      }
    });
  }

  void _startBannerTimer(int itemCount) {
    _bannerTimer?.cancel();
    if (itemCount <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_bannerController.hasClients) {
        _currentBannerIndex++;
        if (_currentBannerIndex >= itemCount) _currentBannerIndex = 0;
        _bannerController.animateToPage(
          _currentBannerIndex,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _fetchUserData() async {
    try {
      String? id = widget.userId ?? _auth.currentUser?.uid;
      if (id != null) {
        final snapshot = await _database.child('users/$id').get();
        if (snapshot.exists) {
          if (mounted) {
            setState(() {
              _userData = Map<String, dynamic>.from(snapshot.value as Map);
              _isLoading = false;
            });
            // Show welcome popup automatically after data is ready
            if (!_hasShownWelcomeDialog) {
              _hasShownWelcomeDialog = true;
              Future.delayed(const Duration(milliseconds: 1200), () => _showChatWelcomePopup());
            }
          }
          return;
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _capitalize(String? s) {
    if (s == null || s.isEmpty) return "";
    return s[0].toUpperCase() + s.substring(1);
  }

  String _getFullName() {
    if (_userData.isEmpty) return widget.username;
    
    String fName = _capitalize(_userData['firstName']);
    String mName = (_userData['middleName'] != null && _userData['middleName'].toString().isNotEmpty) 
        ? _userData['middleName'].toString()[0].toUpperCase()
        : "";
    String lName = _capitalize(_userData['lastName']);
    
    return [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
  }

  void _updateUpcomingSchedules() {
    List<Map<String, dynamic>> combined = [];

    // Filter Appts
    for (var appt in _allAppts) {
      if (appt['status'] != 'Cancelled' && appt['status'] != 'Completed') {
        try {
          DateTime date = DateTime.parse(appt['appointmentDate']);
          if (date.isAfter(DateTime.now().subtract(const Duration(hours: 1)))) {
            combined.add({...appt, 'isProduct': false});
          }
        } catch (_) {}
      }
    }

    // Filter Res
    for (var res in _allRes) {
      if (res['status'] != 'Cancelled' && res['status'] != 'Completed') {
        try {
          DateTime date = DateTime.parse(res['pickupDate']);
          if (date.isAfter(DateTime.now().subtract(const Duration(hours: 1)))) {
            combined.add({...res, 'isProduct': true});
          }
        } catch (_) {}
      }
    }

    combined.sort((a, b) {
      String dateA = a['appointmentDate'] ?? a['pickupDate'] ?? '';
      String dateB = b['appointmentDate'] ?? b['pickupDate'] ?? '';
      return dateA.compareTo(dateB);
    });

    if (mounted) setState(() => _upcomingAppointments = combined);
  }

  Map<String, dynamic>? _getDiscountFor(String id, bool isProduct, {String? variationName}) {
    for (var promo in _activePromos) {
      List targets = promo['targets'] ?? [];
      for (var target in targets) {
        if (target['id'] == id) {
          if (isProduct) {
            if (target['applyToAll'] == true) return promo;
            List selectedVars = target['selectedVariations'] ?? [];
            if (variationName != null && selectedVars.contains(variationName)) return promo;
            if (variationName == null) return promo;
          } else {
            return promo;
          }
        }
      }
    }
    return null;
  }

  Future<void> _fetchUpcomingAppointments() async {
    // Logic moved to _initNotificationListeners to consolidate listeners
    _updateUpcomingSchedules();
  }

  Future<void> _fetchPrescriptions() async {
    String? id = widget.userId ?? _auth.currentUser?.uid;
    if (id == null) return;

    _database.child('prescriptions').orderByChild('userId').equalTo(id).onValue.listen((event) {
      if (event.snapshot.exists) {
        Map data = event.snapshot.value as Map;
        List<Map<String, dynamic>> list = [];
        data.forEach((key, value) {
          var item = Map<String, dynamic>.from(value);
          item['id'] = key;
          list.add(item);
        });
        list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        if (mounted) setState(() => _prescriptions = list);
      } else {
        if (mounted) setState(() => _prescriptions = []);
      }
    });
  }

  void _showChatWelcomePopup() {
    final TextEditingController popupController = TextEditingController();
    String displayName = _capitalize(_userData['firstName'] ?? widget.username);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => ResponsiveConstraints(
        maxWidth: 450, // Constraint dialog width
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 10,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: lightGold.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryGold.withValues(alpha: 0.2), width: 2),
                  ),
                  child: Image.asset('assets/icon/ai_dogbot.png', height: 70, errorBuilder: (c,e,s) => Icon(Icons.pets, size: 70, color: primaryGold)),
                ),
                const SizedBox(height: 24),
                Text(
                  "Hi $displayName!",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: darkGold),
                ),
                const SizedBox(height: 12),
                const Text(
                  "I pet is online and ready to help you.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 30),
                // INTERACTIVE ASK BAR INSIDE POPUP
                Container(
                  decoration: BoxDecoration(
                    color: lightGold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: primaryGold, width: 1.5),
                    boxShadow: [BoxShadow(color: primaryGold.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: TextField(
                    controller: popupController,
                    autofocus: false,
                    style: TextStyle(color: darkGold, fontWeight: FontWeight.w500),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        Navigator.pop(context);
                        _openChatbot(initialText: val.trim());
                      }
                    },
                    decoration: InputDecoration(
                      hintText: "What would you like today?",
                      hintStyle: TextStyle(color: primaryGold.withValues(alpha: 0.5), fontSize: 14),
                      prefixIcon: Icon(Icons.chat_bubble_rounded, color: primaryGold, size: 22),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: CircleAvatar(
                          backgroundColor: primaryGold,
                          radius: 18,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                            onPressed: () {
                              if (popupController.text.trim().isNotEmpty) {
                                Navigator.pop(context);
                                _openChatbot(initialText: popupController.text.trim());
                              }
                            },
                          ),
                        ),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Maybe Later", style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openChatbot({String? initialText}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PetChatbot(
        userId: widget.userId ?? _auth.currentUser?.uid ?? 'unknown',
        username: _userData['username'] ?? widget.username,
        fullName: _getFullName(),
        initialMessage: initialText,
      ),
    );
  }

  void _showPetDetails(Map pet, int index) {
    showDialog(
      context: context,
      builder: (context) => _PetDetailDialog(
        pet: pet,
        index: index,
        primaryGold: primaryGold,
        darkGold: darkGold,
        lightGold: lightGold,
        onUpdate: (updatedPet) => _updatePet(index, updatedPet),
      ),
    );
  }

  Future<void> _updatePet(int index, Map<String, dynamic> updatedPet) async {
    try {
      String? id = widget.userId ?? _auth.currentUser?.uid;
      if (id != null) {
        List<dynamic> pets = List.from(_userData['pets'] ?? []);
        pets[index] = updatedPet;
        await _database.child('users/$id/pets').set(pets);
        _fetchUserData(); // Refresh local state
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pet information updated successfully!")),
          );
        }
      }
    } catch (e) {
      debugPrint("Update Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading 
        ? const Center(child: CupertinoActivityIndicator())
        : GoldBlobsBackground(
            useSafeArea: false,
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentTabIndex = index;
                  _selectedCategory = null;
                  _searchQuery = "";
                  _searchController.clear();
                });
              },
              children: [
                _KeepAlivePage(child: _buildTabPage(0, topPadding)), // Shop
                _KeepAlivePage(child: _buildTabPage(1, topPadding)), // Services
                _buildTabPage(2, topPadding), // Profile
              ],
            ),
          ),
      floatingActionButton: (_currentTabIndex == 1 && !BookingManager.isEmpty) 
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AppointmentSchedulingScreen(
                userId: widget.userId ?? _auth.currentUser!.uid,
                username: widget.username,
                fullName: _getFullName(),
              ))),
              label: Text("Proceed to Booking (${BookingManager.count})", style: const TextStyle(fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.calendar_month),
              backgroundColor: primaryGold,
            )
          : null,
      bottomNavigationBar: _buildBottomSelector(),
    );
  }

  Widget _buildTabPage(int index, double topPadding) {
    return Column(
      children: [
        _buildHeader(index, topPadding),
        Expanded(
          child: index == 2
              ? _buildProfileTab()
              : RefreshIndicator(
                  onRefresh: () async => _fetchUserData(),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildBanner(index),
                        _buildCategoryBar(index),
                        _buildSectionHeader(index == 0 ? "Daily Discover" : "Available Services"),
                        _buildContentGrid(index),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(int index, double topPadding) {
    if (index == 2) {
      return Container(
        padding: EdgeInsets.only(
          top: topPadding + 10, 
          bottom: 15, 
          left: ResponsiveLayout.isMobile(context) ? 20 : 40, 
          right: ResponsiveLayout.isMobile(context) ? 8 : 40
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [darkGold, primaryGold], 
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Row(
          children: [
            Text("My Profile", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    List<String> hints = index == 0 ? _productHints : _serviceHints;
    String currentHint = hints[_currentHintIndex % hints.length];

    return Container(
      padding: EdgeInsets.only(
        top: topPadding + 10, 
        bottom: 15, 
        left: ResponsiveLayout.isMobile(context) ? 12 : 40, 
        right: ResponsiveLayout.isMobile(context) ? 4 : 40
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [darkGold, primaryGold], 
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: ResponsiveConstraints(
          maxWidth: 1200,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white, 
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 15),
                      Icon(Icons.search, color: primaryGold.withValues(alpha: 0.6), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(fontSize: 14),
                          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                          onTap: () => setState(() => _isSearchFocused = true),
                          onSubmitted: (v) => setState(() => _isSearchFocused = false),
                          decoration: InputDecoration(
                            hintText: _searchController.text.isEmpty ? currentHint : "",
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      // "I PET" AI BUTTON (INSIDE SEARCH BAR)
                      GestureDetector(
                        onTap: () => _openChatbot(),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [lightGold, primaryGold.withValues(alpha: 0.4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset(
                            'assets/icon/ai_dogbot.png', 
                            width: 26, 
                            height: 26, 
                            errorBuilder: (c, e, s) => Icon(Icons.pets, size: 22, color: primaryGold)
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 26),
                    tooltip: "My Cart",
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserCartScreen(
                      userId: widget.userId ?? _auth.currentUser!.uid, 
                      username: widget.username,
                      fullName: _getFullName(),
                    ))),
                  ),
                  StreamBuilder(
                    stream: _database.child('carts/${widget.userId ?? _auth.currentUser!.uid}').onValue,
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                        Map data = snapshot.data!.snapshot.value as Map;
                        return Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text('${data.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveLayout.isMobile(context) ? 20 : 60),
      child: Center(
        child: ResponsiveConstraints(
          maxWidth: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: Colors.grey.shade700), 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => UserSettingsScreen(userId: widget.userId ?? _auth.currentUser?.uid ?? 'unknown', username: widget.username))),
                  ),
                  Stack(
                    children: [
                      IconButton(
                        icon: Icon(Icons.shopping_cart_outlined, color: Colors.grey.shade700), 
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserCartScreen(
                          userId: widget.userId ?? _auth.currentUser!.uid, 
                          username: widget.username,
                          fullName: _getFullName(),
                        ))),
                      ),
                      StreamBuilder(
                        stream: _database.child('carts/${widget.userId ?? _auth.currentUser!.uid}').onValue,
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                            Map data = snapshot.data!.snapshot.value as Map;
                            return Positioned(
                              right: 4,
                              top: 4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: primaryGold, borderRadius: BorderRadius.circular(10)),
                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                child: Text('${data.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                  IconButton(icon: Icon(Icons.notifications_none_rounded, color: Colors.grey.shade700), onPressed: () {}),
                ],
              ),
              const SizedBox(height: 10),
              // Profile Info
              Row(
                children: [
                  CircleAvatar(
                    radius: ResponsiveLayout.isMobile(context) ? 35 : 50,
                    backgroundColor: Colors.blueGrey.shade100,
                    backgroundImage: _userData['profileImage'] != null ? NetworkImage(_userData['profileImage']) : null,
                    child: _userData['profileImage'] == null ? Icon(Icons.person, size: ResponsiveLayout.isMobile(context) ? 45 : 65, color: Colors.grey.shade400) : null,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: MarqueeText(
                      text: _getFullName(),
                      style: TextStyle(
                        fontSize: ResponsiveLayout.isMobile(context) ? 22 : 30, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.black87
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              // My Pets Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("My Pets", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => _showAddPetDialog(),
                    child: const Text("Add a pet", style: TextStyle(color: Colors.black87, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _userData['pets'] == null || (_userData['pets'] as List).isEmpty
                  ? Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primaryGold, width: 2),
                      ),
                      child: const Center(child: Text("Add your first pet!", style: TextStyle(color: Colors.grey))),
                    )
                  : SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: (_userData['pets'] as List).length,
                        itemBuilder: (context, index) {
                          return _buildPetCard((_userData['pets'] as List)[index], index);
                        },
                      ),
                    ),
              const SizedBox(height: 30),
              // My Activities Section
              const Text("My Activities", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildActivityItem(Icons.description_outlined, "My reservations", () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserOrdersScreen(
                userId: widget.userId ?? _auth.currentUser!.uid, 
                username: widget.username,
                fullName: _getFullName(),
              )))),
              _buildActivityItem(Icons.calendar_today_outlined, "My Bookings", () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserAppointmentsScreen(
                userId: widget.userId ?? _auth.currentUser!.uid,
                username: widget.username,
                fullName: _getFullName(),
              )))),
              const SizedBox(height: 30),
              // Upcoming Schedules Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Upcoming Schedules", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserAppointmentsScreen(
                      userId: widget.userId ?? _auth.currentUser!.uid,
                      username: widget.username,
                      fullName: _getFullName(),
                    ))),
                    child: const Text("View all", style: TextStyle(color: Colors.black87, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              _upcomingAppointments.isEmpty
                  ? _buildEmptyBox("book or reserve a product now!!", Icons.calendar_month)
                  : Column(
                      children: _upcomingAppointments.take(2).map((a) => _buildScheduleCard(a)).toList(),
                    ),
              const SizedBox(height: 30),
              // E Prescriptions Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("E Prescriptions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () {},
                    child: const Text("View all", style: TextStyle(color: Colors.black87, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              _prescriptions.isEmpty
                  ? _buildEmptyBox("book now! Get a prescibed medicines by Doctor.", Icons.medical_information)
                  : Column(
                      children: _prescriptions.take(2).map((p) => _buildPrescriptionCard(p)).toList(),
                    ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyBox(String text, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryGold, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: MarqueeText(
              text: text,
              style: const TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetCard(Map pet, int index) {
    String name = pet['name'] ?? 'Pet';
    String species = pet['type'] ?? 'Dog';
    bool isDog = species.toLowerCase() == 'dog';
    return GestureDetector(
      onTap: () => _showPetDetails(pet, index),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryGold, width: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: MarqueeText(
                    text: name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(isDog ? Icons.pets : Icons.pets, size: 18, color: Colors.black87), 
              ],
            ),
            Text(species, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: lightGold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: primaryGold),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      trailing: const Icon(Icons.chevron_right, size: 30, color: Colors.black87),
    );
  }

  Widget _buildScheduleCard(Map schedule) {
    bool isProduct = schedule['isProduct'] ?? false;
    String dateStr = isProduct ? schedule['pickupDate'] : schedule['appointmentDate'];
    DateTime date = DateTime.parse(dateStr);
    
    String titlePrefix = isProduct ? "Reservation" : "Transaction";
    String serviceLabel = isProduct ? "Items" : "Booked service";
    
    String serviceName = schedule['serviceName'] ?? 'N/A';
    if (!isProduct && schedule['services'] != null && schedule['services'] is List) {
       serviceName = (schedule['services'] as List).map((s) => s['name'] ?? 'N/A').join(', ');
    } else if (isProduct) {
       serviceName = schedule['productName'] ?? 'N/A';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeText(
            text: "$titlePrefix # : ${schedule['referenceNumber'] ?? 'N/A'}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          MarqueeText(
            text: "$serviceLabel : $serviceName",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
          ),
          if (!isProduct && schedule['petDetails'] != null)
             MarqueeText(
               text: "Pet(s) : ${schedule['petDetails'] is List ? (schedule['petDetails'] as List).map((p) => p['name'] ?? 'N/A').join(', ') : (schedule['petDetails']['name'] ?? 'N/A')}",
               style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
             ),
          MarqueeText(
            text: "Date : ${DateFormat('MMMM dd, yyyy').format(date)}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
          ),
          MarqueeText(
            text: "Time : ${schedule['startTime'] ?? schedule['pickupTime'] ?? 'N/A'}",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
          ),
          const SizedBox(height: 5),
          const Center(
            child: Text("view details", style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionCard(Map prescription) {
    return GestureDetector(
      onTap: () => _showPrescriptionDetails(prescription),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryGold, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: MarqueeText(
                    text: prescription['petName'] ?? 'Name Of Pet',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                Icon(Icons.medication, color: primaryGold, size: 24),
              ],
            ),
            const SizedBox(height: 5),
            MarqueeText(
              text: "Date : ${prescription['date'] ?? 'N/A'}",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
            ),
            MarqueeText(
              text: "Patient Condition : ${prescription['condition'] ?? 'N/A'}",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text("view details", style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrescriptionDetails(Map prescription) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: primaryGold, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: lightGold.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.medication_liquid, color: primaryGold, size: 50),
              ),
              const SizedBox(height: 20),
              Text(
                "E-Prescription",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: darkGold),
              ),
              const Divider(height: 30, thickness: 1.5),
              if (prescription['prescriptionUrl'] != null) ...[
                Expanded(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      prescription['prescriptionUrl'],
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (c, e, s) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: Colors.red, size: 40),
                          Text("Failed to load prescription image"),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                _prescriptionDetailRow("Pet Name:", prescription['petName'] ?? 'N/A'),
                _prescriptionDetailRow("Date Issued:", prescription['date'] ?? 'N/A'),
                _prescriptionDetailRow("Condition:", prescription['condition'] ?? 'N/A'),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Doctor's Advice & Meds:", style: TextStyle(fontWeight: FontWeight.bold, color: darkGold, fontSize: 16)),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  constraints: const BoxConstraints(minHeight: 100),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: primaryGold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    prescription['prescription'] ?? 'No medicine details recorded.',
                    style: const TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
              const SizedBox(height: 30),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(colors: [darkGold, primaryGold, lightGold]),
                    boxShadow: [
                      BoxShadow(color: primaryGold.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Center(
                    child: Text("Close", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prescriptionDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  void _showAddPetDialog() {
    final TextEditingController nameC = TextEditingController();
    final TextEditingController breedC = TextEditingController();
    final TextEditingController ageC = TextEditingController();
    final TextEditingController bdayC = TextEditingController();
    final TextEditingController weightC = TextEditingController();
    String? species;
    String? sex;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ResponsiveConstraints(
          maxWidth: 500,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryGold, width: 3),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Add a pet", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _dialogField(nameC, "Name"),
                    const SizedBox(height: 10),
                    _dialogField(weightC, "Weight (kg)", keyboardType: TextInputType.number),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _dialogDropdown("Species", species, ['Dog', 'Cat'], (v) {
                            setDialogState(() {
                              species = v;
                            });
                          })
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _dialogEditableDropdown(
                            breedC, 
                            "Breed", 
                            species != null ? (_petBreeds[species] ?? []) : []
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _dialogDropdown("Sex", sex, ['Male', 'Female'], (v) => setDialogState(() => sex = v))),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogField(ageC, "Age", keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _dialogField(
                      bdayC, 
                      "Birthday", 
                      readOnly: true, 
                      onTap: () async {
                        DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: primaryGold,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setDialogState(() => bdayC.text = DateFormat('yyyy-MM-dd').format(picked));
                        }
                      }
                    ),
                    const SizedBox(height: 25),
                    TextButton(
                      onPressed: () {
                        if (nameC.text.isNotEmpty) {
                          _addPet({
                            'name': nameC.text,
                            'type': species ?? 'Other',
                            'breed': breedC.text,
                            'weight': weightC.text,
                            'sex': sex ?? 'N/A',
                            'age': ageC.text,
                            'birthday': bdayC.text,
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: Text("ADD", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryGold)),
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

  Widget _dialogField(TextEditingController ctrl, String hint, {TextInputType? keyboardType, bool readOnly = false, VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
        ),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _dialogDropdown(String hint, String? value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 14)),
          isExpanded: true,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _dialogEditableDropdown(TextEditingController ctrl, String hint, List<String> items) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 14),
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                border: InputBorder.none,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
            padding: EdgeInsets.zero,
            onSelected: (String val) {
              ctrl.text = val;
            },
            itemBuilder: (BuildContext context) {
              return items.map((String choice) {
                return PopupMenuItem<String>(
                  value: choice,
                  child: Text(choice, style: const TextStyle(fontSize: 14)),
                );
              }).toList();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addPet(Map<String, dynamic> newPet) async {
    try {
      String? id = widget.userId ?? _auth.currentUser?.uid;
      if (id != null) {
        List<dynamic> pets = List.from(_userData['pets'] ?? []);
        
        // Generate a unique ID for the pet
        final String petId = "PET-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}";
        newPet['petId'] = petId;

        pets.add(newPet);
        await _database.child('users/$id/pets').set(pets);
        _fetchUserData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pet added!")));
      }
    } catch (e) {
      debugPrint("Add Pet Error: $e");
    }
  }

  Widget _buildBanner(int index) {
    double bannerHeight = ResponsiveLayout.isMobile(context) ? 160 : 300;

    if (_activePromos.isEmpty) {
      return Container(
        width: double.infinity,
        height: bannerHeight,
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(colors: [darkGold, primaryGold, lightGold]),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pets, color: Colors.white, size: 40),
              SizedBox(height: 5),
              Text("Docloy Veterinary Clinic", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    List<String> images = _activePromos.map((v) => v['imageUrl'].toString()).where((url) => url.isNotEmpty).toList();

    if (images.isEmpty) return const SizedBox.shrink();

    // Start timer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBannerTimer(images.length);
    });

    return Container(
      height: bannerHeight,
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: PageView.builder(
          controller: _bannerController,
          itemCount: images.length,
          onPageChanged: (idx) => _currentBannerIndex = idx,
          itemBuilder: (context, index) {
            return Image.network(
              images[index],
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [darkGold, primaryGold])),
                child: const Icon(Icons.broken_image, color: Colors.white),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: darkGold)),
          const Text("See More >", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(int index) {
    String currentType = index == 0 ? 'Products' : 'Services';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 95,
            child: StreamBuilder<DatabaseEvent>(
              stream: _database.child('categories').onValue,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  Map data = snapshot.data!.snapshot.value as Map;
                  
                  // Filter categories based on the current tab (Products or Services)
                  var filteredCategories = data.entries.where((e) {
                    var catData = Map<String, dynamic>.from(e.value as Map);
                    return catData['type'] == currentType;
                  }).toList();

                  return ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _categoryIcon("All", null, isSelected: _selectedCategory == null),
                      ...filteredCategories.map((e) {
                        var catData = Map<String, dynamic>.from(e.value as Map);
                        return _categoryIcon(catData['name'], catData['image'], isSelected: _selectedCategory == catData['name']);
                      }),
                    ],
                  );
                }
                
                // Fallback: If no categories node exists, show items' categories from the respective node
                String node = index == 0 ? 'products' : 'services';
                return StreamBuilder<DatabaseEvent>(
                  stream: _database.child(node).onValue,
                  builder: (context, itemSnap) {
                    if (itemSnap.hasData && itemSnap.data!.snapshot.value != null) {
                      Map data = itemSnap.data!.snapshot.value as Map;
                      Set<String> categories = data.values.map((v) => (v['category'] ?? 'General').toString()).toSet();
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          _categoryIcon("All", null, isSelected: _selectedCategory == null),
                          ...categories.map((cat) => _categoryIcon(cat, null, isSelected: _selectedCategory == cat)),
                        ],
                      );
                    }
                    return const Center(child: CupertinoActivityIndicator());
                  }
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryIcon(String label, String? imageUrl, {bool isSelected = false}) {
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = label == "All" ? null : label),
      child: SizedBox(
        width: 75,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected ? primaryGold.withValues(alpha: 0.1) : Colors.grey.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? primaryGold : Colors.transparent, width: 1.5),
                image: imageUrl != null && imageUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              ),
              child: imageUrl == null || imageUrl.isEmpty
                ? Icon(Icons.category, color: isSelected ? primaryGold : Colors.grey.shade700, size: 28)
                : null,
            ),
            const SizedBox(height: 8),
            MarqueeText(
              text: label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? primaryGold : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentGrid(int index) {
    String node = index == 0 ? 'products' : 'services';
    return ResponsiveConstraints(
      maxWidth: 1400,
      child: StreamBuilder<DatabaseEvent>(
        stream: _database.child(node).onValue,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            Map data = snapshot.data!.snapshot.value as Map;
            var items = data.entries.where((e) {
              bool matchesCat = _selectedCategory == null || e.value['category'] == _selectedCategory;
              bool matchesSearch = _searchQuery.isEmpty || e.value['name'].toString().toLowerCase().contains(_searchQuery);
              return matchesCat && matchesSearch;
            }).toList();

            if (items.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No items found.")));
            }

            // Calculate columns based on width
            int crossAxisCount = 2;
            if (ResponsiveLayout.isDesktop(context)) {
              crossAxisCount = 6;
            } else if (ResponsiveLayout.isTablet(context)) {
              crossAxisCount = 4;
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: ResponsiveLayout.isMobile(context) ? 0.72 : 0.8,
              ),
              itemCount: items.length,
              itemBuilder: (context, gridIndex) {
                return _buildShopeeCard(items[gridIndex].value, items[gridIndex].key, index);
              },
            );
          }
          return const Center(child: Padding(padding: EdgeInsets.all(50), child: CupertinoActivityIndicator()));
        },
      ),
    );
  }

  Widget _buildShopeeCard(dynamic item, String id, int index) {
    bool isProduct = index == 0;
    var promo = _getDiscountFor(id, isProduct);
    
    String priceText = "";
    double originalPrice = (item['price'] ?? 0).toDouble();
    double displayPrice = originalPrice;
    int discountPercent = 0;

    if (promo != null) {
      discountPercent = promo['discountPercent'] ?? 0;
    }

    if (isProduct && item['variations'] != null) {
      List<dynamic> varList = [];
      if (item['variations'] is List) {
        varList = item['variations'];
      } else if (item['variations'] is Map) {
        varList = item['variations'].values.toList();
      }

      if (varList.isNotEmpty) {
        List<double> prices = varList.map<double>((v) => (v['price'] ?? 0).toDouble()).toList();
        prices.sort();
        double minPrice = prices.first;
        double maxPrice = prices.last;

        if (discountPercent > 0) {
          minPrice = minPrice * (1 - discountPercent / 100);
          maxPrice = maxPrice * (1 - discountPercent / 100);
        }

        if (minPrice == maxPrice) {
          priceText = "₱${_formatter.format(minPrice.round())}";
        } else {
          priceText = "₱${_formatter.format(minPrice.round())} - ${_formatter.format(maxPrice.round())}";
        }
      }
    }

    if (priceText.isEmpty) {
      displayPrice = originalPrice * (1 - discountPercent / 100);
      priceText = "₱${_formatter.format(displayPrice.round())}";
    }

    return GestureDetector(
      onTap: () async {
        if (isProduct) {
          await Navigator.push(context, MaterialPageRoute(builder: (c) => ProductViewScreen(
            product: item,
            productId: id,
            userId: widget.userId ?? _auth.currentUser!.uid,
            username: widget.username,
            fullName: _getFullName(),
          )));
        } else {
          await Navigator.push(context, MaterialPageRoute(builder: (c) => ServiceViewScreen(
            service: item,
            serviceId: id,
            userId: widget.userId ?? _auth.currentUser!.uid,
            username: widget.username,
            fullName: _getFullName(),
          )));
        }
        if (mounted) setState(() {});
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: (_dataSaverEnabled)
                      ? const Center(child: Icon(Icons.image_outlined, size: 40, color: Colors.grey))
                      : (item['image'] != null && item['image'].toString().isNotEmpty)
                        ? Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Image.network(item['image'], fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.image, size: 50, color: Colors.grey)),
                          )
                        : const Center(
                            child: Icon(Icons.image, size: 50, color: Colors.grey),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        text: item['name'],
                        style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (promo != null && item['variations'] == null)
                        Text('₱${_formatter.format(originalPrice.round())}', style: const TextStyle(color: Colors.grey, fontSize: 10, decoration: TextDecoration.lineThrough)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(priceText, style: TextStyle(color: primaryGold, fontSize: item['variations'] != null ? 13 : 16, fontWeight: FontWeight.bold)),
                              if (isProduct)
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  icon: Icon(Icons.add_shopping_cart, color: primaryGold, size: 20),
                                  onPressed: () => _addToCart(item, id),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (!isProduct) ...[
                            const Icon(Icons.access_time, size: 10, color: Colors.grey),
                            const SizedBox(width: 2),
                            Text(item['estimatedTime'] ?? 'N/A', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                            const Spacer(),
                            Text('Book Now', style: TextStyle(color: primaryGold, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (promo != null)
              Positioned(
                top: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9),
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomLeft: Radius.circular(8)),
                  ),
                  child: Text('$discountPercent% OFF', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart(dynamic item, String id) async {
    // If the product has variations, navigate to the product view screen to let the user choose.
    if (item['variations'] != null) {
      final uid = widget.userId ?? _auth.currentUser!.uid;
      await Navigator.push(context, MaterialPageRoute(builder: (c) => ProductViewScreen(
        product: item,
        productId: id,
        userId: uid,
        username: widget.username,
        fullName: _getFullName(),
      )));
      if (mounted) setState(() {});
      return;
    }

    final uid = widget.userId ?? _auth.currentUser!.uid;
    final cartRef = _database.child('carts/$uid');
    
    var promo = _getDiscountFor(id, true);
    double originalPrice = (item['price'] ?? 0).toDouble();
    double currentPrice = originalPrice;
    if (promo != null) {
      currentPrice = originalPrice * (1 - (promo['discountPercent'] ?? 0) / 100);
    }
    
    final snapshot = await cartRef.get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      String? existingKey;
      int existingQty = 0;
      
      data.forEach((key, value) {
        // Fix: Check both productId and ensuring no variationName for shortcut adds
        bool sameProduct = value['productId'] == id;
        bool noVariation = value['variationName'] == null;

        if (sameProduct && noVariation) {
          existingKey = key;
          existingQty = value['quantity'] ?? 0;
        }
      });
      
      if (existingKey != null) {
        int newQty = existingQty + 1;
        await cartRef.child(existingKey!).update({
          'quantity': newQty,
          'totalPrice': newQty * currentPrice,
        });
      } else {
        await _pushNewToCart(cartRef, item, id, currentPrice);
      }
    } else {
      await _pushNewToCart(cartRef, item, id, currentPrice);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${item['name']} added to cart"),
        backgroundColor: primaryGold,
      ));
    }
  }

  Future<void> _pushNewToCart(DatabaseReference cartRef, dynamic item, String id, double price) async {
    await cartRef.push().set({
      'productName': item['name'],
      'productId': id, // Save ID for cart price re-calculation
      'quantity': 1,
      'unitPrice': price,
      'totalPrice': price,
      'imageUrl': item['image'],
      'description': item['description'] ?? '',
      'timestamp': ServerValue.timestamp,
    });
  }

  Widget _buildBottomSelector() {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          _navItem(0, "Shop", Icons.storefront),
          _navItem(1, "Services", Icons.medical_services_outlined),
          _navItem(2, "Me", Icons.person_outline),
        ],
      ),
    );
  }

  Widget _navItem(int index, String label, IconData icon) {
    bool isActive = _currentTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? primaryGold : Colors.grey),
            Text(label, style: TextStyle(color: isActive ? primaryGold : Colors.grey, fontSize: 12, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}

class _PetDetailDialog extends StatefulWidget {
  final Map pet;
  final int index;
  final Color primaryGold;
  final Color darkGold;
  final Color lightGold;
  final Function(Map<String, dynamic>) onUpdate;

  const _PetDetailDialog({
    required this.pet,
    required this.index,
    required this.primaryGold,
    required this.darkGold,
    required this.lightGold,
    required this.onUpdate,
  });

  @override
  State<_PetDetailDialog> createState() => _PetDetailDialogState();
}

class _PetDetailDialogState extends State<_PetDetailDialog> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _breedController;
  late TextEditingController _ageController;
  late TextEditingController _birthdayController;
  late TextEditingController _weightController;
  String? _selectedType;
  String? _selectedSex;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.pet['name']);
    _breedController = TextEditingController(text: widget.pet['breed']);
    _ageController = TextEditingController(text: widget.pet['age']);
    _birthdayController = TextEditingController(text: widget.pet['birthday']);
    _weightController = TextEditingController(text: widget.pet['weight']?.toString() ?? '');
    _selectedType = widget.pet['type'];
    _selectedSex = widget.pet['sex'] ?? widget.pet['gender'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _birthdayController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [widget.lightGold.withValues(alpha: 0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: widget.primaryGold.withValues(alpha: 0.3), width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGoldHeader(),
              const SizedBox(height: 20),
              if (_isEditing) _buildEditForm() else _buildInfoDisplay(),
              const SizedBox(height: 24),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoldHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [widget.darkGold, widget.primaryGold]),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: widget.primaryGold.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.pets, color: Colors.white, size: 40),
          const SizedBox(height: 10),
          Text(
            _isEditing ? "Edit Pet Info" : (_nameController.text.isEmpty ? "Pet Info" : _nameController.text),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoDisplay() {
    return Column(
      children: [
        _infoRow(Icons.category_outlined, "Type", _selectedType ?? 'N/A'),
        _infoRow(Icons.pets_outlined, "Breed", _breedController.text.isEmpty ? 'N/A' : _breedController.text),
        _infoRow(Icons.monitor_weight_outlined, "Weight", _weightController.text.isEmpty ? 'N/A' : _weightController.text),
        _infoRow(Icons.transgender_outlined, "Sex", _selectedSex ?? 'N/A'),
        _infoRow(Icons.cake_outlined, "Age", _ageController.text.isEmpty ? 'N/A' : _ageController.text),
        _infoRow(Icons.calendar_today_outlined, "Birthday", _birthdayController.text.isEmpty ? 'N/A' : _birthdayController.text),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: widget.primaryGold, size: 22),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Column(
      children: [
        _editField(_nameController, "Pet Name", Icons.person_outline),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _selectedType,
          items: ['Dog', 'Cat'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _selectedType = v),
          decoration: _inputDecoration("Type", Icons.category_outlined),
        ),
        const SizedBox(height: 10),
        _editField(_breedController, "Breed", Icons.pets_outlined),
        const SizedBox(height: 10),
        _editField(_weightController, "Weight", Icons.monitor_weight_outlined),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _selectedSex,
          items: ['Male', 'Female'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (v) => setState(() => _selectedSex = v),
          decoration: _inputDecoration("Sex", Icons.transgender_outlined),
        ),
        const SizedBox(height: 10),
        _editField(_ageController, "Age", Icons.cake_outlined),
        const SizedBox(height: 10),
        _editField(_birthdayController, "Birthday", Icons.calendar_today_outlined),
      ],
    );
  }

  Widget _editField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: widget.primaryGold),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.primaryGold, width: 2),
      ),
    );
  }

  Widget _buildActions() {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _isEditing = false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                widget.onUpdate({
                  'name': _nameController.text,
                  'type': _selectedType,
                  'breed': _breedController.text,
                  'weight': _weightController.text,
                  'sex': _selectedSex,
                  'age': _ageController.text,
                  'birthday': _birthdayController.text,
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryGold,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text("Close"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit, size: 18, color: Colors.white),
            label: const Text("Edit", style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryGold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}


