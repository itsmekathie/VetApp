import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'cloudinary_service.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'widgets/gold_blobs_background.dart';

class AdminProductsScreen extends StatefulWidget {
  final bool filterLowStock;
  const AdminProductsScreen({super.key, this.filterLowStock = false});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> with SingleTickerProviderStateMixin {
  final _database = FirebaseDatabase.instance.ref();
  final ImagePicker _picker = ImagePicker();
  final _searchController = TextEditingController();
  String _searchQuery = "";
  String? _selectedCategory;
  bool _isAddMenuOpen = false;
  bool _showOnlyLowStock = false;

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  final Color primaryGold = const Color(0xFFB8860B);
  final _formatter = NumberFormat('#,###');
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
    _showOnlyLowStock = widget.filterLowStock;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAddMenu() {
    setState(() {
      _isAddMenuOpen = !_isAddMenuOpen;
      if (_isAddMenuOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  Future<String?> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading image...')));
    String? imageUrl = await CloudinaryService.uploadImage(File(image.path));
    if (imageUrl != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload successful!')));
    }
    return imageUrl;
  }

  void _showAddEditProductDialog({String? key, dynamic existingData}) {
    final nameController = TextEditingController(text: existingData?['name'] ?? '');
    final qtyController = TextEditingController(text: (existingData?['quantity'] ?? 0).toString());
    final priceController = TextEditingController(text: (existingData?['price'] ?? 0).toString());
    final catController = TextEditingController(text: existingData?['category'] ?? _selectedCategory ?? 'General');
    final descController = TextEditingController(text: existingData?['description'] ?? '');
    String imageUrl = existingData?['image'] ?? '';
    bool hasChanged = false;

    List<Map<String, dynamic>> variations = [];
    List<TextEditingController> varNameCtrls = [];
    List<TextEditingController> varPriceCtrls = [];
    List<TextEditingController> varQtyCtrls = [];

    if (existingData?['variations'] != null) {
      if (existingData['variations'] is List) {
        variations = List<Map<String, dynamic>>.from(
          (existingData['variations'] as List).map((e) => Map<String, dynamic>.from(e))
        );
      } else if (existingData['variations'] is Map) {
        variations = (existingData['variations'] as Map).values.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      
      for (var v in variations) {
        varNameCtrls.add(TextEditingController(text: v['name'] ?? ''));
        varPriceCtrls.add(TextEditingController(text: (v['price'] ?? 0).toString()));
        varQtyCtrls.add(TextEditingController(text: (v['quantity'] ?? 0).toString()));
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isValid = nameController.text.isNotEmpty && 
                         (variations.isNotEmpty || (priceController.text.isNotEmpty && qtyController.text.isNotEmpty));
          
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: primaryGold, width: 3),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(key == null ? 'Inventory' : 'Edit Product', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () async {
                        String? url = await _pickAndUploadImage();
                        if (url != null) {
                          setDialogState(() {
                            imageUrl = url;
                            hasChanged = true;
                          });
                        }
                      },
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: imageUrl.isNotEmpty 
                          ? Image.network(imageUrl, fit: BoxFit.cover)
                          : const Center(child: Text("image", style: TextStyle(color: Colors.grey))),
                      ),
                    ),
                    const Text("Tap to upload/replace the image", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 20),
                    _buildInputField("Name :", nameController, "Name of the product", onChanged: (v) => setDialogState(() => hasChanged = true)),
                    _buildCategoryDropdown(catController, (v) {
                      setDialogState(() {
                        catController.text = v!;
                        hasChanged = true;
                      });
                    }),
                    _buildDescriptionField(descController, (v) => setDialogState(() => hasChanged = true)),
                    
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Variations :", style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: Icon(Icons.add_circle, color: primaryGold),
                          onPressed: () {
                            setDialogState(() {
                              variations.add({'name': '', 'price': 0.0, 'quantity': 0});
                              varNameCtrls.add(TextEditingController());
                              varPriceCtrls.add(TextEditingController());
                              varQtyCtrls.add(TextEditingController());
                              hasChanged = true;
                            });
                          },
                        ),
                      ],
                    ),
                    if (variations.isEmpty) ...[
                      _buildInputField("Stock :", qtyController, "(Stock)", keyboardType: TextInputType.number, onChanged: (v) => setDialogState(() => hasChanged = true)),
                      _buildInputField("Price :", priceController, "(Price)", isPrice: true, keyboardType: TextInputType.number, onChanged: (v) => setDialogState(() => hasChanged = true)),
                    ] else ...[
                      ...variations.asMap().entries.map((entry) {
                        int index = entry.key;
                        return _buildVariationItem(
                          index, 
                          varNameCtrls[index],
                          varPriceCtrls[index],
                          varQtyCtrls[index],
                          () => setDialogState(() {
                            variations.removeAt(index);
                            varNameCtrls[index].dispose();
                            varPriceCtrls[index].dispose();
                            varQtyCtrls[index].dispose();
                            varNameCtrls.removeAt(index);
                            varPriceCtrls.removeAt(index);
                            varQtyCtrls.removeAt(index);
                            hasChanged = true;
                          }),
                          (v) => setDialogState(() => hasChanged = true),
                        );
                      }),
                    ],
                    
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: (isValid && (key == null || hasChanged)) ? () async {
                        List<Map<String, dynamic>> finalVariations = [];
                        for (int i = 0; i < variations.length; i++) {
                          finalVariations.add({
                            'name': varNameCtrls[i].text.trim(),
                            'price': double.tryParse(varPriceCtrls[i].text) ?? 0.0,
                            'quantity': int.tryParse(varQtyCtrls[i].text) ?? 0,
                          });
                        }

                        final data = {
                          'name': nameController.text.trim(),
                          'quantity': finalVariations.isEmpty 
                              ? (int.tryParse(qtyController.text) ?? 0) 
                              : finalVariations.fold<int>(0, (sum, v) => sum + (v['quantity'] as int)),
                          'price': finalVariations.isEmpty 
                              ? (double.tryParse(priceController.text) ?? 0.0) 
                              : finalVariations.map((v) => (v['price'] as num).toDouble()).reduce((a, b) => a < b ? a : b),
                          'category': catController.text.trim(),
                          'description': descController.text.trim(),
                          'image': imageUrl,
                          'variations': finalVariations.isNotEmpty ? finalVariations : null,
                        };
                        if (key == null) {
                          await _database.child('products').push().set(data);
                        } else {
                          await _database.child('products').child(key).update(data);
                        }

                        // --- UPDATE LOW STOCK STAT ---
                        _updateLowStockStat();
                        
                        if (!mounted) return;
                        Navigator.pop(context);
                      } : null,
                      child: Container(
                        width: double.infinity, height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: (isValid && (key == null || hasChanged)) 
                            ? LinearGradient(colors: [darkGold, primaryGold])
                            : null,
                          color: (isValid && (key == null || hasChanged)) ? null : Colors.grey,
                        ),
                        child: const Center(child: Text("Save", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController ctrl, String hint, {bool isPrice = false, TextInputType keyboardType = TextInputType.text, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.replaceAll(" :", ""), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(10),
            ),
            child: StatefulBuilder(
              builder: (context, setState) => TextField(
                controller: ctrl,
                onChanged: (v) {
                  setState(() {});
                  if (onChanged != null) onChanged(v);
                },
                keyboardType: keyboardType,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: InputBorder.none,
                  prefixText: isPrice && ctrl.text.isNotEmpty ? "₱ " : null,
                  suffixIcon: const Icon(Icons.edit_note, size: 20, color: Colors.grey),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(TextEditingController ctrl, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Category", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Container(
            height: 44,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(10),
            ),
            child: StreamBuilder(
              stream: _database.child('categories').onValue,
              builder: (context, snapshot) {
                List<String> items = ['General'];
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  Map data = snapshot.data!.snapshot.value as Map;
                  data.forEach((k, v) {
                    if (v['type'] == 'Products') items.add(v['name']);
                  });
                }
                return DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: items.contains(ctrl.text) ? ctrl.text : items.first,
                    items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: onChanged,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionField(TextEditingController ctrl, Function(String)? onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Description :", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: 3,
            onChanged: onChanged,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(10),
              border: InputBorder.none,
              suffixIcon: IconButton(icon: const Icon(Icons.cancel, size: 18), onPressed: () => ctrl.clear()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVariationItem(int index, TextEditingController nameCtrl, TextEditingController priceCtrl, TextEditingController qtyCtrl, VoidCallback onRemove, Function(String) onChanged) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  onChanged: onChanged,
                  decoration: const InputDecoration(hintText: "Variation Name (e.g. 500ml)", isDense: true),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: onRemove),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setState) => TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      setState(() {});
                      onChanged(v);
                    },
                    decoration: InputDecoration(
                      hintText: "(Price)", 
                      prefixText: priceCtrl.text.isNotEmpty ? "₱ " : null,
                      isDense: true
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: onChanged,
                  decoration: const InputDecoration(hintText: "(Stock)", isDense: true),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    String imageUrl = '';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: primaryGold, width: 3),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add Category', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: isSaving ? null : () async {
                    String? url = await _pickAndUploadImage();
                    if (url != null) setDialogState(() { imageUrl = url; });
                  },
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(border: Border.all(color: Colors.black), borderRadius: BorderRadius.circular(10)),
                    child: imageUrl.isNotEmpty ? Image.network(imageUrl, fit: BoxFit.cover) : const Center(child: Text("image")),
                  ),
                ),
                const SizedBox(height: 20),
                _buildInputField("Name :", nameController, "Category Name", onChanged: (v) => setDialogState(() {})),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: (nameController.text.isNotEmpty && !isSaving) ? () async {
                    setDialogState(() => isSaving = true);
                    try {
                      await _database.child('categories').child(nameController.text.trim()).set({
                        'name': nameController.text.trim(),
                        'image': imageUrl,
                        'type': 'Products',
                      });
                      
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Category added successfully!")));
                      Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      setDialogState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                    }
                  } : null,
                  child: Container(
                    width: double.infinity, height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: nameController.text.isNotEmpty ? LinearGradient(colors: [darkGold, primaryGold]) : null,
                      color: nameController.text.isNotEmpty ? null : Colors.grey,
                    ),
                    child: Center(
                      child: isSaving 
                        ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Text("Add", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  if (_showOnlyLowStock)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  "Low Stock Items",
                                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => setState(() => _showOnlyLowStock = false),
                                  child: Icon(Icons.close, size: 16, color: Colors.red.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildCategoryBar(),
                  Expanded(child: _buildProductList()),
                ],
              ),
            ),

            // FAB and Overlay Menu (Centered)
            if (_isAddMenuOpen)
              GestureDetector(
                onTap: _toggleAddMenu,
                child: Container(color: Colors.black45), // Darker overlay
              ),
            
            if (_isAddMenuOpen)
              Center(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLargeMenuButton("Product", () { _toggleAddMenu(); _showAddEditProductDialog(); }, const Color(0xFF4A4EFE)),
                      const SizedBox(height: 15),
                      _buildLargeMenuButton("Product Category", () { _toggleAddMenu(); _showAddCategoryDialog(); }, primaryGold),
                    ],
                  ),
                ),
              ),

            Positioned(
              bottom: 30, right: 30,
              child: FloatingActionButton(
                onPressed: _toggleAddMenu,
                backgroundColor: _isAddMenuOpen ? Colors.red : primaryGold,
                elevation: 0,
                child: Icon(_isAddMenuOpen ? Icons.close : Icons.add, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              const Expanded(child: Center(child: Text("Inventory", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)))),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    decoration: const InputDecoration(hintText: "Search...", border: InputBorder.none),
                  ),
                ),
                const Icon(Icons.tune, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return SizedBox(
      height: 100,
      child: StreamBuilder(
        stream: _database.child('categories').onValue,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            Map data = snapshot.data!.snapshot.value as Map;
            var cats = data.entries.where((e) => e.value['type'] == 'Products').toList();
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              children: [
                _categoryIcon("All", null, isSelected: _selectedCategory == null),
                ...cats.map((e) => _categoryIcon(e.value['name'], e.value['image'], isSelected: _selectedCategory == e.value['name'])),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _categoryIcon(String label, String? imageUrl, {bool isSelected = false}) {
    return GestureDetector(
      onTap: () {
        if (_selectedCategory == label && label != "All" && label != "General") {
          _showEditCategoryDialog(label);
        } else {
          setState(() => _selectedCategory = label == "All" ? null : label);
        }
      },
      child: Container(
        width: 70,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: isSelected ? primaryGold.withOpacity(0.1) : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? primaryGold : Colors.transparent, width: 2),
                image: imageUrl != null && imageUrl.isNotEmpty ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover) : null,
              ),
              child: isSelected && label != "All" && label != "General"
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.edit, color: Colors.white, size: 20),
                      ),
                    )
                  : (imageUrl == null || imageUrl.isEmpty) ? const Icon(Icons.category, color: Colors.grey) : null,
            ),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  void _showEditCategoryDialog(String catName) async {
    final snap = await _database.child('categories').child(catName).get();
    if (!snap.exists) return;
    
    Map catData = snap.value as Map;
    final nameController = TextEditingController(text: catData['name'] ?? catName);
    String imageUrl = catData['image'] ?? '';
    bool hasChanged = false;
    bool isSaving = false;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: primaryGold, width: 3),
                color: Colors.white,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Edit Category', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: isSaving ? null : () async {
                      String? url = await _pickAndUploadImage();
                      if (url != null) setDialogState(() { imageUrl = url; hasChanged = true; });
                    },
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(border: Border.all(color: Colors.black), borderRadius: BorderRadius.circular(10)),
                      child: imageUrl.isNotEmpty ? Image.network(imageUrl, fit: BoxFit.cover) : const Center(child: Text("image")),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildInputField("Name :", nameController, "Category Name", onChanged: (v) => setDialogState(() => hasChanged = true)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving ? null : () => _confirmDeleteCategory(catName),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: (nameController.text.isNotEmpty && !isSaving && (hasChanged || nameController.text.trim() != catName)) ? () async {
                            setDialogState(() => isSaving = true);
                            try {
                              String newName = nameController.text.trim();
                              
                              // If name changed, rename keys in DB
                              if (newName != catName) {
                                await _database.child('categories').child(newName).set({
                                  'name': newName,
                                  'image': imageUrl,
                                  'type': 'Products',
                                });
                                await _database.child('categories').child(catName).remove();
                                
                                // Update existing products with this category
                                final prodSnap = await _database.child('products').orderByChild('category').equalTo(catName).get();
                                if (prodSnap.exists) {
                                  Map prods = prodSnap.value as Map;
                                  for (var key in prods.keys) {
                                    await _database.child('products/$key').update({'category': newName});
                                  }
                                }
                              } else {
                                await _database.child('categories').child(catName).update({
                                  'image': imageUrl,
                                });
                              }
                              
                              setState(() {
                                _selectedCategory = newName;
                              });
                              
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Category updated successfully!")));
                              Navigator.pop(context);
                            } catch (e) {
                              if (!context.mounted) return;
                              setDialogState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                            }
                          } : null,
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: (nameController.text.isNotEmpty && !isSaving && (hasChanged || nameController.text.trim() != catName))
                                ? LinearGradient(colors: [darkGold, primaryGold])
                                : null,
                              color: (nameController.text.isNotEmpty && !isSaving && (hasChanged || nameController.text.trim() != catName))
                                ? null
                                : Colors.grey,
                            ),
                            child: Center(
                              child: isSaving 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
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

  void _confirmDeleteCategory(String catName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: const Text('Delete all products linked to this category as well?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // close confirm dialog
              Navigator.pop(context); // close edit dialog
              
              // Move existing products to General
              final prodSnap = await _database.child('products').orderByChild('category').equalTo(catName).get();
              if (prodSnap.exists) {
                Map prods = prodSnap.value as Map;
                for (var key in prods.keys) {
                  await _database.child('products/$key').update({'category': 'General'});
                }
              }
              
              await _database.child('categories').child(catName).remove();
              setState(() {
                _selectedCategory = null;
              });
            },
            child: const Text('No, Move to General'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // close confirm dialog
              Navigator.pop(context); // close edit dialog
              
              // Delete all products in this category
              final prodSnap = await _database.child('products').orderByChild('category').equalTo(catName).get();
              if (prodSnap.exists) {
                Map prods = prodSnap.value as Map;
                for (var key in prods.keys) {
                  await _database.child('products/$key').remove();
                }
              }
              
              await _database.child('categories').child(catName).remove();
              setState(() {
                _selectedCategory = null;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, Delete All'),
          ),
        ],
      ),
    );
  }

