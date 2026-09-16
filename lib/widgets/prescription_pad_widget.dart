import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MedicationEntry {
  final String name;
  final String dosage;
  final String duration;
  final List<String> times;
  final String foodNote;
  final String importantNote;

  MedicationEntry({
    required this.name,
    required this.dosage,
    required this.duration,
    required this.times,
    required this.foodNote,
    required this.importantNote,
  });
}

class PrescriptionPadWidget extends StatelessWidget {
  final String patientName;
  final String date;
  final String species;
  final String age;
  final String sex;
  final List<MedicationEntry> medications;
  final String dvmName;
  final String licNo;
  final String ptrNo;
  final String contactNo;

  const PrescriptionPadWidget({
    super.key,
    required this.patientName,
    required this.date,
    required this.species,
    required this.age,
    required this.sex,
    required this.medications,
    required this.dvmName,
    required this.licNo,
    required this.ptrNo,
    required this.contactNo,
  });

  @override
  Widget build(BuildContext context) {
    const Color darkBlue = Color(0xFF002366);
    
    return Container(
      width: 400, // Fixed width for image generation consistency
      padding: const EdgeInsets.all(25),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Patient, Date
          Row(
            children: [
              const Text("Patient: ", style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue, fontSize: 13)),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: darkBlue))),
                  child: Text(patientName, style: const TextStyle(color: darkBlue, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 15),
              const Text("Date: ", style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue, fontSize: 13)),
              Container(
                width: 100,
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: darkBlue))),
                child: Text(date, style: const TextStyle(color: darkBlue, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Species, Age, Sex
          Row(
            children: [
              const Text("Species: ", style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue, fontSize: 13)),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: darkBlue))),
                  child: Text(species, style: const TextStyle(color: darkBlue, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 15),
              const Text("Age: ", style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue, fontSize: 13)),
              Container(
                width: 60,
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: darkBlue))),
                child: Text(age, style: const TextStyle(color: darkBlue, fontSize: 13)),
              ),
              const SizedBox(width: 15),
              const Text("Sex: ", style: TextStyle(fontWeight: FontWeight.bold, color: darkBlue, fontSize: 13)),
              _sexOption("Male", sex == "Male", darkBlue),
              _sexOption("Female", sex == "Female", darkBlue),
            ],
          ),
          const SizedBox(height: 40),
          // Rx Symbol
          const Text(
            "Rx",
            style: TextStyle(
              fontSize: 70,
              fontWeight: FontWeight.bold,
              color: darkBlue,
              fontFamily: 'Serif',
            ),
          ),
          const SizedBox(height: 25),
          // Medications List
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: medications.length,
              itemBuilder: (context, index) {
                final med = medications[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${index + 1}. ${med.name} (${med.dosage})",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkBlue),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Duration: ${med.duration} | Time: ${med.times.join(', ')}",
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      Text(
                        "Instruction: ${med.foodNote}",
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      if (med.importantNote.isNotEmpty)
                        Text(
                          "Note: ${med.importantNote}",
                          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black54),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Footer / Signature Section
          const Divider(color: darkBlue, thickness: 1.5),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 220, // Fixed width for the entire signature block
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 2),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: darkBlue, width: 1.2))),
                    child: Text(
                      dvmName.isNotEmpty ? dvmName : "__________________",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: darkBlue, fontSize: 14),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.center,
                    child: Text("DVM", style: TextStyle(fontSize: 10, color: darkBlue, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  _footerRow("Lic. No.:", licNo, darkBlue),
                  _footerRow("PTR No.:", ptrNo, darkBlue),
                  _footerRow("Contact No.:", contactNo, darkBlue),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          // Branding
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: darkBlue, width: 2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: Text(
                    "DOCLOY VET CLINIC",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: darkBlue,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset("assets/icon/DVC.png", height: 25, errorBuilder: (c, e, s) => const Icon(Icons.pets, color: darkBlue, size: 20)),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    "DOCLOY VET CLINIC",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: darkBlue,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sexOption(String label, bool isSelected, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 4),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
              color: isSelected ? color : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 85, // Fixed width for labels to ensure vertical alignment of the start of values
            child: Text(
              label, 
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color, width: 0.8))),
              child: Text(
                value, 
                style: TextStyle(fontSize: 12, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
