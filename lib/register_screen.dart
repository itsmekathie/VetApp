import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'verify_email_screen.dart';
import 'email_service.dart';
import 'responsive_layout.dart';
import 'dart:math';
import 'widgets/gold_blobs_background.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String? _selectedSuffix;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPassController = TextEditingController();
  final _contactNumberController = TextEditingController();

  File? _profileImage;
  final ImagePicker _picker = ImagePicker();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _termsAccepted = false;
  bool _isLoading = false;

  final List<String> _suffixes = ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPassController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please accept the Terms and Conditions')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text;
      
      String otp = (Random().nextInt(900000) + 100000).toString();
      
      // Save OTP to Firebase for secure verification
      final String encodedEmail = email.replaceAll('.', ',');
      await FirebaseDatabase.instance.ref('otp_verifications/$encodedEmail').set({
        'otp': otp,
        'timestamp': ServerValue.timestamp,
      });

      await EmailService.sendOTP(email, otp);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(
            firstName: _firstNameController.text.trim(),
            middleName: _middleNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            suffix: _selectedSuffix,
            contactNumber: '+63 ${_contactNumberController.text.trim()}',
            email: email,
            password: password,
            profileImage: _profileImage,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      String errorMsg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false, 
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: ResponsiveConstraints(
            maxWidth: 600, // Constrain form width for Tablet/Desktop
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Image.asset(
                        'assets/icon/DVC.png', 
                        height: ResponsiveLayout.isMobile(context) ? 120 : 160,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => const Icon(Icons.pets, size: 80, color: Color(0xFFB8860B)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Create Account', 
                        style: TextStyle(
                          fontSize: ResponsiveLayout.isMobile(context) ? 28 : 34, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                      const SizedBox(height: 10),
                      // ... remaining elements stay centered by ResponsiveConstraints
                      GestureDetector(
                      onTap: _pickImage,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                            child: _profileImage == null ? const Icon(Icons.person, size: 45, color: Colors.grey) : null,
                          ),
                          const SizedBox(height: 8),
                          const Text('tap to add profile image', style: TextStyle(color: Colors.grey, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_firstNameController, 'First name')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(_middleNameController, 'Middle name')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_lastNameController, 'Last name')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextFieldSuffix('Suffix (optional)', _suffixes, _selectedSuffix, (val) => setState(() => _selectedSuffix = val))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      _emailController, 
                      'Email', 
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (!v.toLowerCase().endsWith('@gmail.com') || v.trim() == '@gmail.com') {
                          return 'Only @gmail.com accounts are allowed';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_passwordController, 'Password', obscureText: _obscurePassword, toggleObscure: () => setState(() => _obscurePassword = !_obscurePassword))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(_confirmPassController, 'Confirm pa.', obscureText: _obscureConfirmPassword, toggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      _contactNumberController, 
                      'Contact Number', 
                      keyboardType: TextInputType.phone,
                      prefixText: '+63 ',
                      formatters: [PhoneNumberFormatter()],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        String digits = v.replaceAll(RegExp(r'\D'), '');
                        if (digits.length != 10) return 'Must be 10 digits';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Checkbox(value: _termsAccepted, onChanged: (val) => setState(() => _termsAccepted = val ?? false)),
                        const Text('I agree to the '),
                        GestureDetector(
                          onTap: _showTermsAndConditions,
                          child: const Text('terms and Conditions', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _isLoading ? const CircularProgressIndicator(color: Color(0xFFB8860B)) : _buildGradientButton('Register', _register),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String hint, {
    bool obscureText = false, 
    VoidCallback? toggleObscure, 
    TextInputType? keyboardType, 
    List<TextInputFormatter>? formatters,
    String? prefixText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller, 
      obscureText: obscureText, 
      keyboardType: keyboardType, 
      inputFormatters: formatters,
      decoration: InputDecoration(
        hintText: hint, 
        prefixText: prefixText,
        counterText: "",
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        suffixIcon: toggleObscure != null ? IconButton(icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility), onPressed: toggleObscure) : null,
      ),
      validator: validator ?? (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildTextFieldSuffix(String hint, List<String> items, String? value, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value, hint: Text(hint, style: const TextStyle(fontSize: 14)), isExpanded: true,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.orange, size: 30),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownField(String hint, List<String> items, String? value, Function(String?) onChanged, {bool isRequired = true}) {
    return DropdownButtonFormField<String>(
      value: value, hint: Text(hint, style: const TextStyle(fontSize: 14)), isExpanded: true,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.orange, size: 30),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.black)),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      validator: isRequired ? (v) => v == null ? 'Required' : null : null,
    );
  }

  Widget _buildGradientButton(String text, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(colors: [Color(0xFF8A6E2F), Color(0xFFFBDB83), Color(0xFFB8860B)]),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }

  void _showTermsAndConditions() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Terms",
      pageBuilder: (context, anim1, anim2) {
        return TermsAndConditionsWindow();
      },
    );
  }
}

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll(RegExp(r'\D'), '');
    
    if (text.isNotEmpty && (text.startsWith('0') || !text.startsWith('9'))) {
      return oldValue;
    }

    if (text.length > 10) {
      text = text.substring(0, 10);
    }

    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 3) formatted += ' ';
      if (i == 6) formatted += ' ';
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class TermsAndConditionsWindow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: GoldBlobsBackground(
        useSafeArea: false,
        child: SafeArea(
          child: ResponsiveConstraints(
            maxWidth: 800, // Wider constraints for document reading
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28), onPressed: () => Navigator.pop(context)),
                      Expanded(
                        child: Text(
                          'Terms and Conditions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: ResponsiveLayout.isMobile(context) ? 32 : 40, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.black
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data Privacy & Security', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
                      const SizedBox(height: 16),
                      _section('1. Explicit Consent for Data Processing', """By registering an account, you grant the Clinic explicit permission to collect, store, and process your personal identifiable information (PII)—including your full name, mobile number, and email address—alongside your pet’s profiles, medical records, and booking history. This data is collected strictly to facilitate your service requests and will be retained only as long as your account remains active or as required by local veterinary record retention laws."""),
                      _section('2. Scope of Internal Data Sharing', """Your data will be accessed exclusively by authorized clinic personnel, including practicing veterinarians, veterinary technicians, and front-desk staff, solely to provide medical care and fulfill product reservations. No data will be shared with external third parties or third-party marketers without your separate, explicit consent, except when required by law or in emergency public health/zoonotic disease situations."""),
                      _section('3. User Data Rights and Erasure', """You maintain full ownership and control over your digital information. You have the right to review, update, or correct your personal and pet data directly through the application profile settings. Furthermore, you may request the permanent deletion of your account and all associated personal data from our active servers at any time, provided you have no outstanding, unfulfilled product reservations or pending emergency appointments."""),
                      _section('4. Data Security Safeguards', """We implement industry-standard technical, organizational, and physical security measures—including data encryption, secure servers, and strict access controls—to protect your information from unauthorized access, accidental loss, alteration, or data breaches. While we strive to maintain maximum security, you acknowledge that no digital transmission over the internet can be guaranteed 100% secure."""),
                      _section('5. Communications and Notifications', """By completing the registration process, you agree to receive automated, non-marketing system communications from the application. These include, but are not limited to, appointment confirmations, booking reminders, product reservation availability alerts, and critical security or account-related updates via SMS, push notifications, or email."""),
                      
                      const SizedBox(height: 24),
                      const Text('Application Usage & Policies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
                      const SizedBox(height: 16),
                      _section('6. Fair Use and Cancellation Policy', """Because the application offers booking and scheduling services entirely free of charge with no upfront payment or deposit required, you agree to use the system responsibly. If you are unable to attend a scheduled clinic appointment, you are required to cancel or reschedule your slot through the app at least twenty-four (24) hours before the appointment time to free up the slot for other pets in need."""),
                      _section('7. No-Show Consequences and Account Suspension', """To maintain operational efficiency and fair access for all clients, the Clinic tracks attendance and pick-up patterns. The Clinic reserves the right to temporarily flag, restrict, or permanently suspend your account from making future bookings or product reservations if you accumulate three (3) consecutive "No-Shows" without a valid, pre-notified cancellation."""),
                      _section('8. Accuracy of Information and Profiles', """You agree to provide true, accurate, and current information when creating your user account and individual pet profiles. Falsifying identities, intentionally misrepresenting a pet's medical emergency status, or withholding critical information regarding a pet's aggressive behavior or highly contagious medical condition is strictly prohibited and constitutes grounds for immediate account termination."""),
                      _section('9. Product Reservation Holding Windows', """Reserving a product through the application does not constitute a legal sale, as no financial transaction occurs online. Reserved products will be held at the physical clinic for a strict maximum window of forty-eight (48) hours from the time of confirmation. If the items are not claimed and paid for in-store within this timeframe, the reservation will automatically expire, and the items will be reallocated to general stock."""),
                      _section('10. Limitation of Liability and "As-Is" Clause', """The application is provided to users on an "as-is" and "as-available" basis without warranties of any kind. The Clinic and its software developers are not liable for any direct or indirect inconveniences, lost slots, or missed product allocations resulting from temporary system downtimes, server glitches, network connectivity errors, or routine application maintenance."""),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
          SizedBox(height: 4),
          Text(content, style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4)),
        ],
      ),
    );
  }
}
