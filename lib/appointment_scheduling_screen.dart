import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'booking_manager.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

final Map<String, List<String>> _petBreeds = {
  'Dog': ['Golden Retriever', 'Bulldog', 'Poodle', 'German Shepherd', 'Beagle', 'Chihuahua', 'Labrador', 'Shih Tzu', 'Dachshund', 'Siberian Husky'],
  'Cat': ['Persian', 'Siamese', 'Maine Coon', 'Bengal', 'Ragdoll', 'Sphynx', 'British Shorthair', 'Scottish Fold', 'Abyssinian', 'Burmese'],
};

class AppointmentSchedulingScreen extends StatefulWidget {
  final String? serviceName; 
  final String userId;
  final String username;
  final String? fullName;
  final DateTime? initialDate;
  final String? oldAppointmentId;

  const AppointmentSchedulingScreen({
    super.key,
    this.serviceName,
    required this.userId,
    required this.username,
    this.fullName,
    this.initialDate,
    this.oldAppointmentId,
  });

  @override
  State<AppointmentSchedulingScreen> createState() => _AppointmentSchedulingScreenState();
}

class _AppointmentSchedulingScreenState extends State<AppointmentSchedulingScreen> {
  final _database = FirebaseDatabase.instance.ref();
  final _reasonController = TextEditingController();
  final _hourController = TextEditingController();
  final _minuteController = TextEditingController();
  final _endHourController = TextEditingController();
  final _endMinuteController = TextEditingController();
  String _amPm = "AM";
  String _endAmPm = "AM";
  
  late DateTime _selectedDate;
  String? _selectedSlot; // Stores the start time, e.g., "08:00 AM"
  bool _addBuffer = false; // 30-min buffer
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _selectedServicesList = []; 
  double _totalPrice = 0.0;
  List<Map<String, dynamic>> _availableServices = [];
  
  List<Map<String, dynamic>> _userPets = [];
  List<Map<String, dynamic>> _selectedPets = [];
  String? _clientType;

  Map<String, List<Map<String, String>>> _bookedRanges = {}; 
  Map<String, int> _dailyBookingCount = {}; 
  final int _maxDailyBookings = 10; 

  List<Map<String, dynamic>> _activePromos = [];
  StreamSubscription? _promoSub;

