import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class ProductReservationScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? fullName;
  final List<Map<String, dynamic>> initialProducts;

  const ProductReservationScreen({
    super.key,
    required this.userId,
    required this.username,
    this.fullName,
    required this.initialProducts,
  });

  @override
  State<ProductReservationScreen> createState() => _ProductReservationScreenState();
}

class _ProductReservationScreenState extends State<ProductReservationScreen> {
  final _database = FirebaseDatabase.instance.ref();
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _activePromos = [];
  Map<String, dynamic> _allProducts = {};
  StreamSubscription? _promoSub;
  StreamSubscription? _prodSub;
  
  late DateTime _selectedDate;
  
  // Time Picker States
  int _startHour = 8;
  int _startMinute = 0;
  String _startAmPm = "AM";
  
  int _endHour = 9;
  int _endMinute = 0;
  String _endAmPm = "AM";

  // Clinic Closure Data
  String? _openUntilDate;
  List<String> _closedDates = [];
  Map<String, dynamic> _customHours = {};
  
  // Booking status tracking
  Map<String, int> _dailyBookingCount = {}; 
  final int _maxDailyBookings = 10; 

  // Multi-Product State
  late List<Map<String, dynamic>> _products;
  Map<String, int> _actualStocks = {};

  // Colors
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);
  final _formatter = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _products = _mergeProducts(widget.initialProducts);
    DateTime now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _listenToData();
    _fetchClinicClosure();
    _fetchExistingBookings();
    _fetchActualStocks();
  }

  @override
  void dispose() {
    _promoSub?.cancel();
    _prodSub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _mergeProducts(List<Map<String, dynamic>> initial) {
    Map<String, Map<String, dynamic>> merged = {};
    for (var p in initial) {
      // Use productId and variationName to uniquely identify item
      String productId = p['productId']?.toString() ?? 'unknown';
      String variationName = p['variationName']?.toString() ?? 'none';
      String key = "${productId}_$variationName";
      
      if (merged.containsKey(key)) {
        merged[key]!['quantity'] = (merged[key]!['quantity'] ?? 0) + (p['quantity'] ?? 0);
      } else {
        merged[key] = Map<String, dynamic>.from(p);
      }
    }
    return merged.values.toList();
  }

  void _listenToData() {
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

    _prodSub = _database.child('products').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists) {
        setState(() {
          _allProducts = Map<String, dynamic>.from(event.snapshot.value as Map);
        });
      }
    });
  }

  double _calculateCurrentPrice(Map<String, dynamic> p) {
    String? productId = p['productId'];
    String? variationName = p['variationName'];
    
    if (productId == null || !_allProducts.containsKey(productId)) {
      return (p['price'] ?? 0).toDouble();
    }

    var product = _allProducts[productId];
    double originalPrice = (product['price'] ?? 0).toDouble();
    
    if (variationName != null && product['variations'] != null) {
      var vars = product['variations'];
      List<dynamic> varList = vars is List ? vars : (vars is Map ? vars.values.toList() : []);
      var v = varList.firstWhere((element) => element['name'] == variationName, orElse: () => null);
      if (v != null) originalPrice = (v['price'] ?? 0).toDouble();
    }

    Map<String, dynamic>? promo;
    for (var activePromo in _activePromos) {
      List targets = activePromo['targets'] ?? [];
      for (var target in targets) {
        if (target['id'] == productId) {
          if (target['applyToAll'] == true) {
            promo = activePromo;
            break;
          }
          List selectedVars = target['selectedVariations'] ?? [];
          if (variationName != null && selectedVars.contains(variationName)) {
            promo = activePromo;
            break;
          }
        }
      }
      if (promo != null) break;
    }

    if (promo != null) {
      return originalPrice * (1 - (promo['discountPercent'] ?? 0) / 100);
    }
    
    return originalPrice;
  }

  Future<void> _fetchActualStocks() async {
    for (var p in _products) {
      final baseName = p['baseName'] ?? p['productName'];
      final snap = await _database.child('products').orderByChild('name').equalTo(baseName).get();
      if (snap.exists) {
        final data = snap.children.first.value as Map;
        int stock = 0;
        if (p['variationName'] != null && data['variations'] != null) {
          var vars = data['variations'];
          if (vars is List) {
            for (var v in vars) {
              if (v['name'] == p['variationName']) {
                stock = v['quantity'] ?? 0;
                break;
              }
            }
          } else if (vars is Map) {
            for (var v in vars.values) {
              if (v['name'] == p['variationName']) {
                stock = v['quantity'] ?? 0;
                break;
              }
            }
          }
        } else {
          stock = data['quantity'] ?? 0;
        }
        setState(() {
          _actualStocks[p['productName']] = stock;
        });
      }
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

  Future<void> _fetchExistingBookings() async {
    final apptSnap = await _database.child('appointments').get();
    final resSnap = await _database.child('product_reservations').get();
    
    Map<String, int> counts = {};
    
    if (apptSnap.exists) {
      Map data = apptSnap.value as Map;
      data.forEach((k, v) {
        if (v['status'] != 'Cancelled' && v['appointmentDate'] != null) {
          try {
            String date = DateFormat('yyyy-MM-dd').format(DateTime.parse(v['appointmentDate']));
            counts[date] = (counts[date] ?? 0) + 1;
          } catch(e) {}
        }
      });
    }
    
    if (resSnap.exists) {
      Map data = resSnap.value as Map;
      data.forEach((k, v) {
        if (v['status'] != 'Cancelled' && v['status'] != 'Rejected' && v['pickupDate'] != null) {
          String date = v['pickupDate'];
          counts[date] = (counts[date] ?? 0) + 1;
        }
      });
    }

    setState(() => _dailyBookingCount = counts);
  }

  void _showReservationConfirmation() {
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String pickupTime = "$_startHour:${_startMinute == 0 ? "00" : "30"} $_startAmPm - $_endHour:${_endMinute == 0 ? "00" : "30"} $_endAmPm";

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final refNum = 'PRD-${timestamp.toString().substring(timestamp.toString().length - 7)}';

    double totalAmount = 0;
    for (var p in _products) {
      double currentPrice = _calculateCurrentPrice(p);
      totalAmount += (currentPrice * p['quantity']);
    }

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
                  const Center(child: Text("Reserve Product", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 20),
                  _confirmRow("Transaction # :", refNum),
                  _confirmRow("Client :", widget.fullName ?? widget.username),
                  
                  const Divider(),
                  ..._products.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            color: Colors.grey.shade100,
                          ),
                          child: p['imageUrl'] != null && p['imageUrl'] != ''
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Image.network(p['imageUrl'], fit: BoxFit.cover),
                              )
                            : const Icon(Icons.shopping_bag, size: 20, color: Colors.grey),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['productName'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              if (p['variationName'] != null)
                                Text(p['variationName'], style: TextStyle(fontSize: 11, color: primaryGold, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Text("x${p['quantity']}", style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 10),
                        Text("₱${_formatter.format((_calculateCurrentPrice(p) * p['quantity']).round())}", style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  )),
                  const Divider(),

                  _confirmRow("Total Price :", "₱${_formatter.format(totalAmount.round())}"),
                  _confirmRow("Date :", DateFormat('MMM dd, yyyy').format(_selectedDate)),
                  _confirmRow("Prefered time pick-up :", pickupTime),
                  const SizedBox(height: 30),
                  const Text(
                    "Note ! Please provide your accurate details and claim your reserved product(s) within the given deadline, or the item will automatically return to stock.",
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
                            _finalizeReservation(refNum);
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

  Future<void> _finalizeReservation(String refNum) async {
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String pickupTime = "$_startHour:${_startMinute == 0 ? "00" : "30"} $_startAmPm - $_endHour:${_endMinute == 0 ? "00" : "30"} $_endAmPm";

    setState(() => _isSubmitting = true);
    try {
      final Map<String, dynamic> updates = {};
      double totalAmount = 0;
      List<Map<String, dynamic>> finalItems = [];

      // 1. Prepare All Updates (Stock, Cart, Reservation)
      for (var p in _products) {
        final productId = p['productId'];
        // Double check existence to prevent "cannot be found" errors
        if (productId == null || !_allProducts.containsKey(productId)) {
          throw 'Product "${p['productName']}" is no longer available in our shop.';
        }

        final baseName = p['baseName'] ?? p['productName'];
        
        // Stock Validation & Calculation
        final productSnap = await _database.child('products').orderByChild('name').equalTo(baseName).get();
        if (!productSnap.exists) throw 'Product $baseName not found';
        
        DataSnapshot pDoc = productSnap.children.first;
        String pKey = pDoc.key!;
        Map pData = pDoc.value as Map;

        if (p['variationName'] != null && pData['variations'] != null) {
          var vars = pData['variations'];
          bool found = false;
          // Handle both List and Map for variations
          if (vars is List) {
            for (int i = 0; i < vars.length; i++) {
              if (vars[i]['name'] == p['variationName']) {
                int currentStock = vars[i]['quantity'] ?? 0;
                if (p['quantity'] > currentStock) throw 'Not enough stock for ${p['productName']}';
                vars[i]['quantity'] = currentStock - p['quantity'];
                found = true;
                break;
              }
            }
          } else if (vars is Map) {
            for (var key in vars.keys) {
               if (vars[key]['name'] == p['variationName']) {
                 int currentStock = vars[key]['quantity'] ?? 0;
                 if (p['quantity'] > currentStock) throw 'Not enough stock for ${p['productName']}';
                 vars[key]['quantity'] = currentStock - p['quantity'];
                 found = true;
                 break;
               }
            }
          }
          if (!found) throw 'Variation ${p['variationName']} not found';
          updates['products/$pKey/variations'] = vars;
        } else {
          int currentStock = pData['quantity'] ?? 0;
          if (p['quantity'] > currentStock) throw 'Not enough stock for ${p['productName']}';
          updates['products/$pKey/quantity'] = currentStock - p['quantity'];
        }

        // Cart Removal
        if (p['cartItemId'] != null) {
          updates['carts/${widget.userId}/${p['cartItemId']}'] = null;
        }

        double unitPrice = _calculateCurrentPrice(p);
        totalAmount += (unitPrice * p['quantity']);
        finalItems.add({
          'productName': p['productName'],
          'baseName': baseName,
          'productId': p['productId'],
          'variationName': p['variationName'],
          'quantity': p['quantity'],
          'unitPrice': unitPrice,
          'totalPrice': unitPrice * p['quantity'],
        });
      }

      // 2. Prepare Reservation Entry
      final reservationKey = _database.child('product_reservations').push().key;
      updates['product_reservations/$reservationKey'] = {
        'items': finalItems,
        'productName': finalItems.length == 1 ? finalItems[0]['productName'] : "${finalItems.length} Products",
        'userId': widget.userId,
        'username': widget.username,
        'clientName': widget.fullName ?? widget.username,
        'totalPrice': totalAmount,
        'pickupDate': dateKey,
        'pickupTime': pickupTime,
        'paymentMethod': 'Free Reservation',
        'referenceNumber': refNum,
        'status': 'Reserved',
        'timestamp': ServerValue.timestamp,
      };

      // 3. Execute Atomic Multi-Path Update
      await _database.update(updates);

      if (!mounted) return;
      _showFinalSuccessDialog();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showFinalSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.check_circle, color: Colors.green, size: 60),
        content: const Text('Product(s) reserved successfully! Please visit the clinic during your chosen slot.', textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('OK')),
        ],
      ),
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
                    const Text("Product Reservation", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    // Product List
                    ...List.generate(_products.length, (index) => _buildProductCard(index)),
                    
                    const SizedBox(height: 25),
                    const Text("Date", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildHorizontalDateSelection(),
                    const SizedBox(height: 10),
                    _buildLegend(),
                    
                    const SizedBox(height: 25),
                    const Center(child: Text("Set Pick Up Time", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 15),
                    _buildTimePickerRange(),
                    
                    const SizedBox(height: 30),
                    _buildOrderSummary(),

                    const SizedBox(height: 50),
                    const Center(child: Text("This service is entirely free, and no additional fees will be added to the product price.", 
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500))),
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

  Widget _buildProductCard(int index) {
    var p = _products[index];
    int stock = _actualStocks[p['productName']] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold, width: 2),
        color: Colors.white.withOpacity(0.9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: p['imageUrl'] != null && p['imageUrl'].isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(p['imageUrl'], fit: BoxFit.cover),
                )
              : const Icon(Icons.shopping_bag_outlined, color: Colors.grey, size: 30),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['productName'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 4),
                Text(p['description'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("₱${_formatter.format(p['price'].round())}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                    Row(
                      children: [
                        _qtyBtn(Icons.remove, () {
                          if (p['quantity'] > 1) {
                            setState(() => p['quantity']--);
                          }
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text("${p['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        _qtyBtn(Icons.add, () {
                          if (p['quantity'] < stock) {
                            setState(() => p['quantity']++);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reached maximum available stock'), duration: Duration(seconds: 1)));
                          }
                        }),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: primaryGold.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: darkGold),
      ),
    );
  }

  Widget _buildOrderSummary() {
    double total = 0;
    for (var p in _products) {
      total += (p['price'] * p['quantity']);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Order Summary", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        ..._products.map((p) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: Colors.white,
                ),
                child: p['imageUrl'] != null && p['imageUrl'] != ''
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.network(p['imageUrl'], fit: BoxFit.cover),
                    )
                  : const Icon(Icons.shopping_bag, size: 15, color: Colors.grey),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text("${p['productName']} (x${p['quantity']})", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              Text("₱ ${_formatter.format((p['price'] * p['quantity']).round())}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        )),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Amount :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("₱ ${_formatter.format(total.round())}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalDateSelection() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 14, 
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
            onTap: isClosed ? null : () => setState(() => _selectedDate = date),
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
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _legendDot(primaryGold, "Available"),
        _legendDot(Colors.orange, "Has Bookings"),
        _legendDot(Colors.red, "Full"),
        _legendDot(Colors.grey, "Closed"),
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

  Widget _buildTimePickerRange() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const Text("FROM", style: TextStyle(fontWeight: FontWeight.bold)),
        _timeDisplayBox(isStart: true),
        const Text("TO", style: TextStyle(fontWeight: FontWeight.bold)),
        _timeDisplayBox(isStart: false),
      ],
    );
  }

  Widget _timeDisplayBox({required bool isStart}) {
    int h = isStart ? _startHour : _endHour;
    int m = isStart ? _startMinute : _endMinute;
    String ap = isStart ? _startAmPm : _endAmPm;

    return GestureDetector(
      onTap: () => _showScrollTimePicker(isStart),
      child: Container(
        width: 130,
        height: 45,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(colors: [darkGold, lightGold]),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("${h.toString().padLeft(2, '0')}:${m == 0 ? "00" : "30"}", 
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() {
                if (isStart) _startAmPm = _startAmPm == "AM" ? "PM" : "AM";
                else _endAmPm = _endAmPm == "AM" ? "PM" : "AM";
              }),
              child: Text(ap, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showScrollTimePicker(bool isStart) {
    List<int> amHours = [8, 9, 10, 11];
    List<int> pmHours = [12, 1, 2, 3, 4, 5];
    
    int currentH = isStart ? _startHour : _endHour;
    int currentM = isStart ? _startMinute : _endMinute;
    String currentAP = isStart ? _startAmPm : _endAmPm;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 250,
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                  Text("Pick ${isStart ? "Start" : "End"} Time", style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Done")),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(
                        initialItem: (currentAP == "AM" ? amHours : pmHours).indexOf(currentH).clamp(0, 10)
                      ),
                      onSelectedItemChanged: (idx) {
                        setState(() {
                          if (currentAP == "AM") {
                            if (isStart) _startHour = amHours[idx]; else _endHour = amHours[idx];
                          } else {
                            if (isStart) _startHour = pmHours[idx]; else _endHour = pmHours[idx];
                          }
                        });
                      },
                      children: (currentAP == "AM" ? amHours : pmHours).map((h) => Center(child: Text("$h"))).toList(),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(initialItem: currentM == 0 ? 0 : 1),
                      onSelectedItemChanged: (idx) {
                        setState(() {
                          if (isStart) _startMinute = idx == 0 ? 0 : 30;
                          else _endMinute = idx == 0 ? 0 : 30;
                        });
                      },
                      children: [const Center(child: Text("00")), const Center(child: Text("30"))],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSubmitting ? null : () {
        int sMil = _startHour;
        if (_startAmPm == "PM" && _startHour != 12) sMil += 12;
        if (_startAmPm == "AM" && _startHour == 12) sMil = 0;
        
        int eMil = _endHour;
        if (_endAmPm == "PM" && _endHour != 12) eMil += 12;
        if (_endAmPm == "AM" && _endHour == 12) eMil = 0;

        if (eMil < sMil || (eMil == sMil && _endMinute <= _startMinute)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TO time must be after FROM time.')));
          return;
        }

        _showReservationConfirmation();
      },
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(colors: [darkGold, lightGold, primaryGold]),
        ),
        child: Center(
          child: _isSubmitting 
            ? const CircularProgressIndicator(color: Colors.white) 
            : const Text("Reserve Product", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
