import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'appointment_scheduling_screen.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class UserAppointmentsScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? fullName;

  const UserAppointmentsScreen({
    super.key, 
    required this.userId,
    required this.username,
    this.fullName,
  });

  @override
  State<UserAppointmentsScreen> createState() => _UserAppointmentsScreenState();
}

class _UserAppointmentsScreenState extends State<UserAppointmentsScreen> {
  String _activeFilter = "Default";
  final Color primaryGold = const Color(0xFFB8860B);
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);
  final _formatter = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final database = FirebaseDatabase.instance.ref();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Bookings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.black),
            onSelected: (value) => setState(() => _activeFilter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: "Default", child: Text("Upcoming & Scheduled")),
              const PopupMenuItem(value: "Completed", child: Text("Completed")),
              const PopupMenuItem(value: "Cancelled", child: Text("Cancelled")),
              const PopupMenuItem(value: "Rejected", child: Text("Rejected")),
            ],
          ),
        ],
      ),
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: Center(
          child: ResponsiveConstraints(
            maxWidth: 900,
            child: Column(
              children: [
                const SizedBox(height: 10),
                if (_activeFilter != "Default")
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Chip(
                          label: Text("Filter: $_activeFilter", style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setState(() => _activeFilter = "Default"),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          backgroundColor: lightGold.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder(
                    stream: database.child('appointments').orderByChild('userId').equalTo(widget.userId).onValue,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                        Map data = snapshot.data!.snapshot.value as Map;
                        List<MapEntry<dynamic, dynamic>> allAppointments = data.entries.map((e) => MapEntry(e.key, e.value)).toList();
                        
                        // Sort by timestamp descending
                        allAppointments.sort((a, b) => (b.value['timestamp'] ?? 0).compareTo(a.value['timestamp'] ?? 0));

                        if (_activeFilter == "Default") {
                          var upcoming = allAppointments.where((e) => e.value['status'] == "Pending").toList();
                          var scheduled = allAppointments.where((e) => (e.value['status'] == "Approved" || e.value['status'] == "Accepted")).toList();

                          if (upcoming.isEmpty && scheduled.isEmpty) {
                            return const Center(child: Text("No upcoming or scheduled bookings."));
                          }

                          return ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            children: [
                              if (upcoming.isNotEmpty) ...[
                                _sectionHeader("Upcoming (Pending)"),
                                ...upcoming.map((e) => _buildAppointmentCard(e.value, e.key)),
                              ],
                              if (scheduled.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _sectionHeader("Scheduled (Approved)"),
                                ...scheduled.map((e) => _buildAppointmentCard(e.value, e.key)),
                              ],
                              const SizedBox(height: 20),
                            ],
                          );
                        } else {
                          var filtered = allAppointments.where((e) => e.value['status'] == _activeFilter).toList();
                          
                          if (filtered.isEmpty) {
                            return Center(child: Text("No $_activeFilter bookings."));
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              var appt = filtered[index].value;
                              var apptId = filtered[index].key;
                              return _buildAppointmentCard(appt, apptId);
                            },
                          );
                        }
                      }
                      return const Center(child: Text('No bookings yet.'));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getServiceNames(dynamic appt) {
    if (appt['services'] != null && appt['services'] is List) {
      return (appt['services'] as List)
          .map((s) => s['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join(", ");
    }
    return appt['serviceName'] ?? 'N/A';
  }

  String _getEstimatedTimes(dynamic appt) {
    if (appt['services'] != null && appt['services'] is List) {
      return (appt['services'] as List)
          .map((s) => s['estimatedTime']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join(", ");
    }
    return appt['estimatedTime'] ?? 'N/A';
  }

  Widget _sectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            title,
            style: TextStyle(
              color: darkGold,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Divider(color: primaryGold.withOpacity(0.3), thickness: 1),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildAppointmentCard(dynamic appt, String apptId) {
    DateTime date = DateTime.parse(appt['appointmentDate']);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          const Positioned(top: 0, right: 0, child: Icon(Icons.shopping_cart, color: Colors.black, size: 28)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Transaction # ${appt['referenceNumber'] ?? apptId.toString().substring(apptId.length - 6).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text("Service Booked: ${_getServiceNames(appt)}", style: const TextStyle(fontSize: 14)),
              Text("Date: ${DateFormat('MMMM dd, yyyy').format(date)}", style: const TextStyle(fontSize: 14)),
              Text("Price: ₱${_formatter.format((appt['price'] ?? 0).round())}", style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: () => _showServiceDetails(appt, apptId),
                  child: const Text("See details", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showServiceDetails(dynamic appt, String apptId) async {
    String clientName = appt['clientName'] ?? appt['username'] ?? 'N/A';
    
    final userSnap = await FirebaseDatabase.instance.ref().child('users/${appt['userId']}').get();
    if (userSnap.exists) {
      Map userData = userSnap.value as Map;
      
      // Construct full name if available
      String fName = userData['firstName'] ?? '';
      String mName = (userData['middleName'] != null && userData['middleName'].toString().isNotEmpty) 
          ? "${userData['middleName'].toString()[0].toUpperCase()}." 
          : "";
      String lName = userData['lastName'] ?? '';
      String fullName = [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
      if (fullName.isNotEmpty) clientName = fullName;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => ResponsiveConstraints(
        maxWidth: 500,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: primaryGold, width: 3),
              color: Colors.white,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Service Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  _detailRow("Transaction # :", appt['referenceNumber'] ?? apptId),
                  _detailRow("Client :", clientName),
                  _detailRow("Service booked :", _getServiceNames(appt)),
                  _detailRow("Total Price :", "₱${_formatter.format((appt['price'] ?? 0).round())}"),
                  _detailRow("Date :", DateFormat('MMM dd, yyyy').format(DateTime.parse(appt['appointmentDate']))),
                  _detailRow("Estimated Time :", _getEstimatedTimes(appt)),
                  _detailRow("Client Type :", appt['clientType'] ?? 'N/A'),
                  if (appt['status'] == 'Rejected' && appt['rejectionReason'] != null)
                    _detailRow("Rejection Reason :", appt['rejectionReason'], color: Colors.red),
                  const SizedBox(height: 15),
                  const Align(alignment: Alignment.centerLeft, child: Text("Pet Information:", style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Builder(
                      builder: (context) {
                        var pets = appt['petDetails'];
                        if (pets == null) return const Text("N/A");
                        List<dynamic> petList = pets is List ? pets : [pets];
                        
                        return Column(
                          children: petList.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                if (petList.length > 1) 
                                   Align(alignment: Alignment.centerLeft, child: Text("Pet ${petList.indexOf(p) + 1}", style: TextStyle(fontSize: 12, color: primaryGold, fontWeight: FontWeight.bold))),
                                _petDetailRow("Name :", p['name'] ?? 'N/A'),
                                Row(
                                  children: [
                                    Expanded(child: _petDetailRow("Species :", p['type'] ?? 'N/A')),
                                    Expanded(child: _petDetailRow("Breed :", p['breed'] ?? 'N/A')),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(child: _petDetailRow("Sex :", p['sex'] ?? 'N/A')),
                                    Expanded(child: _petDetailRow("Age :", p['age'] ?? 'N/A')),
                                  ],
                                ),
                                _petDetailRow("Weight :", p['weight'] ?? 'N/A'),
                                _petDetailRow("Birthday :", p['birthday'] ?? 'N/A'),
                                if (p != petList.last) Divider(color: primaryGold.withOpacity(0.3), height: 10),
                              ],
                            ),
                          )).toList(),
                        );
                      }
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Align(alignment: Alignment.centerLeft, child: Text("Patient(s) Condition :", style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: primaryGold),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Text(appt['reason'] ?? '', style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 20),
                  if (appt['status'] != 'Completed')
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (appt['status'] == 'Pending' || appt['status'] == 'Approved')
                          _actionButton(Icons.block, "Cancel", Colors.red, () => _confirmAction("cancel", appt, apptId)),
                        if (appt['status'] == 'Pending' || appt['status'] == 'Approved' || appt['status'] == 'Cancelled' || appt['status'] == 'Rejected')
                          _actionButton(Icons.calendar_month, "Reschedule", Colors.indigo, () => _confirmAction("reschedule", appt, apptId)),
                      ],
                    ),
                  const SizedBox(height: 20),
                  if (appt['status'] == 'Completed') ...[
                    const Divider(),
                    const Center(
                      child: Text(
                        "For Medical Support & Follow-ups Please Contact Us!",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder(
                      future: FirebaseDatabase.instance.ref().child('admins').limitToFirst(1).get(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          Map admin = (snapshot.data!.value as Map).values.first;
                          return Column(
                            children: [
                              _contactRow(
                                Icons.phone, 
                                admin['contactNumber'] ?? 'N/A',
                                onTap: admin['contactNumber'] != null 
                                  ? () => _launchURL("tel:${admin['contactNumber'].toString().replaceAll(RegExp(r'[^0-9+]'), '')}") 
                                  : null,
                              ),
                              _contactRow(
                                Icons.facebook, 
                                "Facebook Page",
                                iconColor: const Color(0xFF1877F2),
                                onTap: admin['facebook'] != null ? () => _launchURL(admin['facebook']) : null,
                              ),
                              _contactRow(
                                Icons.chat_bubble, 
                                "Chat on Messenger",
                                iconColor: const Color(0xFF0084FF),
                                onTap: admin['messenger'] != null ? () => _launchURL(admin['messenger']) : null,
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const Divider(),
                  ],
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)],
                        ),
                      ),
                      child: const Center(child: Text("Close", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
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

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: color != null ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $urlString')),
        );
      }
    }
  }

  Widget _contactRow(IconData icon, String value, {Color? iconColor, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: (iconColor ?? primaryGold).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: (iconColor ?? primaryGold).withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: iconColor ?? primaryGold),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  value, 
                  style: TextStyle(
                    fontSize: 13, 
                    color: Colors.blueGrey.shade800, 
                    fontWeight: FontWeight.w500,
                    decoration: onTap != null ? TextDecoration.underline : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              ),
              if (onTap != null)
                Icon(Icons.open_in_new, size: 14, color: (iconColor ?? primaryGold).withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _petDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 5),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _confirmAction(String action, dynamic appt, String apptId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Booking?'),
        content: Text('Are you sure you want to $action this appointment?'),
        actions: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(c, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: const Center(
                      child: Text("No", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(c, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: const Center(
                      child: Text("Yes", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = FirebaseDatabase.instance.ref();
      if (action == "cancel") {
        await db.child('appointments/$apptId').update({'status': 'Cancelled'});
        if (mounted) {
          Navigator.pop(context); // Close details dialog
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Appointment Cancelled")));
        }
      } else {
        // Reschedule
        if (mounted) {
          Navigator.pop(context); // Close details dialog
          Navigator.push(context, MaterialPageRoute(builder: (c) => AppointmentSchedulingScreen(
            serviceName: appt['services'] != null && (appt['services'] as List).isNotEmpty 
                ? (appt['services'] as List).first['name'] 
                : appt['serviceName'],
            userId: widget.userId,
            username: widget.username,
            fullName: widget.fullName,
            oldAppointmentId: apptId, // Pass the ID of the appointment being rescheduled
          )));
        }
      }
    }
  }
}
