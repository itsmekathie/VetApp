class BookingManager {
  // Static list to hold selected services during the current app session
  static final List<Map<String, dynamic>> _pendingServices = [];

  static List<Map<String, dynamic>> get pendingServices => List.unmodifiable(_pendingServices);

  static void addService(Map<String, dynamic> service) {
    // Check if already added to prevent duplicates
    bool exists = _pendingServices.any((s) => s['name'] == service['name']);
    if (!exists) {
      _pendingServices.add(service);
    }
  }

  static void removeService(int index) {
    if (index >= 0 && index < _pendingServices.length) {
      _pendingServices.removeAt(index);
    }
  }

  static void clear() {
    _pendingServices.clear();
  }

  static bool get isEmpty => _pendingServices.isEmpty;
  
  static int get count => _pendingServices.length;
}
