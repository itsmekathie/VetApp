import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'appointment_scheduling_screen.dart';
import 'booking_manager.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';
import 'widgets/pet_setup_modal.dart';

class ServiceViewScreen extends StatefulWidget {
  final dynamic service;
  final String serviceId;
  final String userId;
  final String username;
  final String? fullName;

  const ServiceViewScreen({
    super.key,
    required this.service,
    required this.serviceId,
    required this.userId,
    required this.username,
    this.fullName,
  });

  @override
  State<ServiceViewScreen> createState() => _ServiceViewScreenState();
}

class _ServiceViewScreenState extends State<ServiceViewScreen> {
  final _database = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> _activePromos = [];
  StreamSubscription? _promoSub;
  
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
  final Color lightGold = const Color(0xFFFBDB83);
  final _formatter = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _listenToPromos();
  }

  @override
  void dispose() {
    _promoSub?.cancel();
    super.dispose();
  }

  void _listenToPromos() {
    _promoSub = _database.child('promotions').onValue.listen((event) {
      if (!mounted) return;
      List<Map<String, dynamic>> promos = [];
      if (event.snapshot.exists) {
        Map data = event.snapshot.value as Map;
        data.forEach((key, value) {
          var promo = Map<String, dynamic>.from(value);
          promo['id'] = key;
          int validUntil = promo['validUntil'] ?? 0;
          if (promo['isActive'] != false && DateTime.now().millisecondsSinceEpoch < validUntil) {
            promos.add(promo);
          }
        });
      }
      setState(() => _activePromos = promos);
    });
  }

  Map<String, dynamic>? _getDiscount() {
    for (var promo in _activePromos) {
      List targets = promo['targets'] ?? [];
      for (var target in targets) {
        if (target['id'] == widget.serviceId) return promo;
      }
    }
    return null;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: Stack(
          children: [
            SafeArea(
              child: ResponsiveConstraints(
                maxWidth: 1200,
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                          const Text("Service Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      child: ResponsiveLayout(
                        mobile: _buildMobileLayout(),
                        tablet: _buildDesktopLayout(),
                        desktop: _buildDesktopLayout(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom Buttons
            _buildBottomActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildServiceImage(),
          const SizedBox(height: 30),
          _buildServiceInfo(),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: _buildServiceImage(height: 400)),
          const SizedBox(width: 40),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildServiceInfo(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceImage({double height = 250}) {
    return Center(
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: widget.service['image'] != null && widget.service['image'] != ''
            ? Image.network(widget.service['image'], fit: BoxFit.cover)
            : const Icon(Icons.medical_services_outlined, size: 100, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildServiceInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Price & Title Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.service['name'] ?? 'N/A', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(widget.service['category'] ?? 'General', style: TextStyle(fontSize: 16, color: darkGold, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_getDiscount() != null)
                  Text(
                    "₱${_formatter.format(widget.service['price']?.round() ?? 0)}",
                    style: const TextStyle(fontSize: 16, color: Colors.grey, decoration: TextDecoration.lineThrough),
                  ),
                Text(
                  "₱${_formatter.format(((widget.service['price'] ?? 0) * (1 - (_getDiscount()?['discountPercent'] ?? 0) / 100)).round())}", 
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryGold)
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Time Info
        Row(
          children: [
            Icon(Icons.access_time_filled, color: primaryGold, size: 20),
            const SizedBox(width: 8),
            Text("Estimated Time: ${widget.service['estimatedTime'] ?? 'N/A'}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
          ],
        ),
        
        const SizedBox(height: 30),
        const Text("Description", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          widget.service['description'] ?? 'No description provided.',
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
        ),
        
        const SizedBox(height: 25),
        const Text("Inclusions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          widget.service['inclusions'] ?? 'All necessary checkups and treatments for this session.',
          style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.4, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  void _checkPetsAndProceed() async {
    final database = FirebaseDatabase.instance.ref();
    final snap = await database.child('users/${widget.userId}/pets').get();
    
    if (snap.exists && (snap.value as List).isNotEmpty) {
      _proceedToBooking();
    } else {
      _showPetPrompt();
    }
  }

  void _showPetPrompt() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: primaryGold, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Want to book a pet service?\nAdd your pet now!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primaryGold, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text("Later", style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _showPetSetupModal();
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(colors: [darkGold, primaryGold]),
                        ),
                        child: const Center(
                          child: Text("Go", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPetSetupModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PetSetupModal(
        userId: widget.userId,
        onPetAdded: () {
          // After adding pet, we can either stay here or proceed.
          // User said: "back to services na sya"
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pet added successfully!")),
          );
        },
      ),
    );
  }

  void _proceedToBooking() {
    Navigator.push(context, MaterialPageRoute(builder: (c) => AppointmentSchedulingScreen(
      serviceName: widget.service['name'],
      userId: widget.userId,
      username: widget.username,
      fullName: widget.fullName,
    )));
  }

  Widget _buildBottomActionButtons() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Center(
        child: ResponsiveConstraints(
          maxWidth: 1200,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      BookingManager.addService({
                        'id': widget.serviceId,
                        'name': widget.service['name'],
                        'price': ((widget.service['price'] ?? 0) * (1 - (_getDiscount()?['discountPercent'] ?? 0) / 100)).toDouble(),
                        'estimatedTime': widget.service['estimatedTime'],
                        'description': widget.service['description'],
                        'inclusions': widget.service['inclusions'],
                        'package': 'Standard'
                      });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${widget.service['name']} added to selection!")));
                      Navigator.pop(context); // Return to Services list
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: primaryGold, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text("Add to Booking", style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: GestureDetector(
                    onTap: _checkPetsAndProceed,
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(colors: [darkGold, primaryGold]),
                      ),
                      child: const Center(
                        child: Text("Book Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
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
