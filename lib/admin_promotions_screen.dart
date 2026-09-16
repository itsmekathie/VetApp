import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'cloudinary_service.dart';
import 'widgets/gold_blobs_background.dart';

class AdminPromotionsScreen extends StatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  State<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends State<AdminPromotionsScreen> {
  final _database = FirebaseDatabase.instance.ref();
  final ImagePicker _picker = ImagePicker();
  
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotion Management', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryGold,
        elevation: 0,
      ),
      body: GoldBlobsBackground(
        child: StreamBuilder(
          stream: _database.child('promotions').onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
              Map data = snapshot.data!.snapshot.value as Map;
              var promoList = data.entries.toList();
              
              // Sort: Active first, then by date
              promoList.sort((a, b) {
                bool aActive = _isPromoActive(a.value);
                bool bActive = _isPromoActive(b.value);
                if (aActive != bActive) return aActive ? -1 : 1;
                return (b.value['validUntil'] ?? 0).compareTo(a.value['validUntil'] ?? 0);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: promoList.length,
                itemBuilder: (context, index) {
                  var promo = promoList[index].value;
                  var promoId = promoList[index].key;
                  return _buildPromoCard(promoId, promo);
                },
              );
            }

            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No promotions found', style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryGold,
        onPressed: () => _showAddEditPromoDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  bool _isPromoActive(dynamic promo) {
    if (promo['isActive'] == false) return false;
    // For legacy promos with no date, assume they are active if not explicitly deactivated
    if (promo['validUntil'] == null) return true;
    int validUntil = promo['validUntil'] ?? 0;
    return DateTime.now().millisecondsSinceEpoch < validUntil;
  }

  Widget _buildPromoCard(String id, dynamic promo) {
    bool isActive = _isPromoActive(promo);
    String validUntilStr = promo['validUntil'] != null 
      ? DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(promo['validUntil']))
      : 'No expiry set';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isActive ? primaryGold : Colors.grey.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (promo['imageUrl'] != null && promo['imageUrl'] != '')
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Image.network(
                promo['imageUrl'],
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        promo['title'] ?? 'N/A',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isActive ? 'ACTIVE' : 'EXPIRED',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  promo['description'] ?? '',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Valid until: $validUntilStr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.percent, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      promo['discountPercent'] != null 
                        ? 'Discount: ${promo['discountPercent']}% OFF'
                        : 'No specific discount set', 
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryGold)
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showAddEditPromoDialog(id: id, existingData: promo),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(foregroundColor: darkGold),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _deletePromo(id),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
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

  Future<void> _deletePromo(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Promotion?'),
        content: const Text('Are you sure you want to remove this promotion?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await _database.child('promotions/$id').remove();
    }
  }

  void _showAddEditPromoDialog({String? id, dynamic existingData}) {
    final titleController = TextEditingController(text: existingData?['title'] ?? '');
    final descController = TextEditingController(text: existingData?['description'] ?? '');
    final discountController = TextEditingController(text: (existingData?['discountPercent'] ?? 0).toString());
    
    DateTime selectedDate = (existingData != null && existingData['validUntil'] != null)
        ? DateTime.fromMillisecondsSinceEpoch(existingData['validUntil']) 
        : DateTime.now().add(const Duration(days: 7));
    
    String imageUrl = existingData?['imageUrl'] ?? '';
    List<dynamic> targets = existingData?['targets'] ?? [];
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(id == null ? 'New Promotion' : 'Edit Promotion', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // Image Section
                  GestureDetector(
                    onTap: () async {
                      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setDialogState(() => isSaving = true);
                        String? url = await CloudinaryService.uploadImage(File(image.path));
                        setDialogState(() {
                          if (url != null) imageUrl = url;
                          isSaving = false;
                        });
                      }
                    },
                    child: Container(
                      height: 120, width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: primaryGold.withOpacity(0.3)),
                      ),
                      child: imageUrl.isNotEmpty
                        ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(imageUrl, fit: BoxFit.cover))
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey),
                              Text('Upload Promo Banner', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  _buildDialogField('Title', titleController, 'e.g., Summer Sale'),
                  _buildDialogField('Description', descController, 'Details about the promo...', maxLines: 2),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildDialogField('Discount (%)', discountController, '0', keyboardType: TextInputType.number),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Valid Until', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                DateTime? pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (pickedDate != null) {
                                  TimeOfDay? pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(selectedDate),
                                  );
                                  if (pickedTime != null) {
                                    setDialogState(() {
                                      selectedDate = DateTime(
                                        pickedDate.year, pickedDate.month, pickedDate.day,
                                        pickedTime.hour, pickedTime.minute
                                      );
                                    });
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  DateFormat('MM/dd/yy HH:mm').format(selectedDate),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  // Target Selection Button
                  OutlinedButton.icon(
                    onPressed: () => _showTargetSelector(targets, (newTargets) {
                      setDialogState(() => targets = newTargets);
                    }),
                    icon: const Icon(Icons.list_alt),
                    label: Text(targets.isEmpty ? 'Select Products/Services' : '${targets.length} Items Selected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryGold,
                      side: BorderSide(color: primaryGold),
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      if (titleController.text.isEmpty || targets.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please provide a title and select items'))
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      final promoData = {
                        'title': titleController.text.trim(),
                        'description': descController.text.trim(),
                        'discountPercent': int.tryParse(discountController.text) ?? 0,
                        'validUntil': selectedDate.millisecondsSinceEpoch,
                        'imageUrl': imageUrl,
                        'targets': targets,
                        'isActive': true,
                        'timestamp': ServerValue.timestamp,
                      };

                      if (id == null) {
                        await _database.child('promotions').push().set(promoData);
                      } else {
                        await _database.child('promotions/$id').update(promoData);
                      }
                      
                      if (!mounted) return;
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGold,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: isSaving 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(id == null ? 'Create Promotion' : 'Update Promotion', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDialogField(String label, TextEditingController ctrl, String hint, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryGold, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Shopee-Style Target Selector ---
  void _showTargetSelector(List<dynamic> currentTargets, Function(List<dynamic>) onUpdate) {
    List<dynamic> tempTargets = List.from(currentTargets);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSelectorState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            child: Container(
              height: 600,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text('Select Products/Services', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('Select items to apply the discount to.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: StreamBuilder(
                      stream: _database.onValue,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        Map data = snapshot.data!.snapshot.value as Map;
                        Map? products = data['products'] as Map?;
                        Map? services = data['services'] as Map?;

                        List<Widget> sections = [];

                        // Products Section
                        if (products != null) {
                          sections.add(_buildSectionHeader('Products', Icons.inventory_2_outlined));
                          products.forEach((id, val) {
                            sections.add(_buildProductItem(id, val, tempTargets, setSelectorState));
                          });
                        }

                        // Services Section
                        if (services != null) {
                          sections.add(const SizedBox(height: 20));
                          sections.add(_buildSectionHeader('Services', Icons.medical_services_outlined));
                          services.forEach((id, val) {
                            sections.add(_buildServiceItem(id, val, tempTargets, setSelectorState));
                          });
                        }

                        return ListView(children: sections);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            onUpdate(tempTargets);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Apply Selection'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: darkGold),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: darkGold)),
        ],
      ),
    );
  }

  Widget _buildProductItem(String id, dynamic val, List<dynamic> tempTargets, StateSetter setState) {
    List<dynamic> productVariations = [];
    if (val['variations'] != null) {
      if (val['variations'] is List) productVariations = val['variations'];
      else if (val['variations'] is Map) productVariations = val['variations'].values.toList();
    }

    // Check if product is selected (applyToAll)
    bool isAllSelected = tempTargets.any((t) => t['id'] == id && t['applyToAll'] == true);
    
    // Check which specific variations are selected
    var targetEntry = tempTargets.firstWhere((t) => t['id'] == id, orElse: () => null);
    List<dynamic> selectedVars = targetEntry != null ? (targetEntry['selectedVariations'] ?? []) : [];

    return Column(
      children: [
        CheckboxListTile(
          title: Text(val['name'] ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text('₱${val['price'] ?? 0}', style: TextStyle(color: primaryGold, fontSize: 12)),
          value: isAllSelected,
          activeColor: primaryGold,
          onChanged: (selected) {
            setState(() {
              if (selected == true) {
                // Remove any specific variation entries and add "Apply to All"
                tempTargets.removeWhere((t) => t['id'] == id);
                tempTargets.add({'id': id, 'type': 'product', 'applyToAll': true});
              } else {
                tempTargets.removeWhere((t) => t['id'] == id);
              }
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        if (productVariations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: ExpansionTile(
              title: Text('Variations (${productVariations.length})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              children: productVariations.map((v) {
                String varName = v['name'] ?? 'Unknown';
                bool isVarSelected = isAllSelected || selectedVars.contains(varName);

                return CheckboxListTile(
                  title: Text(varName, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('₱${v['price'] ?? 0}', style: const TextStyle(fontSize: 11)),
                  value: isVarSelected,
                  activeColor: primaryGold,
                  onChanged: isAllSelected ? null : (selected) {
                    setState(() {
                      var entry = tempTargets.firstWhere((t) => t['id'] == id, orElse: () => null);
                      if (entry == null) {
                        if (selected == true) {
                          tempTargets.add({
                            'id': id, 
                            'type': 'product', 
                            'applyToAll': false, 
                            'selectedVariations': [varName]
                          });
                        }
                      } else {
                        List<String> currentVars = List<String>.from(entry['selectedVariations'] ?? []);
                        if (selected == true) {
                          currentVars.add(varName);
                        } else {
                          currentVars.remove(varName);
                        }
                        
                        if (currentVars.isEmpty) {
                          tempTargets.removeWhere((t) => t['id'] == id);
                        } else {
                          entry['selectedVariations'] = currentVars;
                        }
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildServiceItem(String id, dynamic val, List<dynamic> tempTargets, StateSetter setState) {
    bool isSelected = tempTargets.any((t) => t['id'] == id);

    return CheckboxListTile(
      title: Text(val['name'] ?? 'Service', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('₱${val['price'] ?? 0}', style: TextStyle(color: primaryGold, fontSize: 12)),
      value: isSelected,
      activeColor: primaryGold,
      onChanged: (selected) {
        setState(() {
          if (selected == true) {
            tempTargets.add({'id': id, 'type': 'service'});
          } else {
            tempTargets.removeWhere((t) => t['id'] == id);
          }
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
    );
  }
}
