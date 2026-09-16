import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_database/firebase_database.dart';
// import 'package:intl/intl.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class PetListScreen extends StatefulWidget {
  final String userId;
  const PetListScreen({super.key, required this.userId});

  @override
  State<PetListScreen> createState() => _PetListScreenState();
}

class _PetListScreenState extends State<PetListScreen> {
  final _database = FirebaseDatabase.instance.ref();
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, size: 30), onPressed: () => Navigator.pop(context)),
                        const Text("My Pets", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder(
                      stream: _database.child('users/${widget.userId}/pets').onValue,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                          List<dynamic> pets = snapshot.data!.snapshot.value as List;
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: pets.length,
                            itemBuilder: (context, index) {
                              var pet = Map<String, dynamic>.from(pets[index]);
                              return _buildPetCard(pet, index);
                            },
                          );
                        }
                        return const Center(child: Text("No pets registered yet."));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPetCard(Map<String, dynamic> pet, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => PetInformationScreen(userId: widget.userId, petIndex: index, petData: pet))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [darkGold, lightGold, primaryGold]),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            const CircleAvatar(radius: 30, backgroundColor: Colors.white24, child:  Icon(Icons.pets, color: Colors.white, size: 30)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pet['name'] ?? 'Pet', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                  Text(pet['type'] ?? 'Species', style: const TextStyle(fontSize: 16, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 30, color: Colors.black87),
          ],
        ),
      ),
    );
  }
}

class PetInformationScreen extends StatefulWidget {
  final String userId;
  final int petIndex;
  final Map<String, dynamic> petData;

  const PetInformationScreen({super.key, required this.userId, required this.petIndex, required this.petData});

  @override
  State<PetInformationScreen> createState() => _PetInformationScreenState();
}

class _PetInformationScreenState extends State<PetInformationScreen> {
  final _database = FirebaseDatabase.instance.ref();
  late Map<String, dynamic> _currentPet;
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
    _currentPet = widget.petData;
    _listenToUpdates();
  }

  void _listenToUpdates() {
    _database.child('users/${widget.userId}/pets/${widget.petIndex}').onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        setState(() {
          _currentPet = Map<String, dynamic>.from(event.snapshot.value as Map);
        });
      }
    });
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Pet"),
        content: Text("Are you sure you want to delete ${_currentPet['name']}? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePet();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePet() async {
    try {
      final snap = await _database.child('users/${widget.userId}/pets').get();
      if (snap.exists) {
        List<dynamic> pets = List.from(snap.value as List);
        if (widget.petIndex >= 0 && widget.petIndex < pets.length) {
          pets.removeAt(widget.petIndex);
          await _database.child('users/${widget.userId}/pets').set(pets);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pet deleted successfully")));
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting pet: $e"), backgroundColor: Colors.red));
      }
    }
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
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, size: 30), onPressed: () => Navigator.pop(context)),
                        const Text("Pet Informations", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        _buildInfoBox([
                          _buildInfoItem("Name", _currentPet['name'] ?? 'N/A', () => _showEditSheet("Name")),
                          _buildInfoItem("Species", _currentPet['type'] ?? 'N/A', () => _showEditSheet("Species")),
                          _buildInfoItem("Breed", _currentPet['breed'] ?? 'N/A', () => _showEditSheet("Breed")),
                          _buildInfoItem("Weight", _currentPet['weight'] ?? 'N/A', () => _showEditSheet("Weight")),
                          _buildInfoItem("Sex", _currentPet['sex'] ?? 'N/A', () => _showEditSheet("Sex")),
                          _buildInfoItem("Age", _currentPet['age'] ?? 'N/A', () => _showEditSheet("Age")),
                          _buildInfoItem("Birthday", _currentPet['birthday'] ?? '00/00/0000', () => _showEditSheet("Birthday")),
                        ]),
                        const SizedBox(height: 30),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => _confirmDelete(),
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            label: const Text("Delete Pet", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBox(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold, width: 2),
        color: Colors.white,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoItem(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 16), textAlign: TextAlign.right)),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 24),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResponsiveConstraints(
        maxWidth: 500,
        child: PetEditBottomSheet(
          userId: widget.userId,
          petIndex: widget.petIndex,
          editType: type,
          initialValue: _currentPet,
        ),
      ),
    );
  }
}

class PetEditBottomSheet extends StatefulWidget {
  final String userId;
  final int petIndex;
  final String editType;
  final Map<String, dynamic> initialValue;

  const PetEditBottomSheet({super.key, required this.userId, required this.petIndex, required this.editType, required this.initialValue});

  @override
  State<PetEditBottomSheet> createState() => _PetEditBottomSheetState();
}

