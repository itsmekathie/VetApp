import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:firebase_database/firebase_database.dart';
import 'product_reservation_screen.dart';
import 'appointment_scheduling_screen.dart';
import 'package:intl/intl.dart';

import 'responsive_layout.dart';

class PetChatbot extends StatefulWidget {
  final String? initialMessage;
  final String userId;
  final String username;
  final String? fullName;

  const PetChatbot({
    super.key,
    this.initialMessage,
    required this.userId,
    required this.username,
    this.fullName,
  });

  @override
  _PetChatbotState createState() => _PetChatbotState();
}

class _PetChatbotState extends State<PetChatbot> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  late GenerativeModel _model;

  bool _isLoading = false;
  bool _isHistoryLoading = true;
  bool _showQuickQuestions = true;
  bool _initialProcessed = false;

  List<Map<String, dynamic>> _shopProducts = [];
  StreamSubscription<DatabaseEvent>? _chatSubscription;

  final List<String> _quickQuestions = [
    "How do I book an appointment?",
    "What are your hours and location?",
    "How can I request a medication refill?"
  ];

  final String _apiKey = "AIzaSyCAVdwUwDcOJnrdt9ACZxwjykb55Jrnph4";
  final Color clinicGreen = const Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _fetchProducts();

    _model = GenerativeModel(
      model: 'gemini-3.5-flash',
      apiKey: _apiKey.trim(),
    );

    _startLiveSync();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startLiveSync() {
    final ref = FirebaseDatabase.instance.ref('chat_history/${widget.userId}');

    _chatSubscription = ref.orderByChild('timestamp').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        final data = event.snapshot.value;
        List<Map<String, dynamic>> syncedMessages = [];

        if (data is Map) {
          data.forEach((key, value) {
            var msg = Map<String, dynamic>.from(value as Map);
            if (msg['suggestions'] is String && (msg['suggestions'] as String).isNotEmpty) {
              msg['suggestions'] = (msg['suggestions'] as String).split(',').where((s) => s.isNotEmpty).toList();
            }
            syncedMessages.add(msg);
          });
        }

        syncedMessages.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));

        setState(() {
          _messages.clear();
          _messages.addAll(syncedMessages);
          _isHistoryLoading = false;
          _showQuickQuestions = _messages.length <= 1;
        });
        _scrollToBottom();
      } else {
        _isHistoryLoading = false;
        _saveWelcomeMessage();
      }

      if (!_initialProcessed && widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
        _initialProcessed = true;
        _handleInitialQuery(widget.initialMessage!);
      }
    });
  }

  void _handleInitialQuery(String text) {
    bool alreadyExists = _messages.any((m) => m['message'] == text && m['role'] == 'user');
    if (!alreadyExists && !_isLoading) {
      _processMessage(text);
    }
  }

  Future<void> _saveWelcomeMessage() async {
    final welcome = {
      "role": "bot",
      "message": "Hi ${widget.username}!! I am I pet, your pet expert assistant. 🐾 What would you need today?",
      "timestamp": ServerValue.timestamp,
    };
    await _saveMessageToFirebase(welcome);
  }

  Future<void> _saveMessageToFirebase(Map<String, dynamic> msg) async {
    try {
      var dataToSave = Map<String, dynamic>.from(msg);
      if (dataToSave['suggestions'] is List) {
        dataToSave['suggestions'] = (dataToSave['suggestions'] as List).join(',');
      }
      if (!dataToSave.containsKey('timestamp')) {
        dataToSave['timestamp'] = ServerValue.timestamp;
      }

      await FirebaseDatabase.instance
          .ref('chat_history/${widget.userId}')
          .push()
          .set(dataToSave);
    } catch (e) {
      debugPrint("Firebase Save Error: $e");
    }
  }

  Future<void> _fetchProducts() async {
    try {
      final snapshot = await FirebaseDatabase.instance.ref('products').get();
      if (snapshot.exists) {
        Map data = snapshot.value as Map;
        setState(() {
          _shopProducts = data.entries.map((e) {
            var val = Map<String, dynamic>.from(e.value as Map);
            val['id'] = e.key;
            return val;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Firebase Fetch Error: $e");
    }
  }

  String _buildSystemInstruction() {
    String productList = _shopProducts.map((p) => "- ${p['name']}: ${p['description']} (₱${p['price']})").join("\n");
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return """
INSTRUCTION: You are 'I pet', a professional vet assistant for dogs and cats. 
- Current Date: $today.
- Output at end: [SCHEDULE: YYYY-MM-DD] if they want to book.
- Suggest medicine: [SUGGEST: Product Name].
- Keep responses concise and friendly.

AVAILABLE SHOP ITEMS:
$productList
""";
  }

  void _sendMessage() async {
    String text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;
    _controller.clear();
    _processMessage(text);
  }

  Future<void> _processMessage(String text) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    await _saveMessageToFirebase({"role": "user", "message": text});

    try {
      final fullPrompt = "${_buildSystemInstruction()}\nUser: $text";
      final response = await _model.generateContent([Content.text(fullPrompt)]);
      final botText = response.text ?? "I'm sorry, I couldn't process that.";

      RegExp prodExp = RegExp(r"\[SUGGEST: (.*?)\]");
      List<String> suggestions = [];
      for (var match in prodExp.allMatches(botText)) {
        suggestions.add(match.group(1)!.trim());
      }

      RegExp schedExp = RegExp(r"\[SCHEDULE: (.*?)\]");
      var schedMatch = schedExp.firstMatch(botText);
      String? scheduleDate = schedMatch?.group(1)?.trim();

      String cleanText = botText.replaceAll(prodExp, "").replaceAll(schedExp, "").trim();

      await _saveMessageToFirebase({
        "role": "bot",
        "message": cleanText,
        "suggestions": suggestions,
        "scheduleDate": scheduleDate,
      });

      if (mounted) {
        setState(() => _isLoading = false);
        if (scheduleDate != null) _navigateToSchedule(scheduleDate);
      }
    } catch (e) {
      debugPrint("AI Error: $e");
      if (mounted) setState(() => _isLoading = false);
      _saveMessageToFirebase({
        "role": "bot",
        "message": "Notice: AI service busy. Please try again later.",
      });
    }
  }

  void _navigateToSchedule(String dateStr) {
    try {
      DateTime parsedDate = DateTime.parse(dateStr);
      if (parsedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        parsedDate = DateTime.now().add(const Duration(days: 1));
      }
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => AppointmentSchedulingScreen(
            userId: widget.userId, 
            username: widget.username, 
            fullName: widget.fullName,
            initialDate: parsedDate,
          )));
        }
      });
    } catch (e) {
      debugPrint("Date error: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return Center(
      child: ResponsiveConstraints(
        maxWidth: 700, // Limit chatbot width for Desktop/Tablet
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
              color: Color(0xFFF0F4F8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30))
          ),
          child: Column(
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 15), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              Row(
                children: [
                  // Reverted to ai_dogbot.png as per user request
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/ai_dogbot.png',
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Icon(Icons.pets, color: clinicGreen),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text("I pet AI", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: clinicGreen)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
                ],
              ),
              const Divider(),
              if (_isHistoryLoading)
                const Expanded(child: Center(child: CupertinoActivityIndicator()))
              else
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Row(children: [SizedBox(width: 32), CupertinoActivityIndicator(radius: 7), SizedBox(width: 8), Text("Typing...", style: TextStyle(fontSize: 12, color: Colors.grey))]));
                      }

                      final msg = _messages[index];
                      bool isUser = msg["role"] == "user";
                      List<String> suggestions = [];
                      if (msg["suggestions"] is List) {
                        suggestions = List<String>.from(msg["suggestions"]);
                      } else if (msg["suggestions"] is String && (msg["suggestions"] as String).isNotEmpty) {
                        suggestions = (msg["suggestions"] as String).split(',').where((s) => s.isNotEmpty).toList();
                      }

                      return _buildMessageBubble(msg, isUser, suggestions);
                    },
                  ),
                ),
              if (_showQuickQuestions && !_isLoading && !_isHistoryLoading)
                _buildQuickQuestions(),
              _buildInputArea(keyboardPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser, List<String> suggestions) {
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
                color: isUser ? clinicGreen : Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(15),
                    topRight: const Radius.circular(15),
                    bottomLeft: Radius.circular(isUser ? 15 : 0),
                    bottomRight: Radius.circular(isUser ? 0 : 15)
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]
            ),
            child: Text(msg["message"] ?? "", style: TextStyle(color: isUser ? Colors.white : HexColor.fromHex(isUser ? "#FFFFFF" : "#000000"))),
          ),
        ),
        if (!isUser && suggestions.isNotEmpty) ...[
          const SizedBox(height: 5),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: suggestions.map((s) => _buildProductChip(s)).toList(),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (!isUser && msg["scheduleDate"] != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: ElevatedButton.icon(
              onPressed: () => _navigateToSchedule(msg["scheduleDate"]),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text("Open Scheduler (${msg["scheduleDate"]})"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: clinicGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildQuickQuestions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: _quickQuestions.map((q) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
                onPressed: () => _processMessage(q),
                style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    side: BorderSide(color: clinicGreen)
                ),
                child: Text(q, style: TextStyle(color: clinicGreen, fontWeight: FontWeight.w600))
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildInputArea(double keyboardPadding) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Row(
        children: [
          Expanded(
              child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _sendMessage(),
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                      hintText: "What would you need today?",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16)
                  )
              )
          ),
          IconButton(
              onPressed: _isLoading ? null : _sendMessage,
              icon: Icon(Icons.send_rounded, color: _isLoading ? Colors.grey : clinicGreen)
          ),
        ],
      ),
    );
  }

  Widget _buildProductChip(String productName) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(productName, style: const TextStyle(fontSize: 12)),
        onPressed: () {
          final product = _shopProducts.firstWhere(
            (p) => p['name'].toString().toLowerCase() == productName.toLowerCase(),
            orElse: () => {},
          );
          if (product.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductReservationScreen(
                  userId: widget.userId,
                  username: widget.username,
                  fullName: widget.fullName,
                  initialProducts: [{
                    'productName': product['name'],
                    'quantity': 1,
                    'price': (product['price'] ?? 0).toDouble(),
                    'description': product['description'] ?? '',
                    'imageUrl': product['image'],
                  }],
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
