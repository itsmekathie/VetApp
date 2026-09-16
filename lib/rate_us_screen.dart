import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'widgets/gold_blobs_background.dart';

class RateUsScreen extends StatefulWidget {
  final String userId;
  final String username;

  const RateUsScreen({super.key, required this.userId, required this.username});

  @override
  State<RateUsScreen> createState() => _RateUsScreenState();
}

class _RateUsScreenState extends State<RateUsScreen> {
  int _rating = 0;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmitting = false;

  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
  final Color lightGold = const Color(0xFFFBDB83);

  Future<void> _submitRating() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a star rating.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final db = FirebaseDatabase.instance.ref();
      await db.child("ratings").push().set({
        'userId': widget.userId,
        'username': widget.username,
        'rating': _rating,
        'feedback': _feedbackController.text.trim(),
        'timestamp': ServerValue.timestamp,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Thank you for your feedback!")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting rating: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const SizedBox(height: 60),
                // Header Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: lightGold.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryGold.withOpacity(0.3), width: 2),
                  ),
                  child: Icon(Icons.star_rounded, color: primaryGold, size: 80),
                ),
                const SizedBox(height: 30),
                Text(
                  "Rate Us!",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: darkGold,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  "Enjoying the DocLoy Vet App?\nWe'd love to hear your feedback!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Star Rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 50,
                        color: primaryGold,
                      ),
                      onPressed: () => setState(() => _rating = index + 1),
                    );
                  }),
                ),
                const SizedBox(height: 30),

                // Feedback TextField
                TextField(
                  controller: _feedbackController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: "Share your thoughts (optional)...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: primaryGold),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: primaryGold, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Submit Button
                GestureDetector(
                  onTap: _isSubmitting ? null : _submitRating,
                  child: Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: LinearGradient(
                        colors: [darkGold, primaryGold, lightGold],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryGold.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "SUBMIT",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
