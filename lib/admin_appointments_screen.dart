import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'widgets/gold_blobs_background.dart';

class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  State<AdminAppointmentsScreen> createState() => _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> {
  final _database = FirebaseDatabase.instance.ref();
  final _searchController = TextEditingController();
  String _searchQuery = "";
  final _formatter = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Requests'),
        backgroundColor: const Color(0xFFB8860B),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search bookings or reservations...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: GoldBlobsBackground(
        child: StreamBuilder(
          stream: _database.onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
              Map rootData = snapshot.data!.snapshot.value as Map;
              Map? appointmentsData = rootData['appointments'] as Map?;
              Map? reservationsData = rootData['product_reservations'] as Map?;

              List<MapEntry> items = [];
              
              if (appointmentsData != null) {
                for (var entry in appointmentsData.entries) {
                  var val = Map<String, dynamic>.from(entry.value as Map);
                  val['_id'] = entry.key;
                  val['_type'] = 'appointment';
                  if (val['status'] == 'Pending') items.add(MapEntry(entry.key, val));
                }
              }
              
              if (reservationsData != null) {
                for (var entry in reservationsData.entries) {
                  var val = Map<String, dynamic>.from(entry.value as Map);
                  val['_id'] = entry.key;
                  val['_type'] = 'reservation';
                  if (val['status'] == 'Reserved') items.add(MapEntry(entry.key, val));
                }
              }

              var filteredItems = items.where((e) {
                String user = (e.value['username'] ?? '').toString().toLowerCase();
                String client = (e.value['clientName'] ?? '').toString().toLowerCase();
                String service = (e.value['serviceName'] ?? '').toString().toLowerCase();
                String prod = (e.value['productName'] ?? '').toString().toLowerCase();
                String ref = (e.value['referenceNumber'] ?? '').toString().toLowerCase();
                return user.contains(_searchQuery) || client.contains(_searchQuery) || service.contains(_searchQuery) || prod.contains(_searchQuery) || ref.contains(_searchQuery);
              }).toList();

              if (filteredItems.isEmpty) return const Center(child: Text('No new requests found.'));

              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  var item = filteredItems[index].value;
                  var itemId = filteredItems[index].key;
                  bool isAppt = item['_type'] == 'appointment';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              FutureBuilder(
                                future: FirebaseDatabase.instance.ref().child('users/${item['userId']}').get(),
                                builder: (context, snapshot) {
                                  String clientDisplay = item['clientName'] ?? item['username'] ?? 'Unknown User';
                                  if (snapshot.hasData && snapshot.data!.exists) {
                                    Map userData = snapshot.data!.value as Map;
                                    String fName = userData['firstName'] ?? '';
                                    String mName = (userData['middleName'] != null && userData['middleName'].toString().isNotEmpty) 
                                        ? "${userData['middleName'].toString()[0].toUpperCase()}." 
                                        : "";
                                    String lName = userData['lastName'] ?? '';
                                    String fullName = [fName, mName, lName].where((s) => s.isNotEmpty).join(" ");
                                    if (fullName.isNotEmpty) clientDisplay = fullName;
                                  }
                                  return Text(clientDisplay, style: const TextStyle(fontWeight: FontWeight.bold));
                                },
                              ),
                              Text(item['referenceNumber'] ?? 'N/A', style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isAppt ? Colors.purple.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        isAppt ? 'Service Booking' : 'Product Reservation',
                                        style: TextStyle(
                                          fontSize: 10, 
                                          fontWeight: FontWeight.bold, 
                                          color: isAppt ? Colors.purple : Colors.orange[800]
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    if (isAppt) ...[
                                      Text('Service: ${item['serviceName'] ?? (item['services'] != null ? (item['services'] as List).map((s) => s['name']).join(', ') : 'N/A')}'),
                                      Text('Pet(s): ${item['petDetails'] is List ? (item['petDetails'] as List).map((p) => p['name'] ?? 'N/A').join(', ') : (item['petDetails']?['name'] ?? 'N/A')}'),
                                      if (item['appointmentDate'] != null)
                                        Builder(builder: (context) {
                                          try {
                                            DateTime date = DateTime.parse(item['appointmentDate']);
                                            return Text('Date: ${DateFormat('MMM dd, hh:mm a').format(date)}');
                                          } catch(e) {
                                            return Text('Date: ${item['appointmentDate']}');
                                          }
                                        }),
                                      Text('Total: ₱${_formatter.format((item['price'] ?? 0).round())}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFB8860B))),
                                    ] else ...[
                                       if (item['items'] != null)
                                        ... (item['items'] as List).map((i) => Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('• ${i['productName']} (x${i['quantity']})'),
                                            if (i['variationName'] != null)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 10),
                                                child: Text('Variation: ${i['variationName']}', style: TextStyle(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.bold)),
                                              ),
                                          ],
                                        ))
                                      else ...[
                                        Text('Product: ${item['productName']}'),
                                        if (item['variationName'] != null)
                                          Text('Variation: ${item['variationName']}', style: TextStyle(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.bold)),
                                      ],
                                      Text('Total: ₱${_formatter.format((item['totalPrice'] ?? 0).round())}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFB8860B))),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    onPressed: () => isAppt ? _updateStatus(itemId, 'Approved') : _updateReservationStatus(itemId, 'Accepted'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green, 
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(70, 30),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    child: const Text('Accept', style: TextStyle(fontSize: 11)),
                                  ),
                                  const SizedBox(height: 4),
                                  ElevatedButton(
                                    onPressed: () => isAppt ? _showApptRejectDialog(itemId) : _showReservationRejectDialog(itemId, item),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red, 
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(70, 30),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    child: const Text('Reject', style: TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
            return const Center(child: Text('No new requests.'));
          },
        ),
      ),
    );
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    await _database.child('appointments/$id').update({'status': newStatus});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking accepted and moved to Schedules')));
    }
  }

  Future<void> _updateReservationStatus(String id, String newStatus) async {
    await _database.child('product_reservations/$id').update({'status': newStatus});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reservation $newStatus and moved to Schedules')));
    }
  }

  void _showApptRejectDialog(String id) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Booking'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Enter reason for rejection...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              String reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide a reason')));
                return;
              }
              Navigator.pop(context);
              _processApptRejection(id, reason);
            },
            child: const Text('Confirm Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _processApptRejection(String id, String reason) async {
    await _database.child('appointments/$id').update({
      'status': 'Rejected',
      'rejectionReason': reason,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking rejected.')));
    }
  }

  void _showReservationRejectDialog(String orderId, dynamic order) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Reservation'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Enter reason for rejection...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              String reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide a reason')));
                return;
              }
              Navigator.pop(context);
              _processReservationRejection(orderId, order, reason);
            },
            child: const Text('Confirm Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _processReservationRejection(String orderId, dynamic order, String reason) async {
    await _database.child('product_reservations/$orderId').update({
      'status': 'Rejected',
      'rejectionReason': reason,
    });

    // Return stock for all items
    List<dynamic> items = order['items'] ?? [{
      'productName': order['productName'],
      'baseName': order['baseName'],
      'variationName': order['variationName'],
      'quantity': order['quantity'] ?? 1,
    }];

    for (var item in items) {
      final baseName = item['baseName'] ?? item['productName'];
      final productSnap = await _database.child('products').orderByChild('name').equalTo(baseName).get();
      if (productSnap.exists) {
        String pKey = productSnap.children.first.key!;
        Map pData = productSnap.children.first.value as Map;

        if (item['variationName'] != null && pData['variations'] != null) {
          var vars = pData['variations'];
          if (vars is List) {
            for (int i = 0; i < vars.length; i++) {
              if (vars[i]['name'] == item['variationName']) {
                vars[i]['quantity'] = (vars[i]['quantity'] ?? 0) + (item['quantity'] as int);
                break;
              }
            }
          } else if (vars is Map) {
            for (var key in vars.keys) {
              if (vars[key]['name'] == item['variationName']) {
                vars[key]['quantity'] = (vars[key]['quantity'] ?? 0) + (item['quantity'] as int);
                break;
              }
            }
          }
          await _database.child('products/$pKey').update({'variations': vars});
        } else {
          int currentStock = pData['quantity'] ?? 0;
          await _database.child('products/$pKey').update({'quantity': currentStock + (item['quantity'] as int)});
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reservation rejected and stock returned.')));
    }
  }
}
