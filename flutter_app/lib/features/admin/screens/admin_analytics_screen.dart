import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  bool   _loading    = true;
  int    _total      = 0;
  int    _fixed      = 0;
  int    _open       = 0;
  int    _shallow    = 0;
  int    _moderate   = 0;
  int    _deep       = 0;
  double _totalCost  = 0;
  double _avgCost    = 0;
  double _budget     = 100000; // default budget INR 1 lakh
  List<Map<String, dynamic>> _weeklyData = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      final reports = await client
          .from('reports')
          .select('status, submitted_at, ai_results(severity, repair_cost_max)');

      final list = reports as List;
      _total    = list.length;
      _fixed    = list.where((r) => r['status'] == 'fixed').length;
      _open     = list.where((r) =>
          !['fixed', 'rejected'].contains(r['status'])).length;

      int shallow = 0, moderate = 0, deep = 0;
      double totalCost = 0;
      int costCount = 0;

      // Weekly report counts (last 7 days)
      final Map<String, int> weekMap = {};
      for (int i = 6; i >= 0; i--) {
        final day = DateTime.now().subtract(Duration(days: i));
        final key = '${day.month}/${day.day}';
        weekMap[key] = 0;
      }

      for (final r in list) {
        final ai = r['ai_results'];
        if (ai is Map) {
          final sev = ai['severity'] as String?;
          if (sev == 'shallow')  shallow++;
          if (sev == 'moderate') moderate++;
          if (sev == 'deep')     deep++;
          final cost = (ai['repair_cost_max'] as num?)?.toDouble();
          if (cost != null) { totalCost += cost; costCount++; }
        }

        // Weekly count
        final submitted = DateTime.tryParse(r['submitted_at'] ?? '');
        if (submitted != null) {
          final diff = DateTime.now().difference(submitted).inDays;
          if (diff < 7) {
            final key = '${submitted.month}/${submitted.day}';
            weekMap[key] = (weekMap[key] ?? 0) + 1;
          }
        }
      }

      _shallow   = shallow;
      _moderate  = moderate;
      _deep      = deep;
      _totalCost = totalCost;
      _avgCost   = costCount > 0 ? totalCost / costCount : 0;
      _weeklyData = weekMap.entries
          .map((e) => {'day': e.key, 'count': e.value})
          .toList();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [

                  // ── KPI Cards ─────────────────────────────────────
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.6,
                    children: [
                      _KpiCard('Total Reports', _total.toString(),
                          Icons.report, theme.colorScheme.primary),
                      _KpiCard('Fixed', _fixed.toString(),
                          Icons.check_circle, Colors.green),
                      _KpiCard('Open', _open.toString(),
                          Icons.pending, Colors.orange),
                      _KpiCard('Total Cost Est.',
                          '₹${_formatNum(_totalCost)}',
                          Icons.currency_rupee, Colors.purple),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Budget tracker ────────────────────────────────
                  _SectionTitle('Budget tracker'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Text('Budget: ₹${_formatNum(_budget)}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: _editBudget,
                            child: const Text('Edit'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (_totalCost / _budget).clamp(0.0, 1.0),
                            minHeight: 16,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(
                              _totalCost > _budget
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '₹${_formatNum(_totalCost)} used of ₹${_formatNum(_budget)} '
                          '(${((_totalCost / _budget) * 100).clamp(0, 999).toStringAsFixed(1)}%)',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (_totalCost > _budget)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Over budget by ₹${_formatNum(_totalCost - _budget)}',
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Severity breakdown ────────────────────────────
                  _SectionTitle('Severity breakdown'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _total == 0
                          ? const Center(child: Text('No data yet'))
                          : Row(children: [
                              SizedBox(
                                width: 140,
                                height: 140,
                                child: PieChart(PieChartData(
                                  sections: [
                                    if (_shallow > 0)
                                      PieChartSectionData(
                                        value: _shallow.toDouble(),
                                        color: Colors.green,
                                        title: '$_shallow',
                                        radius: 50,
                                        titleStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    if (_moderate > 0)
                                      PieChartSectionData(
                                        value: _moderate.toDouble(),
                                        color: Colors.orange,
                                        title: '$_moderate',
                                        radius: 50,
                                        titleStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    if (_deep > 0)
                                      PieChartSectionData(
                                        value: _deep.toDouble(),
                                        color: Colors.red,
                                        title: '$_deep',
                                        radius: 50,
                                        titleStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                      ),
                                  ],
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 30,
                                )),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  _Legend(Colors.green, 'Shallow', _shallow),
                                  const SizedBox(height: 8),
                                  _Legend(Colors.orange, 'Moderate', _moderate),
                                  const SizedBox(height: 8),
                                  _Legend(Colors.red, 'Deep', _deep),
                                  const SizedBox(height: 12),
                                  Text('Avg cost: ₹${_formatNum(_avgCost)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Weekly reports bar chart ───────────────────────
                  _SectionTitle('Reports this week'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 160,
                        child: _weeklyData.isEmpty
                            ? const Center(child: Text('No data'))
                            : BarChart(BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: (_weeklyData
                                        .map((d) => (d['count'] as int)
                                            .toDouble())
                                        .reduce((a, b) => a > b ? a : b) +
                                    1),
                                barTouchData: BarTouchData(enabled: false),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  topTitles: AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (v, _) {
                                        final idx = v.toInt();
                                        if (idx >= _weeklyData.length)
                                          return const SizedBox();
                                        return Text(
                                          _weeklyData[idx]['day'],
                                          style: const TextStyle(
                                              fontSize: 10),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                gridData: FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                barGroups: _weeklyData
                                    .asMap()
                                    .entries
                                    .map((e) => BarChartGroupData(
                                          x: e.key,
                                          barRods: [
                                            BarChartRodData(
                                              toY: (e.value['count'] as int)
                                                  .toDouble(),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              width: 18,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                      top: Radius.circular(4)),
                                            ),
                                          ],
                                        ))
                                    .toList(),
                              )),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Resolution rate ───────────────────────────────
                  _SectionTitle('Resolution rate'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Reports fixed'),
                            Text(
                              '$_fixed / $_total',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _total == 0 ? 0 : _fixed / _total,
                            minHeight: 12,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation(
                                Colors.green),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _total == 0
                              ? 'No reports yet'
                              : '${((_fixed / _total) * 100).toStringAsFixed(1)}% resolution rate',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  void _editBudget() {
    final ctrl = TextEditingController(text: _budget.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set monthly budget (INR)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '₹ ',
            labelText: 'Budget amount',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                setState(() => _budget = val);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatNum(double n) {
    if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000)   return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700)),
      );
}

class _KpiCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color    color;
  const _KpiCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(title,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ]),
        ),
      );
}

class _Legend extends StatelessWidget {
  final Color  color;
  final String label;
  final int    count;
  const _Legend(this.color, this.label, this.count);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ($count)',
            style: const TextStyle(fontSize: 12)),
      ]);
}
