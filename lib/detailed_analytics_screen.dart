import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'widgets/gold_blobs_background.dart';
import 'widgets/marquee_text.dart';

class DetailedAnalyticsScreen extends StatefulWidget {
  const DetailedAnalyticsScreen({super.key});

  @override
  State<DetailedAnalyticsScreen> createState() => _DetailedAnalyticsScreenState();
}

class _DetailedAnalyticsScreenState extends State<DetailedAnalyticsScreen> {
  String _servicesTimeframe = "Day";
  String _productsTimeframe = "Day";
  String _abvTimeframe = "Day";

  final Color primaryGold = const Color(0xFFB8860B);
  final _formatter = NumberFormat('#,###');
  final Color darkGold = const Color(0xFF8A6E2F);
  final Color lightGold = const Color(0xFFFBDB83);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instance.ref();
    String currentMonthYear = DateFormat('MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.white,
      body: GoldBlobsBackground(
        child: StreamBuilder(
          stream: db.onValue,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator());
            }

            Map data = snapshot.data!.snapshot.value as Map;
            
            return Column(
              children: [
                _buildHeader(currentMonthYear),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    children: [
                      _buildServicesReport(data),
                      const SizedBox(height: 30),
                      _buildProductsReport(data),
                      const SizedBox(height: 30),
                      _buildAbvReport(data),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(String dateStr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        children: [
          const Text(
            'DETAILED ANALYTICS LOGS',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFF333333),
            ),
          ),
          Text(
            dateStr.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: darkGold,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(thickness: 2, color: Colors.black87),
        ],
      ),
    );
  }

  Widget _buildServicesReport(Map data) {
    // Process data for services
    Map<String, double> trendData = {};
    Map<String, int> topBooked = {};

    if (data['appointments'] != null) {
      Map appts = data['appointments'] as Map;
      appts.forEach((k, v) {
        if (v['status'] == 'Completed') {
          DateTime date = DateTime.tryParse(v['appointmentDate'] ?? '') ?? DateTime.now();
          String key = _getTrendKey(date, _servicesTimeframe);
          double price = (v['totalFinalPrice'] ?? v['price'] ?? 0).toDouble();
          trendData[key] = (trendData[key] ?? 0) + price;

          if (v['services'] != null && v['services'] is List) {
            for (var s in (v['services'] as List)) {
              String name = s['name'] ?? 'Unknown';
              topBooked[name] = (topBooked[name] ?? 0) + 1;
            }
          } else {
            String name = v['serviceName'] ?? 'Unknown';
            topBooked[name] = (topBooked[name] ?? 0) + 1;
          }
        }
      });
    }

    var filledData = _fillMissingTimeframes(trendData, _servicesTimeframe);
    var sortedTop = topBooked.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var top3 = sortedTop.take(3).toList();

    return _buildReportContainer(
      title: 'REPORT 1: SERVICES REVENUE TREND',
      timeframe: _servicesTimeframe,
      onTimeframeChanged: (v) => setState(() => _servicesTimeframe = v),
      chart: _buildLineChart(filledData, primaryGold),
      bottomSection: _buildTopList('TOP 3 BOOKED SERVICES', top3, Icons.medical_services_outlined),
    );
  }

  Widget _buildProductsReport(Map data) {
    Map<String, double> trendData = {};
    Map<String, int> topReserved = {};

    if (data['product_reservations'] != null) {
      Map orders = data['product_reservations'] as Map;
      orders.forEach((k, v) {
        if (v['status'] == 'Received') {
          DateTime date = v['timestamp'] != null ? DateTime.fromMillisecondsSinceEpoch(v['timestamp']) : DateTime.now();
          String key = _getTrendKey(date, _productsTimeframe);
          double price = (v['totalFinalPrice'] ?? v['totalPrice'] ?? 0).toDouble();
          trendData[key] = (trendData[key] ?? 0) + price;

          if (v['items'] != null && v['items'] is List) {
            for (var item in (v['items'] as List)) {
              String name = item['productName'] ?? 'Unknown';
              int qty = (item['quantity'] ?? 1) as int;
              topReserved[name] = (topReserved[name] ?? 0) + qty;
            }
          } else {
            String name = v['productName'] ?? 'Unknown';
            int qty = (v['quantity'] ?? 1) as int;
            topReserved[name] = (topReserved[name] ?? 0) + qty;
          }
        }
      });
    }

    var filledData = _fillMissingTimeframes(trendData, _productsTimeframe);
    var sortedTop = topReserved.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var top3 = sortedTop.take(3).toList();

    return _buildReportContainer(
      title: 'REPORT 2: PRODUCTS REVENUE TREND',
      timeframe: _productsTimeframe,
      onTimeframeChanged: (v) => setState(() => _productsTimeframe = v),
      chart: _buildLineChart(filledData, Colors.blueGrey),
      bottomSection: _buildTopList('TOP 3 RESERVED PRODUCTS', top3, Icons.inventory_2_outlined),
    );
  }

  Widget _buildAbvReport(Map data) {
    Map<String, List<double>> rawData = {};

    void process(Map? section, bool isProduct) {
      if (section == null) return;
      section.forEach((k, v) {
        String status = v['status'] ?? '';
        if (status == 'Completed' || status == 'Received') {
          DateTime date = isProduct 
            ? (v['timestamp'] != null ? DateTime.fromMillisecondsSinceEpoch(v['timestamp']) : DateTime.now())
            : (DateTime.tryParse(v['appointmentDate'] ?? '') ?? DateTime.now());
          
          String key = _getTrendKey(date, _abvTimeframe);
          double price = (v['totalFinalPrice'] ?? v['price'] ?? v['totalPrice'] ?? 0).toDouble();
          if (!rawData.containsKey(key)) rawData[key] = [];
          rawData[key]!.add(price);
        }
      });
    }

    process(data['appointments'] as Map?, false);
    process(data['product_reservations'] as Map?, true);

    Map<String, double> abvData = {};
    rawData.forEach((key, list) {
      double sum = list.reduce((a, b) => a + b);
      abvData[key] = sum / list.length;
    });

    var filledData = _fillMissingTimeframes(abvData, _abvTimeframe);

    return _buildReportContainer(
      title: 'REPORT 3: AVERAGE BOOKING VALUE (ABV)',
      timeframe: _abvTimeframe,
      onTimeframeChanged: (v) => setState(() => _abvTimeframe = v),
      chart: _buildLineChart(filledData, Colors.green),
      bottomSection: const SizedBox(height: 10),
    );
  }

  Widget _buildReportContainer({
    required String title,
    required String timeframe,
    required Function(String) onTimeframeChanged,
    required Widget chart,
    required Widget bottomSection,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart, size: 20, color: Colors.black87),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        const Divider(color: Colors.black12, thickness: 1),
        const SizedBox(height: 10),
        SizedBox(height: 180, child: chart),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('Filter Timeframe: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
            _buildTimeframeBtn('Day', timeframe, onTimeframeChanged),
            _buildTimeframeBtn('Week', timeframe, onTimeframeChanged),
            _buildTimeframeBtn('Month', timeframe, onTimeframeChanged),
            _buildTimeframeBtn('Year', timeframe, onTimeframeChanged),
          ],
        ),
        bottomSection,
        const Divider(color: Colors.black26, thickness: 1.5, height: 40),
      ],
    );
  }

  Widget _buildTimeframeBtn(String label, String current, Function(String) onTap) {
    bool isSelected = label == current;
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black87 : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          isSelected ? '*$label*' : label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTopList(String title, List<MapEntry<String, int>> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 15),
        Row(
          children: [
            const Icon(Icons.emoji_events, size: 16, color: Color(0xFFB8860B)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(items.length, (index) {
          String rank = index == 0 ? "🥇 #1" : index == 1 ? "🥈 #2" : "🥉 #3";
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const SizedBox(width: 25),
                Text(rank, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 10),
                Expanded(
                  child: MarqueeText(
                    text: items[index].key,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _getTrendKey(DateTime date, String timeframe) {
    if (timeframe == "Day") return DateFormat('MM/dd').format(date);
    if (timeframe == "Week") {
      int weekNumber = ((date.day - 1) / 7).floor() + 1;
      return "W$weekNumber ${DateFormat('MMM').format(date)} ${date.year}";
    }
    if (timeframe == "Month") return "${DateFormat('MMM').format(date)} ${date.year}";
    return "${date.year}";
  }

  Map<String, double> _fillMissingTimeframes(Map<String, double> data, String timeframe) {
    Map<String, double> result = {};
    DateTime now = DateTime.now();

    if (timeframe == "Day") {
      for (int i = 6; i >= 0; i--) {
        DateTime date = now.subtract(Duration(days: i));
        String key = _getTrendKey(date, "Day");
        result[key] = data[key] ?? 0.0;
      }
    } else if (timeframe == "Week") {
      DateTime firstOfMonth = DateTime(now.year, now.month, 1);
      DateTime lastOfMonth = DateTime(now.year, now.month + 1, 0);
      int totalDays = lastOfMonth.day;
      int numWeeks = (totalDays / 7).ceil();

      for (int w = 1; w <= numWeeks; w++) {
        DateTime dateInWeek = DateTime(now.year, now.month, (w - 1) * 7 + 1);
        String key = _getTrendKey(dateInWeek, "Week");
        result[key] = data[key] ?? 0.0;
      }
    } else if (timeframe == "Month") {
      for (int m = 1; m <= 12; m++) {
        DateTime date = DateTime(now.year, m, 1);
        String key = _getTrendKey(date, "Month");
        result[key] = data[key] ?? 0.0;
      }
    } else if (timeframe == "Year") {
      for (int i = 4; i >= 0; i--) {
        DateTime date = DateTime(now.year - i, 1, 1);
        String key = _getTrendKey(date, "Year");
        result[key] = data[key] ?? 0.0;
      }
    }
    return result;
  }

  Widget _buildLineChart(Map<String, double> data, Color color) {
    var keys = data.keys.toList();
    List<FlSpot> spots = [];
    double maxVal = 0;
    for (int i = 0; i < keys.length; i++) {
      double val = data[keys[i]]!;
      if (val > maxVal) maxVal = val;
      spots.add(FlSpot(i.toDouble(), val));
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.black12, strokeWidth: 1, dashArray: [5, 5]),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx < 0 || idx >= keys.length) return const SizedBox();
                String label = keys[idx];
                // Simplify labels for display
                if (label.contains(' W')) {
                  label = label.split(' ')[0]; // Show "W1"
                } else if (label.split(' ').length == 2 && label.length > 4) {
                   label = label.split(' ')[0]; // Show "Jan" instead of "Jan 2026"
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString(),
                style: const TextStyle(fontSize: 8, color: Colors.grey),
              ),
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.black87,
            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
              return touchedBarSpots.map((barSpot) {
                return LineTooltipItem(
                  '${keys[barSpot.x.toInt()]}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                  children: [
                    TextSpan(
                      text: '₱${_formatter.format(barSpot.y.round())}',
                      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
