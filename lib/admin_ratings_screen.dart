import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'widgets/gold_blobs_background.dart';

class AdminRatingsScreen extends StatelessWidget {
  const AdminRatingsScreen({super.key});

  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref().child("ratings");

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("User Feedback & Ratings"),
        backgroundColor: primaryGold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GoldBlobsBackground(
        child: StreamBuilder(
          stream: db.onValue,
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
              Map data = snapshot.data!.snapshot.value as Map;
              List<MapEntry> ratingsList = data.entries.toList();
              
              // Sort by timestamp descending
              ratingsList.sort((a, b) => (b.value['timestamp'] ?? 0).compareTo(a.value['timestamp'] ?? 0));

              return ListView.builder(
                padding: const EdgeInsets.all(15),
                itemCount: ratingsList.length,
                itemBuilder: (context, index) {
                  var ratingData = ratingsList[index].value;
                  return _buildRatingCard(ratingData);
                },
              );
            } else if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star_outline, size: 60, color: Colors.grey),
                    SizedBox(height: 10),
                    Text("No ratings yet.", style: TextStyle(color: Colors.grey, fontSize: 18)),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildRatingCard(Map data) {
    int rating = data['rating'] ?? 0;
    String username = data['username'] ?? 'Anonymous';
    String feedback = data['feedback'] ?? '';
    var ts = data['timestamp'];
    String dateStr = ts != null 
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts))
        : 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryGold.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                username,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                dateStr,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              return Icon(
                i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                color: primaryGold,
                size: 20,
              );
            }),
          ),
          if (feedback.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: lightGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                feedback,
                style: const TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
