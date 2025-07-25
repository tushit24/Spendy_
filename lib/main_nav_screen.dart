import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    _HomeTab(),
    _GroupsTab(),
    _ActivityTab(),
    _ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.card,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.yellow,
        unselectedItemColor: AppTheme.textSecondary,
        showUnselectedLabels: true,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded, color: AppTheme.blue),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_rounded, color: AppTheme.green),
            label: 'Groups',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded, color: AppTheme.red),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded, color: AppTheme.yellow),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// Home Tab with animated Add Expense button and chart placeholder
class _HomeTab extends StatefulWidget {
  const _HomeTab();
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _addBtnController;
  late Animation<double> _scaleAnim;
  late ConfettiController _confettiController;

  // Mock data for groups and members
  final List<String> _groups = ['Trip Buddies', 'Roommates', 'Office Lunch'];
  final Map<String, List<String>> _groupMembers = {
    'Trip Buddies': ['Alice', 'Bob', 'Charlie'],
    'Roommates': ['David', 'Eve'],
    'Office Lunch': ['Frank', 'Grace', 'Heidi'],
  };
  final List<Map<String, dynamic>> _recentExpenses = [
    {
      'title': 'Dinner at Pizza Place',
      'subtitle': 'Split with Friends',
      'amount': -500,
      'color': AppTheme.red,
    },
    {
      'title': 'Cab to Airport',
      'subtitle': 'Split with Group',
      'amount': -1200,
      'color': AppTheme.yellow,
    },
    {
      'title': 'Movie Night',
      'subtitle': 'Split with Friends',
      'amount': -800,
      'color': AppTheme.green,
    },
  ];