  // Colors
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);
  final _formatter = NumberFormat('#,###');

  // Clinic Closure & Hours Data
  String? _openUntilDate;
  List<String> _closedDates = [];
  Map<String, dynamic> _customHours = {};

  @override
  void dispose() {
    _reasonController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _endHourController.dispose();
    _endMinuteController.dispose();
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
      setState(() {
        _activePromos = promos;
        _recalculatePrices();
      });
    });
  }

  void _recalculatePrices() {
    if (_selectedServicesList.isEmpty) return;

    for (var item in _selectedServicesList) {
      String? serviceId = item['id'];
      if (serviceId == null) continue;

      // Find service in available services to get original price
      var originalService = _availableServices.firstWhere((s) => s['id'] == serviceId, orElse: () => {});
      if (originalService.isEmpty) continue;

      double originalPrice = (originalService['price'] ?? 0.0).toDouble();
      
      // Check for promo
      Map<String, dynamic>? promo;
      for (var p in _activePromos) {
        List targets = p['targets'] ?? [];
        if (targets.any((t) => t['id'] == serviceId)) {
          promo = p;
          break;
        }
      }

      if (promo != null) {
        item['price'] = originalPrice * (1 - (promo['discountPercent'] ?? 0) / 100);
      } else {
        item['price'] = originalPrice;
      }
    }
    _calculateTotal();
  }

  Future<void> _fetchUserPets() async {
    try {
      final snap = await _database.child('users/${widget.userId}/pets').get();
      if (snap.exists) {
        List<dynamic> pets = snap.value as List;
        setState(() {
          _userPets = pets.map((p) => Map<String, dynamic>.from(p)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching pets: $e");
    }
  }

  Future<void> _fetchClinicClosure() async {
    final snap = await _database.child('clinic_closure').get();
    if (snap.exists) {
      Map data = snap.value as Map;
      setState(() {
        _openUntilDate = data['open_until'];
        if (data['closed_dates'] != null) {
          _closedDates = List<String>.from(data['closed_dates']);
        }
        if (data['custom_hours'] != null) {
          _customHours = Map<String, dynamic>.from(data['custom_hours']);
        }
      });
    }
  }

  Future<void> _fetchExistingAppointments() async {
    try {
      final snap = await _database.child('appointments').get();
      if (snap.exists) {
        Map data = snap.value as Map;
        Map<String, List<Map<String, String>>> ranges = {};
        Map<String, int> counts = {};

        data.forEach((key, value) {
          String? status = value['status'];
          if (status == 'Cancelled') return;

          DateTime date = DateTime.parse(value['appointmentDate']);
          String dateKey = DateFormat('yyyy-MM-dd').format(date);
          
          String start = value['startTime'] ?? DateFormat('hh:mm a').format(date);
          String end = value['endTime'] ?? start;

          ranges.putIfAbsent(dateKey, () => []).add({'start': start, 'end': end});
          counts[dateKey] = (counts[dateKey] ?? 0) + 1;
        });

        setState(() {
          _bookedRanges = ranges;
          _dailyBookingCount = counts;
        });
      }
    } catch (e) {
      debugPrint("Error fetching appointments: $e");
    }
  }

  Future<void> _fetchServices() async {
    try {
      final snap = await _database.child('services').get();
      if (snap.exists) {
        Map data = snap.value as Map;
        List<Map<String, dynamic>> services = [];
        data.forEach((key, value) {
          services.add({
            'id': key,
            'name': value['name'],
            'estimatedTime': value['estimatedTime'],
            'price': value['price'],
            'description': value['description'],
            'inclusions': value['inclusions'],
            'packages': value['packages']
          });
        });
        setState(() {
          _availableServices = services;
        });
      }
    } catch (e) {
      debugPrint("Error fetching services: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    _selectedDate = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    if (_selectedDate.isBefore(DateTime(now.year, now.month, now.day))) {
      _selectedDate = DateTime(now.year, now.month, now.day);
    }
    _listenToPromos();
    _fetchServices().then((_) {
      setState(() {
        // Merge from BookingManager cart
        if (!BookingManager.isEmpty) {
          _selectedServicesList = List.from(BookingManager.pendingServices);
        }
        
        // Add specific service from navigation if not already in cart
        if (widget.serviceName != null) {
          bool alreadyAdded = _selectedServicesList.any((s) => s['name'] == widget.serviceName);
          if (!alreadyAdded) {
            _addInitialService(widget.serviceName!);
          }
        }
        
        _calculateTotal();
        _autoSelectEarliestTime();
      });
    });
    _fetchExistingAppointments().then((_) => _autoSelectEarliestTime());
    _fetchClinicClosure();
    _fetchUserPets();
  }

  int _parseDuration(String? durationStr) {
    if (durationStr == null) return 30;
    String clean = durationStr.toLowerCase().replaceAll('(', '').replaceAll(')', '').trim();
    int minutes = 0;
    
    final hrMatch = RegExp(r'(\d+)\s*hr').firstMatch(clean);
    if (hrMatch != null) {
      minutes += int.parse(hrMatch.group(1)!) * 60;
    }
    
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(clean);
    if (minMatch != null) {
      minutes += int.parse(minMatch.group(1)!);
    }
    
    return minutes == 0 ? 30 : minutes;
  }

  int _getTotalDuration() {
    int total = 0;
    for (var s in _selectedServicesList) {
      total += _parseDuration(s['estimatedTime']);
    }
    if (_addBuffer) total += 30;
    return total;
  }

  List<String> _generateAvailableSlots() {
    List<String> slots = [];
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    // Check if weekend or closed date
    bool isWeekend = _selectedDate.weekday == DateTime.saturday || _selectedDate.weekday == DateTime.sunday;
    if (isWeekend || _closedDates.contains(dateKey)) {
      return slots;
    }
    
    if (_openUntilDate != null) {
      DateTime until = DateTime.parse(_openUntilDate!);
      if (_selectedDate.isAfter(until)) {
        return slots;
      }
    }
    
    int limitStart = 8;
    int limitEnd = 17;
    if (_customHours.containsKey(dateKey)) {
      try {
        limitStart = int.parse(_customHours[dateKey]['start'].split(':')[0]);
        limitEnd = int.parse(_customHours[dateKey]['end'].split(':')[0]);
      } catch (e) {}
    }

    int totalMinutesNeeded = _getTotalDuration();
    DateTime now = DateTime.now();
    bool isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(now);

    for (int hour = limitStart; hour < limitEnd; hour++) {
      for (int min = 0; min < 60; min += 30) {
        if (hour == limitEnd - 1 && min > 30) break; // Avoid starting too late
        
        DateTime slotTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, min);
        if (isToday && slotTime.isBefore(now.add(const Duration(minutes: 15)))) continue; // 15min buffer from now

        String slotStr = DateFormat('hh:mm a').format(slotTime);
        
        // Check if this slot + duration fits
        if (_isSlotAvailable(slotTime, totalMinutesNeeded)) {
          slots.add(slotStr);
        }
      }
    }
    return slots;
  }

  bool _isSlotAvailable(DateTime start, int durationMins) {
    String dateKey = DateFormat('yyyy-MM-dd').format(start);
    List<Map<String, String>> existingRanges = _bookedRanges[dateKey] ?? [];
    
    double newStart = start.hour + (start.minute / 60.0);
    double newEnd = newStart + (durationMins / 60.0);

    // Clinic hard limit check
    int limitEnd = 17;
    if (_customHours.containsKey(dateKey)) {
      try { limitEnd = int.parse(_customHours[dateKey]['end'].split(':')[0]); } catch (e) {}
    }
    if (newEnd > limitEnd) return false;

    for (var range in existingRanges) {
      DateTime s = DateFormat('hh:mm a').parse(range['start']!);
      DateTime e = DateFormat('hh:mm a').parse(range['end']!);
      double exStart = s.hour + (s.minute / 60.0);
      double exEnd = e.hour + (e.minute / 60.0);

      if ((newStart < exEnd) && (newEnd > exStart)) return false;
    }
    return true;
  }

  void _autoSelectEarliestTime() {
    List<String> available = _generateAvailableSlots();
    if (available.isNotEmpty) {
      setState(() => _selectedSlot = available.first);
    } else {
      setState(() => _selectedSlot = null);
    }
  }

  void _addInitialService(String serviceName) {
    final service = _availableServices.firstWhere((s) => s['name'] == serviceName, orElse: () => {});
    if (service.isNotEmpty) {
      // Apply discount if any
      double originalPrice = (service['price'] ?? 0.0).toDouble();
      double currentPrice = originalPrice;
      
      Map<String, dynamic>? promo;
      for (var p in _activePromos) {
        List targets = p['targets'] ?? [];
        if (targets.any((t) => t['id'] == service['id'])) {
          promo = p;
          break;
        }
      }
      
      if (promo != null) {
        currentPrice = originalPrice * (1 - (promo['discountPercent'] ?? 0) / 100);
      }

      setState(() {
        _selectedServicesList.add({
          'id': service['id'],
          'name': service['name'],
          'price': currentPrice,
          'estimatedTime': service['estimatedTime'],
          'description': service['description'],
          'inclusions': service['inclusions'],
          'package': 'Standard'
        });
        _calculateTotal();
        _autoSelectEarliestTime();
      });
    }
  }

  void _calculateTotal() {
    double total = 0;
    for (var item in _selectedServicesList) {
      total += (item['price'] ?? 0.0);
    }
    setState(() => _totalPrice = total);
  }

  Future<void> _scheduleAppointment() async {
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    bool isWeekend = _selectedDate.weekday == DateTime.saturday || _selectedDate.weekday == DateTime.sunday;
    
    if (isWeekend || _closedDates.contains(dateKey)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The clinic is closed on this date.')));
      return;
    }
    if (_openUntilDate != null) {
      DateTime until = DateTime.parse(_openUntilDate!);
      if (_selectedDate.isAfter(until)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The clinic is only accepting bookings until a certain date.')));
        return;
      }
    }

    if (_selectedServicesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one service.')));
      return;
    }
    if (_selectedPets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one pet.')));
      return;
    }
    if (_clientType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please confirm your ownership status.')));
      return;
    }

    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an available time slot.')));
      return;
    }

    DateTime startTime = DateFormat('hh:mm a').parse(_selectedSlot!);
    int totalMins = _getTotalDuration();
    DateTime endTime = startTime.add(Duration(minutes: totalMins));

    // Final verification against conflicts
    DateTime fullStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, startTime.hour, startTime.minute);
    if (!_isSlotAvailable(fullStart, totalMins)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sorry, this slot is no longer available. Please pick another.')));
      _autoSelectEarliestTime();
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final refNum = 'SRV-${timestamp.toString().substring(timestamp.toString().length - 7)}';
    String startTimeStr = DateFormat('hh:mm a').format(fullStart);
    String endTimeStr = DateFormat('hh:mm a').format(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, endTime.hour, endTime.minute));

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: Text("Booking Details", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 20),
                  _confirmRow("Transaction # :", refNum),
                  _confirmRow("Client :", widget.fullName ?? widget.username),
                  _confirmRow("Pet(s) :", _selectedPets.map((p) => p['name'] ?? 'N/A').join(', ')),
                  
                  const Divider(),
                  const Text("Services Selected:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ..._selectedServicesList.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text("${s['name']} (${s['package']})", style: const TextStyle(fontSize: 13))),
                        Text("₱${_formatter.format((s['price'] ?? 0).round())}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
                  const Divider(),

                  _confirmRow("Total Price :", "₱${_formatter.format(_totalPrice.round())}"),
                  _confirmRow("Date :", DateFormat('MMM dd, yyyy').format(_selectedDate)),
                  _confirmRow("Time :", "$startTimeStr - $endTimeStr"),
                  const SizedBox(height: 10),
                  const Text("Patient Condition:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(_reasonController.text.isEmpty ? "None" : _reasonController.text, style: const TextStyle(fontSize: 13)),
                  
                  const SizedBox(height: 30),
                  const Text(
                    "Note ! Booked service might be added Final services and charges may vary depending on the patient's required treatment.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.red.shade300, width: 2),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Cancel", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                                SizedBox(width: 8),
                                Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _finalizeBooking(refNum);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.green.shade300, width: 2),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Proceed", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                                SizedBox(width: 8),
                                Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                              ],
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
        ),
      ),
    );
  }

  Future<void> _finalizeBooking(String refNum) async {
    setState(() => _isSubmitting = true);
    try {
      DateTime startTime = DateFormat('hh:mm a').parse(_selectedSlot!);
      int totalMins = _getTotalDuration();
      DateTime endTime = startTime.add(Duration(minutes: totalMins));

      final appointmentDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        startTime.hour,
        startTime.minute,
      );

      final endDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        endTime.hour,
        endTime.minute,
      );

      final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final String startTimeStr = DateFormat('hh:mm a').format(appointmentDate);
      final String endTimeStr = DateFormat('hh:mm a').format(endDateTime);

      // --- ATOMIC SLOT VERIFICATION VIA TRANSACTION ---
      final availabilityRef = _database.child('appointments_availability/$dateKey');
      
      final transactionResult = await availabilityRef.runTransaction((Object? slots) {
        List<dynamic> currentSlots = [];
        if (slots != null) {
          currentSlots = List<dynamic>.from(slots as List);
        }

        double newStart = appointmentDate.hour + (appointmentDate.minute / 60.0);
        double newEnd = newStart + (totalMins / 60.0);

        // Check for overlaps in the current transaction data
        for (var slot in currentSlots) {
          try {
            Map slotMap = slot as Map;
            DateTime s = DateFormat('hh:mm a').parse(slotMap['start']!);
            DateTime e = DateFormat('hh:mm a').parse(slotMap['end']!);
            double exStart = s.hour + (s.minute / 60.0);
            double exEnd = e.hour + (e.minute / 60.0);

            if ((newStart < exEnd) && (newEnd > exStart)) {
              return Transaction.abort(); // Conflict found!
            }
          } catch (e) {
            debugPrint("Transaction parse error: $e");
          }
        }

        // No conflict, add the new slot to availability
        currentSlots.add({
          'start': startTimeStr,
          'end': endTimeStr,
          'ref': refNum,
        });

        return Transaction.success(currentSlots);
      });

      if (!transactionResult.committed) {
        throw "Sorry, this slot was just taken by another user. Please pick a different time.";
      }

      // --- PROCEED WITH FULL BOOKING RECORD ---
      // Final price verification
      double finalTotal = 0;
      List<Map<String, dynamic>> finalServices = [];

      for (var item in _selectedServicesList) {
        String? serviceId = item['id'];
        double originalPrice = (item['price'] ?? 0.0).toDouble();
        
        if (serviceId != null) {
          var original = _availableServices.firstWhere((s) => s['id'] == serviceId, orElse: () => {});
          if (original.isNotEmpty) {
            originalPrice = (item['package'] == 'Standard') 
              ? (original['price'] ?? 0.0).toDouble()
              : originalPrice;
          }
        }

        double currentPrice = originalPrice;
        if (serviceId != null) {
          Map<String, dynamic>? promo;
          for (var p in _activePromos) {
            List targets = p['targets'] ?? [];
            if (targets.any((t) => t['id'] == serviceId)) {
              promo = p;
              break;
            }
          }
          if (promo != null) {
            currentPrice = originalPrice * (1 - (promo['discountPercent'] ?? 0) / 100);
          }
        }

        finalTotal += currentPrice;
        finalServices.add({
          ...item,
          'price': currentPrice,
        });
      }

      await _database.child('appointments').push().set({
        'services': finalServices,
        'price': finalTotal,
        'userId': widget.userId,
        'username': widget.username,
        'clientName': widget.fullName ?? widget.username,
        'appointmentDate': appointmentDate.toIso8601String(),
        'startTime': startTimeStr,
        'endTime': endTimeStr,
        'status': 'Pending',
        'reason': _reasonController.text.trim(),
        'referenceNumber': refNum,
        'clientType': _clientType,
        'petDetails': _selectedPets,
        'timestamp': ServerValue.timestamp,
        'rescheduledFrom': widget.oldAppointmentId, // Link to the old appointment
      });

      // --- CANCEL OLD APPOINTMENT IF THIS IS A RESCHEDULE ---
      if (widget.oldAppointmentId != null) {
        await _database.child('appointments/${widget.oldAppointmentId}').update({
          'status': 'Cancelled',
          'rescheduledTo': refNum, // Link the old record to the new one
        });
      }
      
      if (!mounted) return;
      BookingManager.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment scheduled successfully!')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildTimeSlotGrid() {
    List<String> availableSlots = _generateAvailableSlots();
    
    // Also need to know which slots are "Taken" but within operating hours
    List<String> allPotentialSlots = [];
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    int limitStart = 8;
    int limitEnd = 17;
    if (_customHours.containsKey(dateKey)) {
      try {
        limitStart = int.parse(_customHours[dateKey]['start'].split(':')[0]);
        limitEnd = int.parse(_customHours[dateKey]['end'].split(':')[0]);
      } catch (e) {}
    }

    int durationMins = _getTotalDuration();

    for (int h = limitStart; h < limitEnd; h++) {
      for (int m = 0; m < 60; m += 30) {
        if (h == limitEnd - 1 && m > 30) break;
        
        // Hide slots where START + DURATION exceeds limitEnd (closing time)
        double sTime = h + (m / 60.0);
        double eTime = sTime + (durationMins / 60.0);
        if (eTime > limitEnd) {
          continue; // Filter out physically impossible slots
        }
        
        allPotentialSlots.add(DateFormat('hh:mm a').format(DateTime(0, 0, 0, h, m)));
      }
    }

    if (allPotentialSlots.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text("Selected duration exceeds clinic hours.", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedSlot != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: primaryGold),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Duration: ${_getTotalDuration()} mins", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("End Time: ${DateFormat('hh:mm a').format(DateFormat('hh:mm a').parse(_selectedSlot!).add(Duration(minutes: _getTotalDuration())))}", 
                         style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
                Row(
                  children: [
                    const Text("Add 30m buffer", style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _addBuffer, 
                      onChanged: (v) {
                        setState(() {
                          _addBuffer = v;
                          // If current selection becomes invalid, re-select
                          if (_selectedSlot != null) {
                            DateTime start = DateFormat('hh:mm a').parse(_selectedSlot!);
                            DateTime fullStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, start.hour, start.minute);
                            if (!_isSlotAvailable(fullStart, _getTotalDuration())) {
                              _autoSelectEarliestTime();
                            }
                          }
                        });
                      },
                      activeColor: primaryGold,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
        ],
        SizedBox(
          height: 65,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: allPotentialSlots.length,
            itemBuilder: (context, index) {
              String slot = allPotentialSlots[index];
              bool isAvailable = availableSlots.contains(slot);
              bool isSelected = _selectedSlot == slot;
              
              // Check if it's "Taken" (booked by someone else) or just "Conflict" (duration overlaps)
              bool isBooked = false;
              DateTime start = DateFormat('hh:mm a').parse(slot);
              
              // Re-check overlap specifically for a 30-min block to see if it's "Booked"
              List<Map<String, String>> existingRanges = _bookedRanges[dateKey] ?? [];
              double sTime = start.hour + (start.minute / 60.0);
              for (var range in existingRanges) {
                 DateTime rs = DateFormat('hh:mm a').parse(range['start']!);
                 DateTime re = DateFormat('hh:mm a').parse(range['end']!);
                 double exS = rs.hour + (rs.minute / 60.0);
                 double exE = re.hour + (re.minute / 60.0);
                 if (sTime >= exS && sTime < exE) {
                   isBooked = true;
                   break;
                 }
              }

              Color color;
              Color textColor;
              if (isSelected) {
                color = primaryGold;
                textColor = Colors.white;
              } else if (isAvailable) {
                color = Colors.white;
                textColor = primaryGold;
              } else if (isBooked) {
                color = Colors.grey.shade200;
                textColor = Colors.grey;
              } else {
                color = Colors.red.shade50;
                textColor = Colors.red;
              }
              
              return GestureDetector(
                onTap: isAvailable ? () => setState(() => _selectedSlot = slot) : null,
                child: Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? primaryGold : (isAvailable ? primaryGold : (isBooked ? Colors.grey.shade300 : Colors.red.shade200)),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(slot, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        if (!isAvailable) 
                          Text(
                            isBooked ? "Booked" : "Conflict", 
                            style: TextStyle(color: textColor, fontSize: 8, fontWeight: FontWeight.bold)
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    // Header
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                        Image.asset('assets/icon/DVC.png', height: 40, errorBuilder: (c, e, s) => CircleAvatar(backgroundColor: darkGold, radius: 20, child: const Icon(Icons.pets, color: Colors.white, size: 20))),
                        const SizedBox(width: 10),
                        const Text("Docloy Veterinary Clinic", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text("Schedule Appointment", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    // Selected Service Box
                    _buildServiceHighlight(),
                    const SizedBox(height: 25),
                    const Text("Condition of the patient", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: primaryGold, width: 2)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: primaryGold, width: 2)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: primaryGold, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Text("Your Pet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildPetSelection(),
                    const SizedBox(height: 25),
                    const Text("Date", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildHorizontalDateSelection(),
                    const SizedBox(height: 10),
                    _buildLegend(),
                    const SizedBox(height: 25),
                    const Text("Time Slot", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildTimeSlotGrid(),
                    const SizedBox(height: 25),
                    const Text("Please Check One Below", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildClientTypeCheckboxes(),
                    const SizedBox(height: 30),
                    const Text(
                      "Note ! Booked service might be added Final services and charges may vary depending on the patient's required treatment.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const Center(child: Text("Arrive 10-15 mins earlier than the scheduled time.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500))),
                    const SizedBox(height: 20),
                    _buildSubmitButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceHighlight() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Selected Appointment/s", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 24),
                onPressed: _commitAndAddMore,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedServicesList.isEmpty)
            const Text("No services selected", style: TextStyle(fontSize: 14))
          else
            Column(
              children: _selectedServicesList.asMap().entries.map((entry) {
                int idx = entry.key;
                var s = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showSelectedServiceDetails(serviceMap: s, isAdding: false),
                          child: Text("${s['name']} (${s['package']})", 
                            style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline, color: Colors.black87)
                          ),
                        ),
                      ),
                      Text("₱${_formatter.format((s['price'] ?? 0).round())}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedServicesList.removeAt(idx);
                            _calculateTotal();
                            _autoSelectEarliestTime();
                          });
                        },
                        child: const Icon(Icons.close, size: 16, color: Colors.red),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const Divider(color: Colors.white38),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Price", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("₱${_formatter.format(_totalPrice.round())}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
          const SizedBox(height: 10),
          if (_selectedServicesList.isNotEmpty)
            GestureDetector(
              onTap: () => _showSelectedServiceDetails(serviceMap: _selectedServicesList.last, isAdding: false),
              child: const Text("See full details", style: TextStyle(color: Colors.purple, decoration: TextDecoration.underline, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  void _commitAndAddMore() {
    // Add all current selections to the global BookingManager
    for (var service in _selectedServicesList) {
      BookingManager.addService(service);
    }
    // Return to the previous screen (Services List or Service View)
    Navigator.pop(context);
  }

  Widget _buildPetSelection() {
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._userPets.map((pet) {
            bool isSelected = _selectedPets.contains(pet);
            return GestureDetector(
              onTap: () => setState(() {
                if (isSelected) {
                  _selectedPets.remove(pet);
                } else {
                  _selectedPets.add(pet);
                }
              }),
              child: Container(
                width: 130,
                margin: const EdgeInsets.only(right: 15),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : null,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected ? Border.all(color: primaryGold, width: 3) : null,
                  gradient: isSelected ? null : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "Name of pet", 
                            style: TextStyle(
                              fontSize: 12, 
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.black
                            ), 
                            overflow: TextOverflow.ellipsis
                          )
                        ),
                        Icon(Icons.pets, size: 16, color: isSelected ? primaryGold : Colors.black),
                      ],
                    ),
                    Text(
                      pet['name'], 
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.black
                      )
                    ),
                    const Text("view", style: TextStyle(color: Colors.purple, fontSize: 10, decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: () => _showAddPetDialog(),
            child: Container(
              width: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryGold, width: 3),
              ),
              child: Icon(Icons.add, size: 50, color: primaryGold),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPetDialog() {
    final nameController = TextEditingController();
    final breedController = TextEditingController();
    final ageController = TextEditingController();
    final bdayController = TextEditingController();
    final weightController = TextEditingController();
    String? species;
    String? sex;
    bool isOwnedByMe = true; // Default to owned

    showDialog(
      context: context,
      builder: (context) => ResponsiveConstraints(
        maxWidth: 500,
        child: StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: primaryGold, width: 3),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Add a pet", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _dialogField(nameController, "Name"),
                    const SizedBox(height: 12),
                    _dialogField(weightController, "Weight (kg)", keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
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
                            breedController, 
                            "Breed", 
                            species != null ? (_petBreeds[species] ?? []) : []
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogDropdown("Sex", sex, ['Male', 'Female'], (v) => setDialogState(() => sex = v))),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogField(ageController, "Age", keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      bdayController, 
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
                          setDialogState(() => bdayController.text = DateFormat('yyyy-MM-dd').format(picked));
                        }
                      }
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => setDialogState(() => isOwnedByMe = false),
                          child: Text("Pet owned by another person", 
                            style: TextStyle(
                              fontSize: 10, 
                              decoration: TextDecoration.underline, 
                              fontWeight: FontWeight.bold,
                              color: !isOwnedByMe ? Colors.blue : Colors.black
                            )
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setDialogState(() => isOwnedByMe = true),
                          child: Text("Owned pet", 
                            style: TextStyle(
                              fontSize: 10, 
                              decoration: TextDecoration.underline, 
                              fontWeight: FontWeight.bold,
                              color: isOwnedByMe ? Colors.blue : Colors.black
                            )
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    GestureDetector(
                      onTap: () async {
                        if (nameController.text.isNotEmpty) {
                          Map<String, dynamic> petMap = {
                            'name': nameController.text,
                            'type': species ?? 'Dog',
                            'breed': breedController.text,
                            'weight': weightController.text,
                            'sex': sex ?? 'Male',
                            'age': ageController.text,
                            'birthday': bdayController.text,
                            'isTemporary': !isOwnedByMe // Flag to indicate if it's just for this booking
                          };

                          if (isOwnedByMe) {
                            await _addPet(petMap);
                          } else {
                            // For temporary pets, just add to local list and select it
                            setState(() {
                              _userPets.add(petMap);
                              _selectedPets.add(petMap);
                            });
                          }
                          if (mounted) Navigator.pop(context);
                        }
                      },
                      child: Text("ADD", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGold)),
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
          hint: Text(hint, style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.6))),
          isExpanded: true,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 14)))).toList(),
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
                hintStyle: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.6)),
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

  Future<void> _addPet(Map<String, dynamic> pet) async {
    try {
      List<Map<String, dynamic>> updatedPets = List.from(_userPets);
      
      // Generate a unique ID for the pet
      final String petId = "PET-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}";
      pet['petId'] = petId;

      updatedPets.add(pet);
      await _database.child('users/${widget.userId}/pets').set(updatedPets);
      _fetchUserPets();
    } catch (e) {
      debugPrint("Add pet error: $e");
    }
  }

  void _showSelectedServiceDetails({required Map<String, dynamic> serviceMap, bool isAdding = false}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: primaryGold, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Selected Appoint..", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(serviceMap['name'] ?? "N/A", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Text("Description : ${serviceMap['description'] ?? 'No description'}", style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 5),
                    Text("Estimated Time : ${serviceMap['estimatedTime'] ?? 'N/A'}", style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 5),
                    Text("Inclusions : ${serviceMap['inclusions'] ?? 'All the inclusion for this service'}", style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 5),
                    Text("Price : ₱${_formatter.format((serviceMap['price'] ?? 0).round())}", style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              GestureDetector(
                onTap: () {
                  if (isAdding) {
                    setState(() {
                      _selectedServicesList.add(serviceMap);
                      _calculateTotal();
                      _autoSelectEarliestTime();
                    });
                  }
                  Navigator.pop(context);
                },
                child: Text(isAdding ? "ADD" : "CLOSE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalDateSelection() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 14, // Show next 2 weeks
        itemBuilder: (context, index) {
          DateTime date = DateTime.now().add(Duration(days: index));
          bool isSelected = DateFormat('yyyy-MM-dd').format(date) == DateFormat('yyyy-MM-dd').format(_selectedDate);
          
          String dateKey = DateFormat('yyyy-MM-dd').format(date);
          int count = _dailyBookingCount[dateKey] ?? 0;
          bool isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
          bool isClosed = _closedDates.contains(dateKey) || isWeekend;
          if (_openUntilDate != null && date.isAfter(DateTime.parse(_openUntilDate!))) isClosed = true;

          Color bgColor;
          if (isClosed) {
            bgColor = Colors.grey;
          } else if (count >= _maxDailyBookings) {
            bgColor = Colors.red;
          } else if (count > 0) {
            bgColor = Colors.orange;
          } else {
            bgColor = primaryGold;
          }

          return GestureDetector(
            onTap: isClosed ? null : () {
              setState(() => _selectedDate = date);
              _autoSelectEarliestTime();
            },
            child: Container(
              width: 70,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
                gradient: LinearGradient(colors: [bgColor.withOpacity(0.9), bgColor.withOpacity(0.6)]),
              ),
              child: Center(
                child: Text(
                  DateFormat('MMM dd').format(date),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _legendDot(primaryGold, "Available"),
            _legendDot(Colors.orange, "Has Bookings"),
            _legendDot(Colors.red, "Full"),
            _legendDot(Colors.grey, "Closed"),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(Colors.red.shade100, "Conflict"),
            const SizedBox(width: 20),
            _legendDot(Colors.grey.shade300, "Taken/Booked"),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildManualTimePicker() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          children: [
            _timeBox(_hourController, _minuteController, _amPm, (v) => setState(() => _amPm = v)),
            const Text("Start Time", style: TextStyle(fontSize: 12, color: Colors.black)),
          ],
        ),
        Column(
          children: [
            _timeBox(_endHourController, _endMinuteController, _endAmPm, (v) => setState(() => _endAmPm = v)),
            const Text("End Time", style: TextStyle(fontSize: 12, color: Colors.black)),
          ],
        ),
      ],
    );
  }

  Widget _timeBox(TextEditingController h, TextEditingController m, String ap, Function(String) onAp) {
    return Row(
      children: [
        Container(
          width: 140, // Increased width
          height: 55, // Increased height
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40, 
                child: TextField(
                  controller: h, 
                  textAlign: TextAlign.center, 
                  keyboardType: TextInputType.number, 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), // Larger font
                  decoration: const InputDecoration(hintText: "00", border: InputBorder.none)
                )
              ),
              const Text(":", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), // Larger colon
              SizedBox(
                width: 40, 
                child: TextField(
                  controller: m, 
                  textAlign: TextAlign.center, 
                  keyboardType: TextInputType.number, 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), // Larger font
                  decoration: const InputDecoration(hintText: "00", border: InputBorder.none)
                )
              ),
            ],
          ),
        ),
        const SizedBox(width: 10), // More space
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => onAp("PM"), 
              child: Text("PM", style: TextStyle(fontSize: 16, fontWeight: ap == "PM" ? FontWeight.bold : FontWeight.normal, color: ap == "PM" ? primaryGold : Colors.grey)) // Larger AM/PM
            ),
            const SizedBox(height: 5),
            GestureDetector(
              onTap: () => onAp("AM"), 
              child: Text("AM", style: TextStyle(fontSize: 16, fontWeight: ap == "AM" ? FontWeight.bold : FontWeight.normal, color: ap == "AM" ? primaryGold : Colors.grey)) // Larger AM/PM
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClientTypeCheckboxes() {
    return Column(
      children: [
        _consentOption(
          "I am the legal owner of the above mentioned pet(s).",
          "I hereby give Doc Loy Veterinary Clinic full and complete authority to check and administer treatment to the said patient/animal. I understand further that whatever be the result(s) of the treatment, Doc Loy Veterinary Clinic will not be liable to any charge than myself.",
          "Legal Owner"
        ),
        _consentOption(
          "I am NOT the owner of the above mentioned pet(s).",
          "The owner has given me full responsibility and permission to give Doc Loy Veterinary Clinic full and complete authority to check and administer treatment to the said patient/animal. We understand that whatever be the result(s) of the treatment, Doc Loy Veterinary Clinic will not be liable to any charge than ourselves.",
          "Not Owner"
        ),
        _consentOption(
          "I am under 18 years old.",
          "I have my parent’s approval and authorization regarding my pet’s check-up and treatment. I understand further that whatever be the result(s) of the treatment, Doc Loy Veterinary Clinic will not be liable to any charge than myself.",
          "Under 18"
        ),
      ],
    );
  }

  Widget _consentOption(String title, String sub, String type) {
    bool isSelected = _clientType == type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _clientType = type),
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                border: Border.all(color: primaryGold, width: 2.5), 
                borderRadius: BorderRadius.circular(6)
              ),
              child: isSelected ? Icon(Icons.check, size: 20, color: primaryGold) : null,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 5),
                Text(sub, style: const TextStyle(fontSize: 15, height: 1.3, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSubmitting ? null : _scheduleAppointment,
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
        ),
        child: Center(
          child: _isSubmitting 
            ? const CircularProgressIndicator(color: Colors.white) 
            : Text(
                _selectedSlot == null ? "Pick a Time Slot" : "Book for ${_selectedSlot!}", 
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
              ),
        ),
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
