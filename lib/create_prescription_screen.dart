import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'widgets/gold_blobs_background.dart';
import 'widgets/prescription_pad_widget.dart';
import 'cloudinary_service.dart';

class CreatePrescriptionScreen extends StatefulWidget {
  final Map<String, dynamic> petInfo;
  final Map<String, dynamic> adminInfo;

  const CreatePrescriptionScreen({
    super.key, 
    required this.petInfo, 
    required this.adminInfo,
  });

  @override
  State<CreatePrescriptionScreen> createState() => _CreatePrescriptionScreenState();
}

class _CreatePrescriptionScreenState extends State<CreatePrescriptionScreen> {
  final List<MedicationEntry> _medications = [];
  final GlobalKey _boundaryKey = GlobalKey();

  // Current Input State
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _dosageCtrl = TextEditingController(text: "100");
  final TextEditingController _durationCtrl = TextEditingController(text: "1");
  
  final String _dosageUnit = "mg";
  final String _durationUnit = "Week";
  final List<String> _selectedTimes = [];
  String _foodInstruction = "After Food";

  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  void _addMedication() {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter medication name")));
      return;
    }
    setState(() {
      _medications.add(MedicationEntry(
        name: _nameCtrl.text,
        dosage: "${_dosageCtrl.text}$_dosageUnit",
        duration: "${_durationCtrl.text} $_durationUnit",
        times: List.from(_selectedTimes),
        foodNote: _foodInstruction,
        importantNote: _noteCtrl.text,
      ));
      // Clear inputs
      _nameCtrl.clear();
      _noteCtrl.clear();
      _selectedTimes.clear();
      _dosageCtrl.text = "100";
      _durationCtrl.text = "1";
    });
  }

  Future<void> _createAndUpload() async {
    if (_medications.isEmpty && _nameCtrl.text.isNotEmpty) {
      _addMedication();
    }
    if (_medications.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please add at least one medication")));
      return;
    }

    // Show Uploading Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UploadingDialog(primaryGold: primaryGold),
    );

    try {
      // Ensure the UI is updated and renderer is ready
      await Future.delayed(const Duration(milliseconds: 500));

      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw "Renderer not ready. Please try again.";

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 2. Save to Temp File
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/prescription_${DateTime.now().millisecondsSinceEpoch}.png').create();
      await file.writeAsBytes(pngBytes);

      // 3. Upload to Cloudinary
      String? imageUrl = await CloudinaryService.uploadImage(file);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        if (imageUrl != null) {
          Navigator.pop(context, imageUrl); // Return URL to completion dialog
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload failed. Please try again.")));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _showPreview() {
    // Temporarily add current if not empty
    List<MedicationEntry> tempMeds = List.from(_medications);
    if (_nameCtrl.text.isNotEmpty) {
      tempMeds.add(MedicationEntry(
        name: _nameCtrl.text,
        dosage: "${_dosageCtrl.text}$_dosageUnit",
        duration: "${_durationCtrl.text} $_durationUnit",
        times: List.from(_selectedTimes),
        foodNote: _foodInstruction,
        importantNote: _noteCtrl.text,
      ));
    }

    if (tempMeds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nothing to preview")));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrescriptionPadWidget(
                patientName: widget.petInfo['name'] ?? 'N/A',
                date: widget.petInfo['date'] ?? DateFormat('MMM dd, yyyy').format(DateTime.now()),
                species: widget.petInfo['species'] ?? 'N/A',
                age: widget.petInfo['age'] ?? 'N/A',
                sex: widget.petInfo['sex'] ?? 'N/A',
                medications: tempMeds,
                dvmName: widget.adminInfo['dvmName'] ?? '',
                licNo: widget.adminInfo['licNo'] ?? '',
                ptrNo: widget.adminInfo['ptrNo'] ?? '',
                contactNo: widget.adminInfo['contactNo'] ?? '',
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: primaryGold),
                  child: const Text("Close Preview", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine preview medications for the off-screen renderer
    List<MedicationEntry> offScreenMeds = List.from(_medications);
    if (_nameCtrl.text.isNotEmpty) {
      offScreenMeds.add(MedicationEntry(
        name: _nameCtrl.text,
        dosage: "${_dosageCtrl.text}$_dosageUnit",
        duration: "${_durationCtrl.text} $_durationUnit",
        times: List.from(_selectedTimes),
        foodNote: _foodInstruction,
        importantNote: _noteCtrl.text,
      ));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGold,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("Create Prescription", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: GoldBlobsBackground(
        child: Stack(
          children: [
            // 1. HIDDEN CAPTURE AREA (Pushed completely off screen to fix overflow/white space)
            Positioned(
              left: -5000, 
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  width: 400,
                  color: Colors.white,
                  child: PrescriptionPadWidget(
                    patientName: widget.petInfo['name'] ?? 'N/A',
                    date: widget.petInfo['date'] ?? DateFormat('MMM dd, yyyy').format(DateTime.now()),
                    species: widget.petInfo['species'] ?? 'N/A',
                    age: widget.petInfo['age'] ?? 'N/A',
                    sex: widget.petInfo['sex'] ?? 'N/A',
                    medications: offScreenMeds.isEmpty ? [MedicationEntry(name: 'Template', dosage: '', duration: '', times: [], foodNote: '', importantNote: '')] : offScreenMeds,
                    dvmName: widget.adminInfo['dvmName'] ?? '',
                    licNo: widget.adminInfo['licNo'] ?? '',
                    ptrNo: widget.adminInfo['ptrNo'] ?? '',
                    contactNo: widget.adminInfo['contactNo'] ?? '',
                  ),
                ),
              ),
            ),

            // 2. MAIN VISIBLE FORM
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_medications.isNotEmpty) ...[
                    const Text("Added Medications:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 10),
                    ..._medications.map((m) => Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                        title: Text(m.name, style: TextStyle(fontWeight: FontWeight.bold, color: darkGold)),
                        subtitle: Text("${m.dosage} | ${m.duration} | ${m.times.join(', ')}", style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => setState(() => _medications.remove(m))),
                      ),
                    )),
                    const Divider(height: 30),
                  ],
                  
                  const Text("Medication Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: "e.g. Amoxicillin",
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryGold.withOpacity(0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryGold.withOpacity(0.1))),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  Row(
                    children: [
                      Expanded(child: _buildCounter("Dosage", _dosageCtrl, suffix: _dosageUnit)),
                      const SizedBox(width: 15),
                      Expanded(child: _buildCounter("Duration", _durationCtrl, suffix: _durationUnit)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  const Text("Medication Time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ["Morning", "Noon", "Evening", "Night"].map((time) {
                      bool isSelected = _selectedTimes.contains(time);
                      return ChoiceChip(
                        label: Text(time),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            if (val) _selectedTimes.add(time);
                            else _selectedTimes.remove(time);
                          });
                        },
                        selectedColor: primaryGold,
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  
                  const Text("To be Taken", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: ["After Food", "Before Food"].map((food) {
                      bool isSelected = _foodInstruction == food;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ChoiceChip(
                          label: Text(food),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setState(() => _foodInstruction = food);
                          },
                          selectedColor: primaryGold,
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  
                  const Text("Important Note", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: "Add specific instructions...",
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryGold.withOpacity(0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryGold.withOpacity(0.1))),
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  OutlinedButton.icon(
                    onPressed: _addMedication,
                    icon: const Icon(Icons.add),
                    label: const Text("Another Medicine"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      foregroundColor: primaryGold,
                      side: BorderSide(color: primaryGold, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: _showPreview,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text("Preview Pad"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: lightGold,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                  const SizedBox(height: 15),
                  GestureDetector(
                    onTap: _createAndUpload,
                    child: Container(
                      width: double.infinity,
                      height: 55,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(colors: [darkGold, primaryGold]),
                        boxShadow: [
                          BoxShadow(color: primaryGold.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Center(
                        child: Text("Create", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounter(String label, TextEditingController ctrl, {String? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: primaryGold.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle_outline, size: 22, color: darkGold), 
                onPressed: () {
                  int val = int.tryParse(ctrl.text) ?? 1;
                  if (val > 1) {
                    setState(() => ctrl.text = (val - 1).toString());
                  }
                }
              ),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                ),
              ),
              if (suffix != null)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Text(suffix, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: darkGold)),
                ),
              IconButton(
                icon: Icon(Icons.add_circle_outline, size: 22, color: darkGold), 
                onPressed: () {
                  int val = int.tryParse(ctrl.text) ?? 0;
                  setState(() => ctrl.text = (val + 1).toString());
                }
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UploadingDialog extends StatelessWidget {
  final Color primaryGold;
  const _UploadingDialog({required this.primaryGold});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
            ),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: primaryGold.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
              child: Icon(Icons.file_upload_outlined, color: primaryGold, size: 40),
            ),
            const SizedBox(height: 20),
            const Text("Just a minute....", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              "Your file is uploading right now. Just please wait for a few moments",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 25),
            LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryGold),
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 15),
            const Text("Uploading...", style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Cancel", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
