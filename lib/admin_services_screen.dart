import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'cloudinary_service.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'widgets/gold_blobs_background.dart';

class AdminServicesScreen extends StatefulWidget {
  const AdminServicesScreen({super.key});

  @override
  State<AdminServicesScreen> createState() => _AdminServicesScreenState();
}

class _AdminServicesScreenState extends State<AdminServicesScreen> with SingleTickerProviderStateMixin {
  final _database = FirebaseDatabase.instance.ref();
  final ImagePicker _picker = ImagePicker();
  final _searchController = TextEditingController();
  String _searchQuery = "";
  String? _selectedCategory;
  bool _isAddMenuOpen = false;

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
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

  void _showAddEditServiceDialog({String? key, dynamic existingData}) {
    final nameController = TextEditingController(text: existingData?['name'] ?? '');
    final timeController = TextEditingController(text: existingData?['estimatedTime'] ?? '');
    final priceController = TextEditingController(text: (existingData?['price'] ?? 0).toString());
    final catController = TextEditingController(text: existingData?['category'] ?? _selectedCategory ?? 'General');
    final descController = TextEditingController(text: existingData?['description'] ?? '');
    final incController = TextEditingController(text: existingData?['inclusions'] ?? '');
    String imageUrl = existingData?['image'] ?? '';
    bool hasChanged = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isValid = nameController.text.isNotEmpty && priceController.text.isNotEmpty;
          
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
                    Text(key == null ? 'Services' : 'Edit Service', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                    _buildInputField("Name :", nameController, "Name of the service", onChanged: (v) => setDialogState(() => hasChanged = true)),
                    _buildInputField("Estimated Time :", timeController, "ex. (30 mins)", onChanged: (v) => setDialogState(() => hasChanged = true)),
                    _buildCategoryDropdown(catController, (v) {
                      setDialogState(() {
                        catController.text = v!;
                        hasChanged = true;
                      });
                    }),
                    _buildTextArea("Description :", descController, (v) => setDialogState(() => hasChanged = true)),
                    _buildTextArea("Inclusions :", incController, (v) => setDialogState(() => hasChanged = true)),
                    _buildInputField("Price :", priceController, "0.0", isPrice: true, onChanged: (v) => setDialogState(() => hasChanged = true)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: (isValid && (key == null || hasChanged)) ? () async {
                        final data = {
                          'name': nameController.text.trim(),
                          'estimatedTime': timeController.text.trim(),
                          'price': double.tryParse(priceController.text) ?? 0.0,
                          'category': catController.text.trim(),
                          'description': descController.text.trim(),
                          'inclusions': incController.text.trim(),
                          'image': imageUrl,
                        };
                        if (key == null) {
                          await _database.child('services').push().set(data);
                        } else {
                          await _database.child('services').child(key).update(data);
                        }
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
                        child: Center(child: Text(key == null ? "Add" : "Save", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
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

  Widget _buildInputField(String label, TextEditingController ctrl, String hint, {bool isPrice = false, Function(String)? onChanged}) {
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
            child: TextField(
              controller: ctrl,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none,
                prefixText: isPrice ? "₱ " : null,
                suffixIcon: const Icon(Icons.edit_note, size: 20, color: Colors.grey),
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
                    if (v['type'] == 'Services') items.add(v['name']);
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

  Widget _buildTextArea(String label, TextEditingController ctrl, Function(String)? onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: 2,
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

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    String imageUrl = '';

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
                  onTap: () async {
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
                _buildInputField("Name :", nameController, "Category Name"),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: (nameController.text.isNotEmpty) ? () async {
                    await _database.child('categories').child(nameController.text.trim()).set({
                      'name': nameController.text.trim(),
                      'image': imageUrl,
                      'type': 'Services',
                    });
                    if (!mounted) return;
                    Navigator.pop(context);
                  } : null,
                  child: Container(
                    width: double.infinity, height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: nameController.text.isNotEmpty ? LinearGradient(colors: [darkGold, primaryGold]) : null,
                      color: nameController.text.isNotEmpty ? null : Colors.grey,
                    ),
                    child: const Center(child: Text("Add", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
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
                  _buildCategoryBar(),
                  Expanded(child: _buildServiceList()),
                ],
              ),
            ),

            if (_isAddMenuOpen)
              GestureDetector(
                onTap: _toggleAddMenu,
                child: Container(color: Colors.black45),
              ),
            
            if (_isAddMenuOpen)
              Center(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLargeMenuButton("Service", () { _toggleAddMenu(); _showAddEditServiceDialog(); }, const Color(0xFF4A4EFE)),
                      const SizedBox(height: 15),
                      _buildLargeMenuButton("Service Category", () { _toggleAddMenu(); _showAddCategoryDialog(); }, primaryGold),
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
              const Expanded(child: Center(child: Text("Services", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)))),
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
            var cats = data.entries.where((e) => e.value['type'] == 'Services').toList();
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
                    onTap: () async {
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
                          onPressed: () => _confirmDeleteCategory(catName),
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
                          onTap: (nameController.text.isNotEmpty && (hasChanged || nameController.text.trim() != catName)) ? () async {
                            String newName = nameController.text.trim();
                            if (newName != catName) {
                              await _database.child('categories').child(newName).set({
                                'name': newName,
                                'image': imageUrl,
                                'type': 'Services',
                              });
                              await _database.child('categories').child(catName).remove();
                              final serviceSnap = await _database.child('services').orderByChild('category').equalTo(catName).get();
                              if (serviceSnap.exists) {
                                Map services = serviceSnap.value as Map;
                                for (var key in services.keys) {
                                  await _database.child('services/$key').update({'category': newName});
                                }
                              }
                            } else {
                              await _database.child('categories').child(catName).update({
                                'image': imageUrl,
                              });
                            }
                            setState(() { _selectedCategory = newName; });
                            if (!mounted) return;
                            Navigator.pop(context);
                          } : null,
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: (nameController.text.isNotEmpty && (hasChanged || nameController.text.trim() != catName))
                                ? LinearGradient(colors: [darkGold, primaryGold])
                                : null,
                              color: (nameController.text.isNotEmpty && (hasChanged || nameController.text.trim() != catName))
                                ? null
                                : Colors.grey,
                            ),
                            child: const Center(child: Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
        content: const Text('Delete all services linked to this category as well?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context); 
              Navigator.pop(context); 
              final serviceSnap = await _database.child('services').orderByChild('category').equalTo(catName).get();
              if (serviceSnap.exists) {
                Map services = serviceSnap.value as Map;
                for (var key in services.keys) {
                  await _database.child('services/$key').update({'category': 'General'});
                }
              }
              await _database.child('categories').child(catName).remove();
              setState(() { _selectedCategory = null; });
            },
            child: const Text('No, Move to General'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); 
              Navigator.pop(context); 
              final serviceSnap = await _database.child('services').orderByChild('category').equalTo(catName).get();
              if (serviceSnap.exists) {
                Map services = serviceSnap.value as Map;
                for (var key in services.keys) {
                  await _database.child('services/$key').remove();
                }
              }
              await _database.child('categories').child(catName).remove();
              setState(() { _selectedCategory = null; });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, Delete All'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceList() {
    return StreamBuilder(
      stream: _database.child('services').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          Map data = snapshot.data!.snapshot.value as Map;
          var items = data.entries.where((e) {
            bool matchesSearch = e.value['name'].toString().toLowerCase().contains(_searchQuery);
            bool matchesCat = _selectedCategory == null || e.value['category'] == _selectedCategory;
            return matchesSearch && matchesCat;
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              var item = items[index].value;
              var key = items[index].key;
              return _buildServiceCard(item, key!);
            },
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildServiceCard(dynamic item, String key) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: Slidable(
        key: ValueKey(key),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.35,
          children: [
            SlidableAction(
              onPressed: (c) => _showAddEditServiceDialog(key: key, existingData: item),
              backgroundColor: Colors.blue.shade100,
              foregroundColor: Colors.blue,
              icon: Icons.edit_square,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
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
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
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
                child: (item['image'] == null || item['image'] == '') ? const Icon(Icons.medical_services, color: Colors.grey) : null,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(item['category'] ?? 'General', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(item['estimatedTime'] ?? 'N/A', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Text("₱${item['price']}", style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left_rounded, color: Colors.grey.shade400, size: 20),
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
        title: const Text('Delete Service'),
        content: const Text('Are you sure you want to delete this service?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { _database.child('services').child(key).remove(); Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
  }
}