  bool _isItemLowStock(dynamic item) {
    if (item['variations'] != null) {
      var vars = item['variations'];
      List<dynamic> varList = [];
      if (vars is List) varList = vars;
      else if (vars is Map) varList = vars.values.toList();
      
      // Alert if ANY variation is below 5 OR if the total stock is 0
      bool hasLowVariation = varList.any((v) => (v['quantity'] ?? 0) < 5);
      return hasLowVariation;
    }
    return (item['quantity'] ?? 0) < 5;
  }

  Widget _buildProductList() {
    return StreamBuilder(
      stream: _database.child('products').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          Map data = snapshot.data!.snapshot.value as Map;
          var items = data.entries.where((e) {
            bool matchesSearch = e.value['name'].toString().toLowerCase().contains(_searchQuery);
            bool matchesCat = _selectedCategory == null || e.value['category'] == _selectedCategory;
            bool matchesLowStock = !_showOnlyLowStock || _isItemLowStock(e.value);
            return matchesSearch && matchesCat && matchesLowStock;
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              var item = items[index].value;
              var key = items[index].key;
              return _buildProductCard(item, key!);
            },
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildProductCard(dynamic item, String key) {
    bool isLow = _isItemLowStock(item);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: Slidable(
        key: ValueKey(key),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.5,
          children: [
            SlidableAction(
              onPressed: (c) => _showQuickStockDialog(key, item),
              backgroundColor: Colors.green.shade100,
              foregroundColor: Colors.green,
              icon: Icons.inventory_2,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
            ),
            SlidableAction(
              onPressed: (c) => _showAddEditProductDialog(key: key, existingData: item),
              backgroundColor: Colors.blue.shade100,
              foregroundColor: Colors.blue,
              icon: Icons.edit_square,
            ),
            SlidableAction(
              onPressed: (c) => _confirmDelete(key),
              backgroundColor: Colors.red.shade100,
              foregroundColor: Colors.red,
              icon: Icons.delete,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(15)),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isLow && _showOnlyLowStock 
              ? Border.all(color: Colors.red.withOpacity(0.5), width: 2) 
              : Border.all(color: Colors.transparent, width: 2),
            boxShadow: [
              BoxShadow(
                color: isLow && _showOnlyLowStock 
                  ? Colors.red.withOpacity(0.1) 
                  : Colors.black.withOpacity(0.05), 
                blurRadius: 10, 
                offset: const Offset(0, 4)
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: item['image'] != null && item['image'] != ''
                    ? DecorationImage(image: NetworkImage(item['image']), fit: BoxFit.cover)
                    : null,
                ),
                child: (item['image'] == null || item['image'] == '') ? const Icon(Icons.inventory, color: Colors.grey) : null,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(item['category'] ?? 'General', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Builder(builder: (context) {
                      if (item['variations'] != null) {
                        int totalStock = 0;
                        List<Widget> varDetails = [];
                        var vars = item['variations'];
                        
                        List<dynamic> varList = [];
                        if (vars is List) {
                          varList = vars;
                        } else if (vars is Map) {
                          varList = vars.values.toList();
                        }

                        for (var v in varList) {
                          int q = (v['quantity'] ?? 0) as int;
                          totalStock += q;
                          
                          // Warning indicators
                          Color textColor = Colors.grey.shade600;
                          String suffix = "";
                          if (q == 0) {
                            textColor = Colors.red.shade700;
                            suffix = " (Out of stock!)";
                          } else if (q < 5) {
                            textColor = Colors.orange.shade800;
                            suffix = " (Low stock)";
                          }

                          varDetails.add(
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                "• ${v['name']}: $q$suffix",
                                style: TextStyle(
                                  fontSize: 10, 
                                  color: textColor,
                                  fontWeight: q < 5 ? FontWeight.bold : FontWeight.normal
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("$totalStock in Stock (${varList.length} variations)", 
                              style: TextStyle(
                                color: totalStock < 5 ? Colors.red : Colors.grey.shade800, 
                                fontSize: 11, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                            ...varDetails,
                          ],
                        );
                      }
                      int q = (item['quantity'] ?? 0) as int;
                      return Text("$q in Stock", 
                        style: TextStyle(
                          color: q < 5 ? Colors.red : Colors.grey, 
                          fontSize: 12, 
                          fontWeight: FontWeight.bold
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Builder(builder: (context) {
                if (item['variations'] != null) {
                  List<dynamic> varList = [];
                  if (item['variations'] is List) {
                    varList = item['variations'];
                  } else if (item['variations'] is Map) {
                    varList = item['variations'].values.toList();
                  }

                  if (varList.isNotEmpty) {
                    List<double> prices = varList.map<double>((v) => (v['price'] ?? 0).toDouble()).toList();
                    prices.sort();
                    double minP = prices.first;
                    double maxP = prices.last;
                    String priceRange = minP == maxP ? "₱${_formatter.format(minP.round())}" : "₱${_formatter.format(minP.round())} - ${_formatter.format(maxP.round())}";

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(priceRange, style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: varList.length > 1 && minP != maxP ? 12 : 15)),
                            Text("Various", style: TextStyle(color: primaryGold.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400, size: 20),
                      ],
                    );
                  }
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("₱${_formatter.format((item['price'] ?? 0).round())}", style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400, size: 20),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeMenuButton(String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        height: 55,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.8), color],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _confirmDelete(String key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async { 
              await _database.child('products').child(key).remove(); 
              _updateLowStockStat();
              if (mounted) Navigator.pop(context); 
            }, 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red), 
            child: const Text('Delete')
          ),
        ],
      ),
    );
  }

  void _showQuickStockDialog(String key, dynamic item) {
    bool isVariation = item['variations'] != null;
    
    // Lists or maps to keep track of controllers & initial stocks
    List<Map<String, dynamic>> targetItems = [];
    
    if (isVariation) {
      var vars = item['variations'];
      List<dynamic> varList = [];
      if (vars is List) {
        varList = vars;
      } else if (vars is Map) {
        varList = vars.values.toList();
      }
      
      for (int i = 0; i < varList.length; i++) {
        var v = varList[i];
        int currentQty = (v['quantity'] ?? 0) as int;
        targetItems.add({
          'index': i,
          'name': v['name'] ?? 'Variation',
          'current': currentQty,
          'controller': TextEditingController(text: currentQty.toString()),
        });
      }
    } else {
      int currentQty = (item['quantity'] ?? 0) as int;
      targetItems.add({
        'index': 0,
        'name': item['name'] ?? 'Product',
        'current': currentQty,
        'controller': TextEditingController(text: currentQty.toString()),
      });
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Quick Stock: ${item['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: targetItems.map((target) {
                final ctrl = target['controller'] as TextEditingController;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      if (isVariation)
                        Expanded(
                          flex: 2,
                          child: Text(
                            target['name'],
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () {
                              int val = int.tryParse(ctrl.text) ?? 0;
                              if (val > 0) {
                                ctrl.text = (val - 1).toString();
                              }
                            },
                          ),
                          Container(
                            width: 60,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: ctrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                            onPressed: () {
                              int val = int.tryParse(ctrl.text) ?? 0;
                              ctrl.text = (val + 1).toString();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              for (var t in targetItems) {
                (t['controller'] as TextEditingController).dispose();
              }
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (isVariation) {
                var vars = item['variations'];
                if (vars is List) {
                  List<dynamic> updatedVars = List.from(vars);
                  for (var target in targetItems) {
                    int idx = target['index'] as int;
                    int newQty = int.tryParse((target['controller'] as TextEditingController).text) ?? 0;
                    updatedVars[idx]['quantity'] = newQty;
                  }
                  await _database.child('products').child(key).child('variations').set(updatedVars);
                } else if (vars is Map) {
                  Map<dynamic, dynamic> updatedVars = Map.from(vars);
                  var keysList = updatedVars.keys.toList();
                  for (var target in targetItems) {
                    int idx = target['index'] as int;
                    int newQty = int.tryParse((target['controller'] as TextEditingController).text) ?? 0;
                    var varKey = keysList[idx];
                    updatedVars[varKey]['quantity'] = newQty;
                  }
                  await _database.child('products').child(key).child('variations').set(updatedVars);
                }
              } else {
                int newQty = int.tryParse((targetItems[0]['controller'] as TextEditingController).text) ?? 0;
                await _database.child('products').child(key).update({'quantity': newQty});
              }

              for (var t in targetItems) {
                (t['controller'] as TextEditingController).dispose();
              }
              _updateLowStockStat();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryGold),
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLowStockStat() async {
    try {
      final snap = await _database.child('products').get();
      int count = 0;
      if (snap.exists) {
        Map data = snap.value as Map;
        for (var p in data.values) {
          if (_isItemLowStock(p)) count++;
        }
      }
      await _database.child('stats/inventory/low_stock_count').set(count);
    } catch (e) {
      debugPrint("Error updating low stock stat: $e");
    }
  }
}
