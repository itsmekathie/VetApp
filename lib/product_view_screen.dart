import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'product_reservation_screen.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class ProductViewScreen extends StatefulWidget {
  final dynamic product;
  final String productId;
  final String userId;
  final String username;
  final String? fullName;

  const ProductViewScreen({
    super.key,
    required this.product,
    required this.productId,
    required this.userId,
    required this.username,
    this.fullName,
  });

  @override
  State<ProductViewScreen> createState() => _ProductViewScreenState();
}

class _ProductViewScreenState extends State<ProductViewScreen> {
  final _database = FirebaseDatabase.instance.ref();
  Map<String, dynamic>? _selectedVariation;
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
    
    // Default select first variation if available
    if (_variations.isNotEmpty) {
      _selectedVariation = _variations.first;
    }
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
    String? varName = _selectedVariation?['name'];
    for (var promo in _activePromos) {
      List targets = promo['targets'] ?? [];
      for (var target in targets) {
        if (target['id'] == widget.productId) {
          if (target['applyToAll'] == true) return promo;
          List selectedVars = target['selectedVariations'] ?? [];
          if (varName != null && selectedVars.contains(varName)) return promo;
          if (varName == null) return promo; // Show sale if any variation might be on sale
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _variations {
    if (widget.product['variations'] == null) return [];
    if (widget.product['variations'] is List) {
      return List<Map<String, dynamic>>.from(
        (widget.product['variations'] as List).map((e) => Map<String, dynamic>.from(e))
      );
    }
    if (widget.product['variations'] is Map) {
      return (widget.product['variations'] as Map).values.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<void> _addToCart() async {
    if (_variations.isNotEmpty && _selectedVariation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a variation first'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final cartRef = _database.child('carts/${widget.userId}');
    final productName = _selectedVariation != null 
        ? "${widget.product['name']} (${_selectedVariation!['name']})" 
        : widget.product['name'];
    
    // Check if item already exists in cart to increment quantity
    final snapshot = await cartRef.get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      String? existingKey;
      int existingQty = 0;
      
      data.forEach((key, value) {
        // Fix: Check both productId and variationName to distinguish between sizes/types
        bool sameProduct = value['productId'] == widget.productId;
        bool sameVariation = value['variationName'] == _selectedVariation?['name'];

        if (sameProduct && sameVariation) {
          existingKey = key;
          existingQty = value['quantity'] ?? 0;
        }
      });
      
      if (existingKey != null) {
        int newQty = existingQty + 1;
        double originalPrice = (_selectedVariation?['price'] ?? widget.product['price'] ?? 0).toDouble();
        double currentPrice = originalPrice * (1 - (_getDiscount()?['discountPercent'] ?? 0) / 100);
        
        await cartRef.child(existingKey!).update({
          'quantity': newQty,
          'totalPrice': newQty * currentPrice,
        });
      } else {
        await _pushNewToCart(cartRef, productName);
      }
    } else {
      await _pushNewToCart(cartRef, productName);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$productName added to cart'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _pushNewToCart(DatabaseReference cartRef, String productName) async {
    final originalPrice = (_selectedVariation?['price'] ?? widget.product['price'] ?? 0).toDouble();
    final discountPercent = _getDiscount()?['discountPercent'] ?? 0;
    final currentPrice = originalPrice * (1 - discountPercent / 100);
    
    await cartRef.push().set({
      'productName': productName,
      'baseName': widget.product['name'],
      'productId': widget.productId,
      'quantity': 1,
      'unitPrice': currentPrice,
      'totalPrice': currentPrice,
      'imageUrl': widget.product['image'],
      'description': widget.product['description'] ?? '',
      'variationName': _selectedVariation?['name'],
      'timestamp': ServerValue.timestamp,
    });
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
                          const Text("Product Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      child: ResponsiveLayout(
                        mobile: _buildMobileLayout(),
                        tablet: _buildDesktopLayout(), // Tablet uses desktop style
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
          _buildImageGallery(),
          const SizedBox(height: 30),
          _buildProductInfo(),
          const SizedBox(height: 120), // Padding for bottom buttons
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
          Expanded(flex: 1, child: _buildImageGallery(height: 450)),
          const SizedBox(width: 40),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProductInfo(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery({double height = 250}) {
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
          child: widget.product['image'] != null && widget.product['image'] != ''
            ? Image.network(widget.product['image'], fit: BoxFit.contain)
            : const Icon(Icons.shopping_bag_outlined, size: 100, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildProductInfo() {
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
                  Text(widget.product['name'] ?? 'N/A', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(widget.product['category'] ?? 'General', style: TextStyle(fontSize: 16, color: darkGold, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_getDiscount() != null)
                  Text(
                    "₱${_formatter.format(_selectedVariation?['price'] ?? widget.product['price'] ?? 0)}",
                    style: const TextStyle(fontSize: 16, color: Colors.grey, decoration: TextDecoration.lineThrough),
                  ),
                Text(
                  "₱${_formatter.format(((_selectedVariation?['price'] ?? widget.product['price'] ?? 0) * (1 - (_getDiscount()?['discountPercent'] ?? 0) / 100)).round())}", 
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryGold)
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Stock Info
        if (_variations.isEmpty || _selectedVariation != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
            child: Text(
              "${_selectedVariation?['quantity'] ?? widget.product['quantity'] ?? 0} items available", 
              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 13)
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_variations.isNotEmpty) ...[
          const SizedBox(height: 25),
          const Text("Select Variation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: _variations.map((v) {
              bool isSelected = _selectedVariation?['name'] == v['name'];
              return ChoiceChip(
                label: Text(v['name']),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedVariation = selected ? v : null;
                  });
                },
                selectedColor: primaryGold.withOpacity(0.2),
                checkmarkColor: primaryGold,
                labelStyle: TextStyle(
                  color: isSelected ? primaryGold : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: isSelected ? primaryGold : Colors.grey.shade300),
                ),
              );
            }).toList(),
          ),
        ],
        
        const SizedBox(height: 30),
        const Text("Description", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          widget.product['description'] ?? 'No description provided.',
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
        ),
      ],
    );
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
                    onPressed: _addToCart,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: primaryGold, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text("Add to Cart", style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_variations.isNotEmpty && _selectedVariation == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Please select a variation first'),
                          backgroundColor: Colors.orange,
                        ));
                        return;
                      }

                      final productName = _selectedVariation != null 
                          ? "${widget.product['name']} (${_selectedVariation!['name']})" 
                          : widget.product['name'];
                      final price = (_selectedVariation?['price'] ?? widget.product['price'] ?? 0).toDouble();
                      final discount = _getDiscount()?['discountPercent'] ?? 0;
                      final finalPrice = price * (1 - discount / 100);

                      Navigator.push(context, MaterialPageRoute(builder: (c) => ProductReservationScreen(
                        userId: widget.userId,
                        username: widget.username,
                        fullName: widget.fullName,
                        initialProducts: [{
                          'productId': widget.productId,
                          'productName': productName,
                          'baseName': widget.product['name'],
                          'quantity': 1,
                          'price': finalPrice,
                          'description': widget.product['description'] ?? '',
                          'imageUrl': widget.product['image'],
                          'variationName': _selectedVariation?['name'],
                        }],
                      )));
                    },
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(colors: [darkGold, primaryGold]),
                      ),
                      child: const Center(
                        child: Text("Reserve Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
