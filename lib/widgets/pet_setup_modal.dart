import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';

class PetSetupModal extends StatefulWidget {
  final String userId;
  final VoidCallback onPetAdded;

  const PetSetupModal({
    super.key,
    required this.userId,
    required this.onPetAdded,
  });

  @override
  State<PetSetupModal> createState() => _PetSetupModalState();
}

class _PetSetupModalState extends State<PetSetupModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();
  final _weightController = TextEditingController();
  final GlobalKey _breedFieldKey = GlobalKey();
  
  String? _selectedType;
  String? _selectedSex;
  String? _selectedAge;
  String? _selectedBirthday;
  String _selectedWeightUnit = 'kg';

  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  final Map<String, List<String>> _breeds = {
    'Dog': [
      'Aspin', 'Shih Tzu', 'Pomeranian', 'Poodle', 'Golden Retriever', 
      'German Shepherd', 'Labrador Retriever', 'Chihuahua', 'Pug', 
      'Siberian Husky', 'Beagle', 'Bulldog', 'Rottweiler', 'Dachshund', 
      'Boxer', 'Corgi', 'Chow Chow', 'Dalmatian'
    ],
    'Cat': [
      'Puspin', 'Persian', 'Siamese', 'Maine Coon', 'Bengal', 'Ragdoll', 
      'British Shorthair', 'Sphynx', 'Abyssinian', 'Scottish Fold', 
      'Munchkin', 'Russian Blue'
    ],
  };

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _addPet() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final database = FirebaseDatabase.instance.ref();
      final snap = await database.child('users/${widget.userId}/pets').get();
      List<dynamic> pets = [];
      if (snap.exists) {
        pets = List.from(snap.value as List);
      }

      final newPet = {
        'name': _nameController.text.trim(),
        'type': _selectedType,
        'breed': _breedController.text.trim(),
        'weight': "${_weightController.text.trim()} $_selectedWeightUnit",
        'sex': _selectedSex,
        'age': _selectedAge,
        'birthday': _selectedBirthday,
      };

      pets.add(newPet);
      await database.child('users/${widget.userId}/pets').set(pets);
      
      widget.onPetAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error adding pet: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              const Text("Add your pet now!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              _buildTextField(_nameController, "Pet Name"),
              const SizedBox(height: 12),
              
              _buildWeightField(),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: _buildTypeSelector(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHybridBreedField(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: _buildSexSelector(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPickerField("Age", _selectedAge, () => _showAgePicker()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              _buildPickerField("Birthday", _selectedBirthday, () => _showBirthdayPicker()),
              const SizedBox(height: 30),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primaryGold, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text("Cancel", style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: GestureDetector(
                      onTap: _addPet,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(colors: [darkGold, lightGold, primaryGold]),
                        ),
                        child: const Center(
                          child: Text("Add", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildTypeSelector() {
    return DropdownButtonFormField<String>(
      value: _selectedType,
      hint: const Text("Type", style: TextStyle(fontSize: 14)),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
      ),
      items: ['Dog', 'Cat'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: (val) {
        setState(() {
          _selectedType = val;
          _breedController.clear(); // Clear breed when type changes
        });
      },
      validator: (v) => v == null ? 'Required' : null,
    );
  }

  Widget _buildWeightField() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            decoration: InputDecoration(
              hintText: "Weight",
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedWeightUnit,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
            ),
            items: ['kg', 'g', 'lbs'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) => setState(() => _selectedWeightUnit = val!),
          ),
        ),
      ],
    );
  }

  Widget _buildSexSelector() {
    return DropdownButtonFormField<String>(
      value: _selectedSex,
      hint: const Text("Sex", style: TextStyle(fontSize: 14)),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
      ),
      items: ['Male', 'Female'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: (val) => setState(() => _selectedSex = val),
      validator: (v) => v == null ? 'Required' : null,
    );
  }

  Widget _buildHybridBreedField() {
    return TextFormField(
      key: _breedFieldKey,
      controller: _breedController,
      decoration: InputDecoration(
        hintText: 'Breed',
        hintStyle: const TextStyle(fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_drop_down, color: Colors.orange, size: 30),
          onPressed: () {
            final List<String> options = (_selectedType != null) ? (_breeds[_selectedType] ?? []) : [];
            if (options.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Type first")));
              return;
            }
            
            final RenderBox renderBox = _breedFieldKey.currentContext!.findRenderObject() as RenderBox;
            final offset = renderBox.localToGlobal(Offset.zero);
            
            showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                offset.dx,
                offset.dy + renderBox.size.height,
                offset.dx + renderBox.size.width,
                0,
              ),
              items: options.map((String breed) {
                return PopupMenuItem<String>(
                  value: breed,
                  child: Text(breed),
                );
              }).toList(),
            ).then((value) {
              if (value != null) {
                setState(() {
                  _breedController.text = value;
                });
              }
            });
          },
        ),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildPickerField(String label, String? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.black),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value ?? label, style: TextStyle(color: value == null ? Colors.grey[600] : Colors.black, fontSize: 14)),
            const Icon(Icons.arrow_drop_down, color: Colors.orange, size: 30),
          ],
        ),
      ),
    );
  }

  void _showAgePicker() {
    List<String> ages = ["1 week", "1 month", "2 months", "1 yr old", "2 yrs old", "3 yrs old", "4 yrs old", "5 yrs old"];
    String tempAge = _selectedAge ?? ages[0];
    
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 300,
        color: Colors.white,
        child: Column(
          children: [
            _buildPickerHeader("Select Age", () {
              setState(() => _selectedAge = tempAge);
              Navigator.pop(context);
            }),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 45,
                onSelectedItemChanged: (i) => tempAge = ages[i],
                children: ages.map((a) => Center(child: Text(a))).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBirthdayPicker() async {
    final DateTime? picked = await showDatePicker(
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
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: darkGold),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedBirthday = "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  Widget _buildPickerHeader(String title, VoidCallback onDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextButton(onPressed: onDone, child: const Text("Done")),
        ],
      ),
    );
  }
}
