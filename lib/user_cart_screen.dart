import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'product_reservation_screen.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class UserCartScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? fullName;

  const UserCartScreen({
    super.key, 
    required this.userId, 
    required this.username,
    this.fullName,
  });

  @override
  State<UserCartScreen> createState() => _UserCartScreenState();
}

class _UserCartScreenState extends State<UserCartScreen> {
  final _database = FirebaseDatabase.instance.ref();
  bool _isCheckingOut = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = {};
  final _formatter = NumberFormat('#,###');
  
  List<Map<String, dynamic>> _activePromos = [];
  Map<String, dynamic> _allProducts = {};
  StreamSubscription? _promoSub;
  StreamSubscription? _prodSub;

  @override
  void initState() {
    super.initState();
    _listenToData();
  }

  @override
  void dispose() {
    _promoSub?.cancel();
    _prodSub?.cancel();
    super.dispose();
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
          _allProducts = (event.snapshot.value as Map).cast<String, dynamic>();
        });
      }
    });
  }

  double _calculateCurrentPrice(dynamic cartItem) {
    String? productId = cartItem['productId'];
    String? variationName = cartItem['variationName'];
    
    if (productId == null || !_allProducts.containsKey(productId)) {
      return (cartItem['unitPrice'] ?? 0).toDouble();
    }

    var product = _allProducts[productId];
    double originalPrice = (product['price'] ?? 0).toDouble();
    
    // Check variations for original price
    if (variationName != null && product['variations'] != null) {
      var vars = product['variations'];
      List<dynamic> varList = vars is List ? vars : (vars is Map ? vars.values.toList() : []);
      var v = varList.firstWhere((element) => element['name'] == variationName, orElse: () => null);
      if (v != null) originalPrice = (v['price'] ?? 0).toDouble();
    }

    // Find active promo
    Map<String, dynamic>? promo;
    for (var p in _activePromos) {
      List targets = p['targets'] ?? [];
      for (var target in targets) {
        if (target['id'] == productId) {
          if (target['applyToAll'] == true) {
            promo = p;
            break;
          }
          List selectedVars = target['selectedVariations'] ?? [];
          if (variationName != null && selectedVars.contains(variationName)) {
            promo = p;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        backgroundColor: const Color(0xFFB8860B),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) _selectedItems.clear();
              });
            },
            child: Text(
              _isSelectionMode ? 'Cancel' : 'Select',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: ResponsiveConstraints(
          maxWidth: 800, // Constrain cart list for Tablet/Desktop
          child: StreamBuilder(
            stream: _database.child('carts/${widget.userId}').onValue,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                Map data = snapshot.data!.snapshot.value as Map;
                var cartItems = data.entries.toList();

                double total = 0;
                for (var entry in cartItems) {
                  String? productId = entry.value['productId'];
                  bool isProductValid = productId != null && _allProducts.containsKey(productId);
                  
                  if (isProductValid) {
                    double currentUnitPrice = _calculateCurrentPrice(entry.value);
                    int qty = entry.value['quantity'] ?? 1;
                    if (!_isSelectionMode || _selectedItems.contains(entry.key)) {
                      total += (currentUnitPrice * qty);
                    }
                  }
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.all(ResponsiveLayout.isMobile(context) ? 16 : 24),
                        itemCount: cartItems.length,
                        itemBuilder: (context, index) {
                          var item = cartItems[index].value;
                          var itemId = cartItems[index].key;
                          bool isSelected = _selectedItems.contains(itemId);
                          
                          String? productId = item['productId'];
                          bool isProductValid = productId != null && _allProducts.containsKey(productId);
                          
                          double currentUnitPrice = _calculateCurrentPrice(item);
                          double currentTotal = currentUnitPrice * (item['quantity'] ?? 1);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              onTap: (_isSelectionMode && isProductValid) ? () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedItems.remove(itemId);
                                  } else {
                                    _selectedItems.add(itemId);
                                  }
                                });
                              } : null,
                              leading: _isSelectionMode
                                  ? Checkbox(
                                      value: isSelected,
                                      activeColor: isProductValid ? const Color(0xFFB8860B) : Colors.grey,
                                      onChanged: isProductValid ? (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedItems.add(itemId);
                                          } else {
                                            _selectedItems.remove(itemId);
                                          }
                                        });
                                      } : null,
                                    )
                                  : Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey.shade100,
                                      ),
                                      child: item['imageUrl'] != null && item['imageUrl'] != ''
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(item['imageUrl'], fit: BoxFit.cover),
                                          )
                                        : const Icon(Icons.shopping_bag, color: Color(0xFFB8860B)),
                                    ),
                              title: Text(
                                item['productName'], 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16,
                                  color: isProductValid ? Colors.black : Colors.grey,
                                  decoration: isProductValid ? null : TextDecoration.lineThrough,
                                )
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item['variationName'] != null)
                                    Text('Variation: ${item['variationName']}', style: TextStyle(color: isProductValid ? const Color(0xFFB8860B) : Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  if (isProductValid)
                                    Text('Qty: ${item['quantity']} | ₱${_formatter.format(currentTotal.round())}', style: TextStyle(color: Colors.grey.shade700))
                                  else
                                    const Text('Product no longer available', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              trailing: _isSelectionMode
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _removeFromCart(itemId),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildCheckoutBar(total, cartItems),
                  ],
                );
              }
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Your cart is empty', style: TextStyle(color: Colors.grey, fontSize: 18)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutBar(double total, List<dynamic> cartItems) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Center(
        child: ResponsiveConstraints(
          maxWidth: 800,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Amount', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('₱${_formatter.format(total.round())}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFB8860B))),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: (_isCheckingOut || (_isSelectionMode && _selectedItems.isEmpty)) 
                      ? null 
                      : () => _navigateToReservation(cartItems),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB8860B),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveLayout.isMobile(context) ? 32 : 48, 
                        vertical: 16
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isCheckingOut 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isSelectionMode ? 'Reserve Selected' : 'Reserve All', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeFromCart(String itemId) async {
    await _database.child('carts/${widget.userId}/$itemId').remove();
  }

  void _navigateToReservation(List<dynamic> cartItems) {
    List<Map<String, dynamic>> selectedProducts = [];
    
    for (var entry in cartItems) {
      if (!_isSelectionMode || _selectedItems.contains(entry.key)) {
        var item = entry.value;
        String? productId = item['productId'];
        
        // Filter out deleted products
        if (productId != null && _allProducts.containsKey(productId)) {
          double currentPrice = _calculateCurrentPrice(item);
          selectedProducts.add({
            'cartItemId': entry.key,
            'productId': item['productId'],
            'productName': item['productName'],
            'baseName': item['baseName'],
            'quantity': item['quantity'],
            'price': currentPrice,
            'description': item['description'] ?? '',
            'imageUrl': item['imageUrl'],
            'variationName': item['variationName'],
          });
        }
      }
    }

    if (selectedProducts.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductReservationScreen(
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
          initialProducts: selectedProducts,
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.check_circle, color: Colors.green, size: 60),
        content: const Text('Items reserved successfully! Please visit the clinic to pick them up.', textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}
