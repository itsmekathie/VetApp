import 'package:flutter/material.dart';
import 'responsive_layout.dart';
import 'widgets/gold_blobs_background.dart';

class PoliciesScreen extends StatelessWidget {
  const PoliciesScreen({super.key});

  final Color darkGold = const Color(0xFF8A6E2F);
  final Color primaryGold = const Color(0xFFB8860B);
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
              maxWidth: 900,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Text(
                    "App Policies",
                    style: TextStyle(
                      fontSize: ResponsiveLayout.isMobile(context) ? 28 : 36,
                      fontWeight: FontWeight.bold,
                      color: darkGold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle("PART 1: TERMS & CONDITIONS"),
                          const Divider(thickness: 1.5),
                          
                          _buildSubTitle("1. Service Booking & Cancellation Policy"),
                          _buildBulletPoint("Booking Approvals: Any service request submitted through the app is a request only. Your appointment is not finalized until you receive a \"Confirmed\" notification or SMS from the clinic."),
                          _buildBulletPoint("Late Arrivals: We offer a strict 15-minute grace period. If you arrive more than 15 minutes late for your scheduled slot, your appointment may be canceled or treated as a walk-in to avoid delaying other patients."),
                          _buildBulletPoint("Cancellation Window: Please cancel or reschedule your appointments at least 4 hours in advance. Frequent no-shows or late cancellations may result in a temporary suspension of your app booking privileges."),
                          
                          const SizedBox(height: 20),
                          _buildSubTitle("2. Free Product Reservation Policy (Pick Up Only)"),
                          _buildBulletPoint("Pick Up Only: All product reservations made via this app are strictly for in-clinic pickup. We do not offer shipping, mailing, or home delivery options under any circumstances."),
                          _buildBulletPoint("48-Hour Holding Window: Once your reservation is confirmed as \"Ready for Pickup,\" the clinic will hold the items for exactly 48 hours."),
                          _buildBulletPoint("Automatic Cancellation: If the reserved products are not collected within the 48-hour window, your reservation will be automatically canceled, and the items will be returned to our general inventory."),
                          _buildBulletPoint("Pricing Disclaimer: Final payment is processed at the clinic during pickup. Prices are subject to minor adjustments based on the active in-clinic rates at the exact time of collection."),
                          
                          const SizedBox(height: 20),
                          _buildSubTitle("3. Medical Emergency Disclaimer"),
                          _buildEmergencyBox(
                            "CRITICAL EMERGENCY WARNING: This app booking and reservation platform is intended solely for routine appointments, check-ups, and non-urgent inventory tracking. \n\nDO NOT WAIT: If your pet is experiencing a severe, acute, or life-threatening medical emergency, DO NOT use the app or wait for an appointment approval. Bring your pet directly to our physical emergency clinic immediately or contact our emergency hotline."
                          ),
                          
                          const SizedBox(height: 40),
                          _buildSectionTitle("PART 2: PRIVACY POLICY"),
                          const Divider(thickness: 1.5),
                          
                          _buildSubTitle("1. Information We Collect"),
                          _buildBulletPoint("Account Information: Your full name, phone number, and email address."),
                          _buildBulletPoint("Pet Profiles: Your pet's name, age, breed, weight, medical records, and vaccination history."),
                          _buildBulletPoint("App Usage Details: Device push notification tokens to send you automated booking alerts, pickup reminders, and clinic updates."),
                          
                          const SizedBox(height: 20),
                          _buildSubTitle("2. How We Use Your Data"),
                          _buildBulletPoint("Process, confirm, and manage your veterinary service appointments."),
                          _buildBulletPoint("Hold and track your local product reservations."),
                          _buildBulletPoint("Maintain accurate operational medical charts for your pet within our clinic."),
                          
                          const SizedBox(height: 20),
                          _buildSubTitle("3. Data Protection and Sharing"),
                          _buildBulletPoint("No Third-Party Sales: We strictly do not sell, rent, trade, or distribute your personal details, contact info, or pet profiles to third-party marketing companies or advertisers."),
                          _buildBulletPoint("App Security: All user data transferred through the app is encrypted in transit and securely handled to prevent unauthorized access."),
                          
                          const SizedBox(height: 40),
                          Center(
                            child: Text(
                              "Last updated: August 2026",
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 5),
      child: Text(
        title,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryGold),
      ),
    );
  }

  Widget _buildSubTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 10),
      child: Text(
        title,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkGold),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("• ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyBox(String text) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.redAccent,
          height: 1.4,
        ),
      ),
    );
  }
}