class _PetEditBottomSheetState extends State<PetEditBottomSheet> {
  final _database = FirebaseDatabase.instance.ref();
  late TextEditingController _textController;
  String? _selectedOption;
  String _selectedWeightUnit = 'kg';
  
  // Custom Date States
  int _selectedMonth = DateTime.now().month;
  int _selectedDay = DateTime.now().day;
  int _selectedYear = DateTime.now().year;

  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  void initState() {
    super.initState();
    String key = widget.editType.toLowerCase() == 'name' ? 'name' : widget.editType.toLowerCase();
    if (widget.editType == 'Species') key = 'type';
    if (widget.editType == 'Weight') key = 'weight';
    _textController = TextEditingController(text: widget.initialValue[key]?.toString() ?? '');
    _selectedOption = widget.initialValue[key]?.toString();
  }

  Future<void> _save(dynamic value) async {
    String key = widget.editType.toLowerCase() == 'name' ? 'name' : widget.editType.toLowerCase();
    if (widget.editType == 'Species') key = 'type';
    if (widget.editType == 'Weight') key = 'weight';
    
    Map<String, dynamic> updates = {key: value};
    
    // If species is changed, clear breed to prevent mismatch
    if (widget.editType == 'Species') {
      updates['breed'] = ''; 
    }
    
    await _database.child('users/${widget.userId}/pets/${widget.petIndex}').update(updates);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          Text("Edit ${widget.editType}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildEditor(),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () {
                if (widget.editType == 'Birthday') {
                  _save(_textController.text);
                } else if (widget.editType == 'Name') {
                  _save(_textController.text.trim());
                } else if (widget.editType == 'Weight') {
                  _save("${_textController.text.trim()} $_selectedWeightUnit");
                } else {
                  _save(_selectedOption);
                }
              },
              child: Container(
                width: double.infinity,
                height: 55,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: LinearGradient(colors: [darkGold, lightGold, primaryGold])),
                child: const Center(child: Text("Save", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    switch (widget.editType) {
      case 'Name':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _textController,
            autofocus: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              suffixIcon: IconButton(icon: const Icon(Icons.cancel_outlined), onPressed: () => _textController.clear()),
            ),
          ),
        );
      case 'Weight':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _textController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: "Weight",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedWeightUnit,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  items: ['kg', 'g', 'lbs'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => setState(() => _selectedWeightUnit = val!),
                ),
              ),
            ],
          ),
        );
      case 'Species':
        return Column(
          children: [
            _selectionItem("Dog", Icons.pets, "DOG 🐶"),
            _selectionItem("Cat", Icons.pets, "CAT 🐱"),
          ],
        );
      case 'Sex':
        return Column(
          children: [
            _selectionItem("Male", Icons.male, "Male ♂️"),
            _selectionItem("Female", Icons.female, "Female ♀️"),
          ],
        );
      case 'Age':
        List<String> ages = ["1 week", "1 months", "2 months", "1 yr old", "2 yrs old", "3 yrs old", "4 yrs old", "5 yrs old"];
        return SizedBox(
          height: 200,
          child: CupertinoPicker(
            itemExtent: 45,
            onSelectedItemChanged: (i) => setState(() => _selectedOption = ages[i]),
            children: ages.map((a) => Center(child: Text(a))).toList(),
          ),
        );
      case 'Breed':
        return _buildBreedEditor();
      case 'Birthday':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: InkWell(
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _textController.text = "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
                });
              }
            },
            child: IgnorePointer(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: "Select Date",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _selectionItem(String value, IconData icon, String label) {
    bool isSelected = _selectedOption == value;
    return InkWell(
      onTap: () => setState(() => _selectedOption = value),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? primaryGold : Colors.grey.shade300, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (isSelected) Icon(Icons.check_circle, color: primaryGold),
          ],
        ),
      ),
    );
  }

  Widget _buildBreedEditor() {
    List<String> commonBreeds = widget.initialValue['type'] == 'Cat' 
      ? ['Puspin', 'Persian', 'Siamese', 'Maine Coon'] 
      : ['Aspin', 'Shih Tzu', 'Golden Retriever', 'German'];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          TextField(
            controller: _textController,
            decoration: const InputDecoration(hintText: "If none on the choices please type here"),
            onChanged: (v) {
              if (v.isNotEmpty) setState(() => _selectedOption = null);
            },
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 10,
            children: commonBreeds.map((b) {
              bool isSelected = _selectedOption == b;
              return ChoiceChip(
                label: Text(b),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    _selectedOption = val ? b : null;
                    if (val) _textController.clear();
                  });
                },
                selectedColor: primaryGold.withValues(alpha: 0.3),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