  void _showAddExpenseSheet() {
    String selectedGroup = _groups[0];
    List<String> selectedMembers = List.from(_groupMembers[selectedGroup]!);
    String splitType = 'Equally';
    final TextEditingController amountController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    Map<String, TextEditingController> customControllers = {};
    String? customError;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final members = _groupMembers[selectedGroup]!;
            if (splitType == 'Custom') {
              for (var m in members) {
                customControllers.putIfAbsent(m, () => TextEditingController());
              }
            } else {
              customControllers.clear();
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.textSecondary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Add Expense',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: selectedGroup,
                      decoration: const InputDecoration(labelText: 'Group'),
                      items: _groups
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: (g) {
                        setState(() {
                          selectedGroup = g!;
                          selectedMembers = List.from(
                            _groupMembers[selectedGroup]!,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: splitType,
                      decoration: const InputDecoration(
                        labelText: 'Split Type',
                      ),
                      items: ['Equally', 'Custom']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (s) => setState(() => splitType = s!),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Participants',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: members.map((m) {
                        final selected = selectedMembers.contains(m);
                        return FilterChip(
                          label: Text(m),
                          selected: selected,
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                selectedMembers.add(m);
                                if (splitType == 'Custom') {
                                  customControllers.putIfAbsent(
                                    m,
                                    () => TextEditingController(),
                                  );
                                }
                              } else {
                                selectedMembers.remove(m);
                                customControllers.remove(m);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (splitType == 'Custom' &&
                        amountController.text.isNotEmpty &&
                        selectedMembers.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          const Text('Enter each participant\'s share:'),
                          ...selectedMembers.map(
                            (m) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: TextField(
                                controller: customControllers[m],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(labelText: m),
                              ),
                            ),
                          ),
                          if (customError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                customError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    if (amountController.text.isNotEmpty &&
                        selectedMembers.isNotEmpty)
                      _buildSplitSummary(
                        amountController.text,
                        selectedMembers,
                        splitType,
                        customControllers,
                      ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        if (amountController.text.isEmpty ||
                            selectedMembers.isEmpty) {
                          return;
                        }
                        final amt = int.tryParse(amountController.text) ?? 0;
                        if (splitType == 'Custom') {
                          int filled = 0;
                          int sum = 0;
                          String? lastFilled;
                          for (var m in selectedMembers) {
                            final val = customControllers[m]?.text ?? '';
                            if (val.isNotEmpty) {
                              filled++;
                              lastFilled = m;
                            }
                          }
                          if (filled == 1) {
                            // Only one person has a value, auto-divide the rest
                            final filledName = lastFilled!;
                            final filledValue =
                                int.tryParse(
                                  customControllers[filledName]?.text ?? '0',
                                ) ??
                                0;
                            final rest = amt - filledValue;
                            final others = selectedMembers
                                .where((m) => m != filledName)
                                .toList();
                            if (others.isNotEmpty) {
                              final perOther = (rest / others.length)
                                  .toDouble();
                              for (var m in others) {
                                customControllers[m]?.text = perOther
                                    .toStringAsFixed(2);
                              }
                            }
                            sum = amt; // Now sum matches
                          } else {
                            for (var m in selectedMembers) {
                              sum +=
                                  int.tryParse(
                                    customControllers[m]?.text ?? '0',
                                  ) ??
                                  0;
                            }
                          }
                          if (sum != amt) {
                            setState(() {
                              customError =
                                  'Custom shares must sum to total amount (₹$amt)';
                            });
                            return;
                          } else {
                            setState(() {
                              customError = null;
                            });
                          }
                        }
                        setState(() {
                          _recentExpenses.insert(0, {
                            'title': descController.text.isEmpty
                                ? 'Expense'
                                : descController.text,
                            'subtitle':
                                'Split with ${selectedMembers.length > 1 ? 'Group' : selectedMembers[0]}',
                            'amount': -amt,
                            'color': AppTheme.blue,
                          });
                        });
                        _confettiController.play();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Expense added!')),
                        );
                      },
                      child: const Text('Save Expense'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSplitSummary(
    String amount,
    List<String> members,
    String splitType,
    Map<String, TextEditingController> customControllers,
  ) {
    final amt = int.tryParse(amount) ?? 0;
    final perPerson = splitType == 'Equally' && members.isNotEmpty
        ? (amt / members.length)
        : amt;
    List<double> shares = members
        .map(
          (m) => splitType == 'Equally'
              ? perPerson.toDouble()
              : double.tryParse(customControllers[m]?.text ?? '0') ?? 0.0,
        )
        .toList();
    return Card(
      color: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Split Summary',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: PieChart(
                PieChartData(
                  sections: [
                    for (int i = 0; i < members.length; i++)
                      PieChartSectionData(
                        value: shares[i],
                        color: Colors.primaries[i % Colors.primaries.length],
                        title: members[i],
                        radius: 40,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 24,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...members.map(
              (m) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(m),
                  Text(
                    splitType == 'Equally'
                        ? '₹${perPerson.toStringAsFixed(2)}'
                        : '₹${customControllers[m]?.text ?? '0'}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _addBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _addBtnController, curve: Curves.easeInOut),
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _addBtnController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  String _chartMode = 'Group';
  String _timeRange = 'This Month';
  int? _touchedIndex;
  final List<String> _chartModes = ['Group', 'Category'];
  final List<String> _timeRanges = ['This Month', 'All Time'];
  final Map<String, String> _expenseCategories = {
    'Dinner at Pizza Place': 'Food',
    'Cab to Airport': 'Travel',
    'Movie Night': 'Entertainment',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('SPENDY'),
        centerTitle: false,
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Animated Add Expense button (red)
                Center(
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: ElevatedButton.icon(
                      onPressed: _showAddExpenseSheet,
                      icon: const Icon(
                        Icons.add_circle_rounded,
                        color: AppTheme.yellow,
                        size: 32,
                      ),
                      label: const Text(
                        'Add Expense',
                        style: TextStyle(fontSize: 20),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.red,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 8,
                        shadowColor: AppTheme.red.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Chart controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ToggleButtons(
                      isSelected: _chartModes
                          .map((m) => m == _chartMode)
                          .toList(),
                      onPressed: (i) => setState(() {
                        _chartMode = _chartModes[i];
                        _touchedIndex = null;
                      }),
                      borderRadius: BorderRadius.circular(12),
                      selectedColor: AppTheme.textPrimary,
                      fillColor: AppTheme.yellow.withOpacity(0.18),
                      children: _chartModes
                          .map(
                            (m) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(m),
                            ),
                          )
                          .toList(),
                    ),
                    DropdownButton<String>(
                      value: _timeRange,
                      items: _timeRanges
                          .map(
                            (r) => DropdownMenuItem(value: r, child: Text(r)),
                          )
                          .toList(),
                      onChanged: (r) => setState(() {
                        _timeRange = r!;
                        _touchedIndex = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Expense chart
                Card(
                  color: AppTheme.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expense Breakdown',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: PieChart(
                            PieChartData(
                              sections: _buildHomeExpenseChartSections(),
                              sectionsSpace: 2,
                              centerSpaceRadius: 32,
                              pieTouchData: PieTouchData(
                                touchCallback: (event, response) {
                                  setState(() {
                                    _touchedIndex = response
                                        ?.touchedSection
                                        ?.touchedSectionIndex;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: _buildHomeExpenseChartLegend(),
                        ),
                        if (_touchedIndex != null &&
                            _touchedIndex! < _getChartGroups().length)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _getChartDetailText(_touchedIndex!),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.yellow,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Recent activity placeholder
                const Text(
                  'Recent Activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: _recentExpenses.length,
                    itemBuilder: (context, i) {
                      final exp = _recentExpenses[i];
                      return ListTile(
                        leading: Icon(
                          Icons.receipt_long_rounded,
                          color: exp['color'] as Color,
                        ),
                        title: Text(exp['title'] as String),
                        subtitle: Text(exp['subtitle'] as String),
                        trailing: Text(
                          '-₹${exp['amount']}',
                          style: TextStyle(
                            color: exp['color'] as Color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Confetti overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: [
                AppTheme.blue,
                AppTheme.red,
                AppTheme.yellow,
                AppTheme.green,
              ],
              numberOfParticles: 30,
              maxBlastForce: 20,
              minBlastForce: 8,
              emissionFrequency: 0.1,
              gravity: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getChartGroups() {
    // Filter by time range (mock: all for now, can add real date logic)
    final List<Map<String, dynamic>> filtered = _recentExpenses;
    final Map<String, double> groupTotals = {};
    final Map<String, Color> groupColors = {};
    for (var exp in filtered) {
      String group;
      if (_chartMode == 'Category') {
        group = _expenseCategories[exp['title']] ?? 'Other';
      } else {
        group = exp['subtitle'] as String;
      }
      final amt = (exp['amount'] as int).abs().toDouble();
      groupTotals[group] = (groupTotals[group] ?? 0) + amt;
      groupColors[group] = exp['color'] as Color;
    }
    return groupTotals.keys
        .map(
          (g) => {
            'label': g,
            'value': groupTotals[g]!,
            'color': groupColors[g]!,
          },
        )
        .toList();
  }

  List<PieChartSectionData> _buildHomeExpenseChartSections() {
    final groups = _getChartGroups();
    final total = groups.fold(0.0, (a, b) => a + (b['value'] as double));
    return List.generate(groups.length, (i) {
      final percent = total > 0 ? (groups[i]['value'] / total * 100) : 0.0;
      final percentStr = percent.toStringAsFixed(1);
      final isTouched = i == _touchedIndex;
      // Hide label for very small segments
      final showLabel = percent >= 5;
      return PieChartSectionData(
        value: groups[i]['value'],
        color: groups[i]['color'],
        title: showLabel
            ? '₹${groups[i]['value'].toStringAsFixed(0)}\n$percentStr%'
            : '',
        radius: isTouched ? 58 : 48,
        titleStyle: TextStyle(
          fontSize: isTouched ? 13 : 11,
          color: Colors.white,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
        titlePositionPercentageOffset: 0.45,
      );
    });
  }

  List<Widget> _buildHomeExpenseChartLegend() {
    final groups = _getChartGroups();
    return groups
        .map(
          (g) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: g['color'],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(g['label'], style: const TextStyle(fontSize: 13)),
            ],
          ),
        )
        .toList();
  }

  String _getChartDetailText(int index) {
    final groups = _getChartGroups();
    if (index < 0 || index >= groups.length) return '';
    final label = groups[index]['label'];
    final value = groups[index]['value'];
    return '$label: ₹${value.toStringAsFixed(0)}';
  }
}

class _GroupsTab extends StatefulWidget {
  const _GroupsTab();
  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  final List<Map<String, String>> _groups = [
    {'name': 'Trip Buddies', 'code': 'TRIP123'},
    {'name': 'Roommates', 'code': 'ROOM456'},
    {'name': 'Office Lunch', 'code': 'LUNCH789'},
  ];

  void _showCreateGroupDialog() {
    final TextEditingController nameController = TextEditingController();
    String? generatedCode;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Create Group',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Group Name'),
                  ),
                  const SizedBox(height: 16),
                  if (generatedCode != null) ...[
                    Text(
                      'Group Code: $generatedCode',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy, color: AppTheme.blue),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: generatedCode ?? ''),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Code copied!')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.email, color: AppTheme.green),
                          onPressed: () {
                            // Placeholder for email invite logic
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Email invite sent!'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      setState(() {
                        generatedCode = _generateGroupCode(nameController.text);
                      });
                      // Add group to list (in real app, save to backend)
                      this.setState(() {
                        _groups.add({
                          'name': nameController.text,
                          'code': generatedCode!,
                        });
                      });
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showJoinGroupDialog() {
    final TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Join Group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: codeController,
            decoration: const InputDecoration(labelText: 'Enter Group Code'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // In real app, validate code and join group
                setState(() {
                  _groups.add({
                    'name': 'New Group',
                    'code': codeController.text,
                  });
                });
                Navigator.pop(context);
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }

  String _generateGroupCode(String name) {
    return name.toUpperCase().replaceAll(' ', '').substring(0, 4) +
        (100 + _groups.length).toString();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      AppTheme.blue,
      AppTheme.red,
      AppTheme.yellow,
      AppTheme.green,
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Groups'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add, color: AppTheme.blue),
            onPressed: _showJoinGroupDialog,
            tooltip: 'Join Group',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGroupDialog,
        backgroundColor: AppTheme.green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Create Group'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _groups.length,
        itemBuilder: (context, i) {
          final group = _groups[i];
          return Card(
            color: AppTheme.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getAvatarColor(group['name']!),
                child: Text(
                  group['name']![0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                group['name']!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Code: ${group['code']}'),
              onTap: () {
                // Placeholder for group details navigation
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Group details coming soon!')),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab();
  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  final List<String> _groups = [
    'All',
    'Trip Buddies',
    'Roommates',
    'Office Lunch',
  ];
  final List<String> _users = [
    'All',
    'Alice',
    'Bob',
    'Charlie',
    'David',
    'Eve',
    'Frank',
    'Grace',
    'Heidi',
  ];
  String _selectedGroup = 'All';
  String _selectedUser = 'All';
  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allExpenses = [
    {
      'group': 'Trip Buddies',
      'title': 'Dinner at Pizza Place',
      'amount': -500,
      'status': 'owed',
      'date': '2024-07-21',
      'color': AppTheme.red,
      'payer': 'Alice',
      'participants': ['Alice', 'Bob', 'Charlie'],
    },
    {
      'group': 'Roommates',
      'title': 'Cab to Airport',
      'amount': -1200,
      'status': 'settled',
      'date': '2024-07-20',
      'color': AppTheme.yellow,
      'payer': 'David',
      'participants': ['David', 'Eve'],
    },
    {
      'group': 'Office Lunch',
      'title': 'Movie Night',
      'amount': -800,
      'status': 'owed',
      'date': '2024-07-19',
      'color': AppTheme.green,
      'payer': 'Frank',
      'participants': ['Frank', 'Grace', 'Heidi'],
    },
    {
      'group': 'Trip Buddies',
      'title': 'Hotel Booking',
      'amount': -3000,
      'status': 'settled',
      'date': '2024-07-18',
      'color': AppTheme.blue,
      'payer': 'Bob',
      'participants': ['Alice', 'Bob', 'Charlie'],
    },
  ];
  final Map<String, int> _summary = {'owe': 1700, 'owed': 1200, 'spent': 5500};
  final Map<int, List<String>> _reactions = {};
  final List<String> _emojiOptions = ['👍', '😂', '🔥', '🎉', '😎'];

  String _formatDate(String date) {
    final dt = DateTime.tryParse(date);
    if (dt == null) return date;
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
      return 'Yesterday';
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  void _showExpenseDetails(Map<String, dynamic> exp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: exp['color'],
                    child: Text(
                      exp['group'][0],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    exp['title'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const Spacer(),
                  _buildStatusBadge(exp['status']),
                ],
              ),
              const SizedBox(height: 16),
              Text('Group: ${exp['group']}'),
              Text('Date: ${exp['date']}'),
              Text('Paid by: ${exp['payer']}'),
              Text('Participants: ${exp['participants'].join(", ")}'),
              const SizedBox(height: 16),
              Text(
                'Amount: ₹${exp['amount']}',
                style: TextStyle(
                  color: exp['color'],
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 24),
              if (exp['status'] == 'owed')
                ElevatedButton.icon(
                  icon: const Icon(Icons.payment),
                  label: const Text('Settle Up'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.green,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showPaymentWindow(exp);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPaymentWindow(Map<String, dynamic> exp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Settle Up'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pay ₹${exp['amount'].abs()} to ${exp['payer']}'),
            const SizedBox(height: 16),
            const Text('Payment integration coming soon!'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('Mark as Settled'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.blue),
              onPressed: () {
                setState(() {
                  exp['status'] = 'settled';
                  // Update summary cards
                  final amt = exp['amount'].abs() as int;
                  _summary['owe'] = (_summary['owe'] ?? 0) - amt;
                  _summary['spent'] = (_summary['spent'] ?? 0) + amt;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as settled!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status == 'settled'
            ? AppTheme.green.withOpacity(0.15)
            : AppTheme.red.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status == 'settled' ? 'Settled' : 'Owed',
        style: TextStyle(
          color: status == 'settled' ? AppTheme.green : AppTheme.red,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filtered = _allExpenses.where((e) {
      final groupMatch =
          _selectedGroup == 'All' || e['group'] == _selectedGroup;
      final userMatch =
          _selectedUser == 'All' ||
          e['participants'].contains(_selectedUser) ||
          e['payer'] == _selectedUser;
      final searchMatch =
          _search.isEmpty ||
          e['title'].toLowerCase().contains(_search.toLowerCase());
      return groupMatch && userMatch && searchMatch;
    }).toList();
    // Group by date
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var exp in filtered) {
      final label = _formatDate(exp['date']);
      grouped.putIfAbsent(label, () => []).add(exp);
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Activity'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Summary cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryCard('You Owe', _summary['owe']!, AppTheme.red),
                _buildSummaryCard(
                  'You’re Owed',
                  _summary['owed']!,
                  AppTheme.green,
                ),
                _buildSummaryCard('Spent', _summary['spent']!, AppTheme.blue),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedGroup,
                    decoration: const InputDecoration(labelText: 'Group'),
                    items: _groups
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (g) => setState(() => _selectedGroup = g!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedUser,
                    decoration: const InputDecoration(labelText: 'User'),
                    items: _users
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (u) => setState(() => _selectedUser = u!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by description',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) => setState(() => _search = val),
            ),
            const SizedBox(height: 20),
            // Animated list with section headers
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No activity yet.'))
                  : ListView(
                      children: [
                        for (var date in grouped.keys)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  date,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              ...grouped[date]!.map(
                                (exp) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  child: Card(
                                    color: AppTheme.card,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: exp['color'],
                                        child: Text(
                                          exp['group'][0],
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Text(
                                            exp['title'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildStatusBadge(exp['status']),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${exp['group']} • ${exp['date']} • Paid by ${exp['payer']}',
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '₹${exp['amount']}',
                                            style: TextStyle(
                                              color: exp['color'],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            exp['status'] == 'settled'
                                                ? 'Settled'
                                                : 'Owed',
                                            style: TextStyle(
                                              color: exp['status'] == 'settled'
                                                  ? AppTheme.green
                                                  : AppTheme.red,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          // Emoji reactions
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: _emojiOptions
                                                .map(
                                                  (emoji) => GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        final idx = _allExpenses
                                                            .indexOf(exp);
                                                        _reactions.putIfAbsent(
                                                          idx,
                                                          () => [],
                                                        );
                                                        if (_reactions[idx]!
                                                            .contains(emoji)) {
                                                          _reactions[idx]!
                                                              .remove(emoji);
                                                        } else {
                                                          _reactions[idx]!.add(
                                                            emoji,
                                                          );
                                                        }
                                                      });
                                                    },
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 2,
                                                          ),
                                                      child: Text(
                                                        emoji,
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              _reactions[_allExpenses
                                                                          .indexOf(
                                                                            exp,
                                                                          )]
                                                                      ?.contains(
                                                                        emoji,
                                                                      ) ==
                                                                  true
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                          color:
                                                              _reactions[_allExpenses
                                                                          .indexOf(
                                                                            exp,
                                                                          )]
                                                                      ?.contains(
                                                                        emoji,
                                                                      ) ==
                                                                  true
                                                              ? AppTheme.yellow
                                                              : AppTheme
                                                                    .textSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _showExpenseDetails(exp),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, int value, Color color) {
    return Card(
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₹$value',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();
  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String _name = 'Ajay Tiwari';
  String _email = 'ajay@example.com';
  final TextEditingController _nameController = TextEditingController();
  final Map<String, int> _stats = {'spent': 5500, 'owe': 1700, 'settled': 1200};
  XFile? _profileImage;
  bool _notificationsEnabled = true;
  String _currency = '₹';
  final List<String> _currencies = ['₹', ' 24', '€', '£'];

  @override
  void initState() {
    super.initState();
    _nameController.text = _name;
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _profileImage = picked);
    }
  }

  void _showInviteFriends() {
    Share.share('Join me on SPENDY! Download the app and use my code: AJAY123');
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              value: _notificationsEnabled,
              onChanged: (val) => setState(() => _notificationsEnabled = val),
              title: const Text('Enable Notifications'),
            ),
            DropdownButtonFormField<String>(
              value: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: _currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (c) => setState(() => _currency = c!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHelpFeedback() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Help & Feedback'),
        content: const Text(
          'For help or to send feedback, email: support@spendy.com',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccount() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deletion coming soon!')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Name'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _name = _nameController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.yellow),
            onPressed: _showSettingsDialog,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.blue,
                  backgroundImage: _profileImage != null
                      ? FileImage(File(_profileImage!.path))
                      : null,
                  child: _profileImage == null
                      ? Text(
                          _name.isNotEmpty ? _name[0].toUpperCase() : 'A',
                          style: const TextStyle(
                            fontSize: 40,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickProfilePhoto,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.yellow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit,
                    size: 20,
                    color: AppTheme.yellow,
                  ),
                  onPressed: _showEditNameDialog,
                  tooltip: 'Edit Name',
                ),
              ],
            ),
            Text(_email, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard('Spent', _stats['spent']!, AppTheme.blue),
                _buildStatCard('Owe', _stats['owe']!, AppTheme.red),
                _buildStatCard('Settled', _stats['settled']!, AppTheme.green),
              ],
            ),
            const SizedBox(height: 32),
            Card(
              color: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.person_add, color: AppTheme.green),
                title: const Text('Invite Friends'),
                onTap: _showInviteFriends,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.help_outline, color: AppTheme.blue),
                title: const Text('Help & Feedback'),
                onTap: _showHelpFeedback,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout, color: AppTheme.red),
                title: const Text('Logout'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logout coming soon!')),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: AppTheme.red),
                title: const Text('Delete Account'),
                onTap: _showDeleteAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int value, Color color) {
    return Card(
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₹$value',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
