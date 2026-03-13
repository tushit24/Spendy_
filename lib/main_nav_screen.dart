import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart'; // Added for FirebaseAuth

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/group_service.dart'; // Added for GroupService
import 'services/storage_service.dart';
import 'models/group_model.dart';
import 'models/expense_model.dart';
import 'models/user_model.dart';
import 'services/notification_service.dart';
import 'utils/debt_simplification.dart';
import 'screens/group_details_screen.dart';

String getCurrencySymbol(String currencyCode) {
  switch (currencyCode) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'INR':
    default:
      return '₹';
  }
}

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController; // Added TabController
  String _selectedGroupId = 'All'; // Lifted from _ActivityTabState

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = AuthService.instance.currentUser;
    return StreamBuilder<AppUser?>(
      stream: authUser != null
          ? FirestoreService.instance.streamUser(authUser.uid)
          : const Stream.empty(),
      builder: (context, userSnap) {
        final currentUser = userSnap.data;
        return Scaffold(
          body: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              const _HomeTab(),
              _buildGroupsTab(),
              _ActivityTab(
                selectedGroupId: _selectedGroupId,
                currentUser:
                    currentUser ??
                    AppUser(
                      uid: authUser?.uid ?? '',
                      name: '',
                      email: '',
                      currency: 'INR',
                      createdAt: DateTime.now(),
                    ),
              ),
              _ProfileTab(
                currentUser:
                    currentUser ??
                    AppUser(
                      uid: authUser?.uid ?? '',
                      name: '',
                      email: '',
                      currency: 'INR',
                      createdAt: DateTime.now(),
                    ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            backgroundColor: AppTheme.card,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppTheme.yellow,
            unselectedItemColor: AppTheme.textSecondary,
            showUnselectedLabels: true,
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
                _tabController.animateTo(index);
              });
            },
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
      },
    );
  }

  // --- GROUPS TAB ---

  void _showCreateGroupDialog() {
    final _nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Group'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g. Goa Trip, Roommates',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                try {
                  Navigator.pop(context); // Close dialog first
                  await GroupService().createGroup(name);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Group created successfully!'),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinGroupDialog() {
    final _codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Group'),
        content: TextField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Group Code',
            hintText: 'Enter 6-character code',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = _codeController.text.trim().toUpperCase();
              if (code.length == 6) {
                try {
                  Navigator.pop(context);
                  final groupName = await GroupService().joinGroup(code);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Joined $groupName successfully!')),
                  );

                  // Mock Notification
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '🔔 You joined a new group! (FCM Placeholder)',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid code length')),
                );
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveGroup(String groupId, String groupName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave $groupName?'),
        content: const Text(
          'Are you sure you want to leave this group? You won\'t see its expenses anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await GroupService().leaveGroup(groupId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Left group successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to see groups'));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join_group',
            onPressed: _showJoinGroupDialog,
            label: const Text('Join Group'),
            icon: const Icon(Icons.group_add),
            backgroundColor: AppTheme.blue, // Changed to AppTheme.blue
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'create_group',
            onPressed: _showCreateGroupDialog,
            label: const Text('Create Group'),
            icon: const Icon(Icons.add),
            backgroundColor: AppTheme.green, // Changed to AppTheme.green
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<Group>>(
          stream: GroupService().getUserGroups(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final groups = snapshot.data ?? [];

            if (groups.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_off, size: 64, color: Colors.grey[600]),
                    const SizedBox(height: 16),
                    Text(
                      'No groups yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create or join a group to get started!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final isAdmin =
                    group.ownerId == FirebaseAuth.instance.currentUser!.uid;

                return Card(
                  color: AppTheme.card, // Changed to AppTheme.card
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailsScreen(groupId: group.id),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme
                                        .textPrimary, // Changed to AppTheme.textPrimary
                                  ),
                                ),
                              ),
                              if (isAdmin)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.blue.withOpacity(
                                      0.2,
                                    ), // Changed to AppTheme.blue
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ADMIN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme
                                          .blue, // Changed to AppTheme.blue
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.people,
                                size: 16,
                                color: AppTheme.textSecondary,
                              ), // Changed to AppTheme.textSecondary
                              const SizedBox(width: 4),
                              Text(
                                '${group.members.length} Members',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                ), // Changed to AppTheme.textSecondary
                              ),
                              const Spacer(),
                              Text(
                                'Code: ${group.code}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  color: AppTheme
                                      .yellow, // Changed to AppTheme.yellow
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.share,
                                  size: 16,
                                  color: AppTheme.textSecondary,
                                ), // Changed to AppTheme.textSecondary
                                onPressed: () {
                                  Share.share(
                                    'Join my SPENDY group!\nGroup: ${group.name}\nCode: ${group.code}',
                                  );
                                },
                                tooltip: 'Share Code',
                              ),
                            ],
                          ),
                          const Divider(
                            color: AppTheme.textSecondary,
                          ), // Changed to AppTheme.textSecondary
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Share.share(
                                    'Join my SPENDY group "${group.name}" using code: ${group.code}',
                                  );
                                },
                                icon: const Icon(
                                  Icons.share,
                                  size: 18,
                                  color: AppTheme.blue,
                                ), // Changed to AppTheme.blue
                                label: const Text(
                                  'Share',
                                  style: TextStyle(color: AppTheme.blue),
                                ), // Changed to AppTheme.blue
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    _confirmLeaveGroup(group.id, group.name),
                                icon: const Icon(
                                  Icons.exit_to_app,
                                  size: 18,
                                  color: AppTheme.red,
                                ), // Changed to AppTheme.red
                                label: const Text(
                                  'Leave',
                                  style: TextStyle(
                                    color: AppTheme.red,
                                  ), // Changed to AppTheme.red
                                ),
                              ),
                              if (isAdmin) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: AppTheme.red,
                                  ), // Changed to AppTheme.red
                                  onPressed: () =>
                                      _confirmDeleteGroup(group.id, group.name),
                                  tooltip: 'Delete Group',
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _confirmDeleteGroup(String groupId, String groupName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $groupName?'),
        content: const Text(
          'Cannot be undone. All members will be removed and expenses deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await GroupService().deleteGroup(groupId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Group deleted successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}

// Home Tab with real Firestore data
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

  String _chartMode = 'Group';
  String _timeRange = 'This Month';
  int? _touchedIndex;
  final List<String> _chartModes = ['Group', 'Category'];
  final List<String> _timeRanges = ['This Month', 'All Time', 'Reset Counter'];
  DateTime? _resetDate;
  String _currencyCode = 'INR';

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
    _loadResetDate();
    // Listen to user stream for currency changes
    final authUser = AuthService.instance.currentUser;
    if (authUser != null) {
      FirestoreService.instance.streamUser(authUser.uid).listen((u) {
        if (mounted) setState(() => _currencyCode = u?.currency ?? 'INR');
      });
    }
  }

  @override
  void dispose() {
    _addBtnController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _showAddExpenseSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return FutureBuilder<AppUser?>(
          future: AuthService.instance.currentUser != null
              ? FirestoreService.instance.getUser(
                  AuthService.instance.currentUser!.uid,
                )
              : Future.value(null),
          builder: (context, appUserSnap) {
            return _AddExpenseSheet(
              confettiController: _confettiController,
              currentUser:
                  appUserSnap.data ??
                  AppUser(
                    uid: AuthService.instance.currentUser?.uid ?? '',
                    name: '',
                    email: '',
                    currency: 'INR',
                    createdAt: DateTime.now(),
                  ),
            );
          },
        );
      },
    );
  }

  /// Loads the user's resetDate from Firestore and stores it locally.
  Future<void> _loadResetDate() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final date = await FirestoreService.instance.getResetDate(uid);
    if (mounted) setState(() => _resetDate = date);
  }

  /// Returns the DateTime to use as the query start date based on the current
  /// filter selection. Returns null for All Time (no filter).
  DateTime? _getFilterStartDate() {
    switch (_timeRange) {
      case 'This Month':
        final now = DateTime.now();
        return DateTime(now.year, now.month, 1);
      case 'Reset Counter':
        return _resetDate; // may be null if never reset
      default: // All Time
        return null;
    }
  }

  /// Shows the reset confirmation dialog, then saves a new resetDate.
  Future<void> _showResetConfirmation() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Reset Counter?'),
        content: const Text(
          'Start tracking Total Spent from today?\n\nAll previous expenses will be excluded from the counter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService.instance.updateResetDate(uid);
      await _loadResetDate();
      if (mounted) {
        setState(() => _timeRange = 'Reset Counter');
      }
    } else {
      // Revert dropdown to previous selection if user cancels
      if (mounted) setState(() => _timeRange = 'This Month');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) return const SizedBox();
    // Fetch currency from AppUser stream
    final currencyCode = _currencyCode;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('SPENDY'),
        centerTitle: false,
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: StreamBuilder<List<Expense>>(
        stream: FirestoreService.instance.streamUserExpensesFiltered(
          user.uid,
          since: _getFilterStartDate(),
        ),
        builder: (context, snapshot) {
          final expenses = snapshot.data ?? [];
          return Stack(
            children: [
              SingleChildScrollView(
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
                            shadowColor: AppTheme.red.withValues(alpha: 0.3),
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
                          fillColor: AppTheme.yellow.withValues(alpha: 0.18),
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
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Expense chart
                    if (expenses.isNotEmpty)
                      _buildChartCard(expenses)
                    else
                      const Card(
                        color: AppTheme.card,
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text("No expenses yet")),
                        ),
                      ),
                    const SizedBox(height: 32),
                    // Recent activity
                    const Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (expenses.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text("No recent activity"),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: expenses.length,
                        itemBuilder: (context, i) {
                          final exp = expenses[i];
                          return ListTile(
                            leading: const Icon(
                              Icons.receipt_long_rounded,
                              color: AppTheme.blue,
                            ),
                            title: Text(exp.title),
                            subtitle: Text(
                              '${exp.splitType} • ${getCurrencySymbol(currencyCode)}${(exp.shares[user.uid] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}',
                            ),
                            trailing: Text(
                              '${getCurrencySymbol(currencyCode)}${(exp.shares[user.uid] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}',
                              style: const TextStyle(
                                color: AppTheme.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
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
                  colors: const [
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
          );
        },
      ),
    );
  }

  Widget _buildChartCard(List<Expense> expenses) {
    final authUid = AuthService.instance.currentUser?.uid ?? '';
    final currencyCode = _currencyCode;
    return Card(
      color: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Spent',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${getCurrencySymbol(currencyCode)}${expenses.fold(0.0, (a, b) => a + (b.shares[authUid] ?? 0)).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.yellow.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _timeRange == 'Reset Counter' && _resetDate == null
                          ? 'This Month'
                          : _timeRange,
                      icon: const Icon(
                        Icons.pie_chart_rounded,
                        color: AppTheme.yellow,
                      ),
                      iconSize: 24,
                      dropdownColor: AppTheme.card,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                      items: _timeRanges
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        if (value == 'Reset Counter') {
                          _showResetConfirmation();
                        } else {
                          setState(() => _timeRange = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: _buildHomeExpenseChartSections(expenses, authUid),
                  sectionsSpace: 2,
                  centerSpaceRadius: 32,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        _touchedIndex =
                            response?.touchedSection?.touchedSectionIndex;
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: _buildHomeExpenseChartLegend(expenses, authUid),
            ),
            if (_touchedIndex != null && _touchedIndex! >= 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _getChartDetailText(_touchedIndex!, expenses, null),
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
    );
  }

  List<Map<String, dynamic>> _getChartGroups(
    List<Expense> expenses,
    String uid,
  ) {
    final Map<String, double> groupTotals = {};
    for (var exp in expenses) {
      final myShare = exp.shares[uid] ?? 0.0;
      if (myShare <= 0) continue;

      String group;
      if (_chartMode == 'Category') {
        final title = exp.title.toLowerCase();
        if (title.contains('food') ||
            title.contains('dinner') ||
            title.contains('lunch') ||
            title.contains('pizza') ||
            title.contains('burger'))
          group = 'Food';
        else if (title.contains('cab') ||
            title.contains('uber') ||
            title.contains('travel') ||
            title.contains('bus') ||
            title.contains('flight'))
          group = 'Travel';
        else if (title.contains('movie') ||
            title.contains('entertainment') ||
            title.contains('game'))
          group = 'Entertainment';
        else
          group = 'Other';
      } else {
        group = exp.splitType;
      }
      groupTotals[group] = (groupTotals[group] ?? 0) + myShare;
    }

    final keys = groupTotals.keys.toList();
    return keys.asMap().entries.map((e) {
      final i = e.key;
      final k = e.value;
      final colors = [
        AppTheme.blue,
        AppTheme.red,
        AppTheme.green,
        AppTheme.yellow,
        Colors.purple,
      ];
      return {
        'label': k,
        'value': groupTotals[k]!,
        'color': colors[i % colors.length],
      };
    }).toList();
  }

  List<PieChartSectionData> _buildHomeExpenseChartSections(
    List<Expense> expenses,
    String uid,
  ) {
    final groups = _getChartGroups(expenses, uid);
    final total = groups.fold(0.0, (a, b) => a + (b['value'] as double));
    return List.generate(groups.length, (i) {
      final val = groups[i]['value'] as double;
      final percent = total > 0 ? (val / total * 100) : 0.0;
      final showLabel = percent >= 5;
      final isTouched = i == _touchedIndex;
      return PieChartSectionData(
        value: val,
        color: groups[i]['color'],
        title: showLabel
            ? '₹${val.toStringAsFixed(0)}\n${percent.toStringAsFixed(1)}%'
            : '',
        radius: isTouched ? 58 : 48,
        titleStyle: TextStyle(
          fontSize: isTouched ? 13 : 11,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      );
    });
  }

  List<Widget> _buildHomeExpenseChartLegend(
    List<Expense> expenses,
    String uid,
  ) {
    final groups = _getChartGroups(expenses, uid);
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

  String _getChartDetailText(int index, List<Expense> expenses, AppUser? user) {
    final groups = _getChartGroups(expenses, user?.uid ?? '');
    if (index < 0 || index >= groups.length) return '';
    final val = groups[index]['value'] as double;
    final total = groups.fold<double>(0, (p, e) => p + (e['value'] as double));
    final percent = total > 0 ? (val / total * 100) : 0;
    return '${groups[index]['label']}: ${getCurrencySymbol(user?.currency ?? 'INR')}${val.toStringAsFixed(0)}\n${percent.toStringAsFixed(1)}%';
  }
}

class _AddExpenseSheet extends StatefulWidget {
  final ConfettiController confettiController;
  final AppUser currentUser;
  const _AddExpenseSheet({
    required this.confettiController,
    required this.currentUser,
  });

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController descController = TextEditingController();
  Map<String, TextEditingController> customControllers = {};

  String splitType = 'Equally';
  Group? selectedGroup;
  List<AppUser> groupMembers = [];
  List<String> selectedMemberIds = [];
  bool isLoadingMembers = false;
  bool _isSaving = false;
  String? customError;

  @override
  void dispose() {
    amountController.dispose();
    descController.dispose();
    for (var c in customControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _fetchMembers(Group group) async {
    setState(() => isLoadingMembers = true);
    // Use GroupService to fetch members from root users collection
    final users = await GroupService().loadGroupMembers(group.id);
    if (mounted) {
      setState(() {
        groupMembers = users;
        selectedMemberIds = users.map((u) => u.uid).toList();

        customControllers.clear();
        if (splitType == 'Custom') {
          for (var m in users) {
            customControllers[m.uid] = TextEditingController();
          }
        }
        isLoadingMembers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: StreamBuilder<List<Group>>(
            stream: GroupService().getUserGroups(),
            builder: (context, snapshot) {
              final groups = snapshot.data ?? [];

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (groups.isEmpty) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    const Text("You need to join or create a group first."),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              }

              if (selectedGroup == null && groups.isNotEmpty) {
                // Defer state update
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && selectedGroup == null) {
                    setState(() {
                      selectedGroup = groups.first;
                    });
                    _fetchMembers(groups.first);
                  }
                });
                // Show loading while we select
                return const Center(child: CircularProgressIndicator());
              }

              return Column(
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
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            value: selectedGroup?.id,
                            decoration: const InputDecoration(
                              labelText: 'Group',
                            ),
                            items: groups
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g.id,
                                    child: Text(g.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (gid) {
                              final g = groups.firstWhere((e) => e.id == gid);
                              setState(() {
                                selectedGroup = g;
                              });
                              _fetchMembers(g);
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              prefixText:
                                  '${getCurrencySymbol(widget.currentUser.currency)} ',
                              labelText: 'Amount',
                              prefixIcon: const Icon(Icons.attach_money),
                            ),
                            onChanged: (_) => setState(() {}),
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
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: (s) => setState(() {
                              splitType = s!;
                              if (splitType == 'Custom') {
                                for (var m in groupMembers) {
                                  if (selectedMemberIds.contains(m.uid)) {
                                    customControllers.putIfAbsent(
                                      m.uid,
                                      () => TextEditingController(),
                                    );
                                  }
                                }
                              }
                            }),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Participants',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (isLoadingMembers)
                            const Center(child: CircularProgressIndicator())
                          else
                            Wrap(
                              spacing: 8,
                              children: groupMembers.map((m) {
                                final selected = selectedMemberIds.contains(
                                  m.uid,
                                );
                                return FilterChip(
                                  label: Text(m.name.isEmpty ? '?' : m.name),
                                  selected: selected,
                                  onSelected: (val) {
                                    setState(() {
                                      if (val) {
                                        selectedMemberIds.add(m.uid);
                                        if (splitType == 'Custom') {
                                          customControllers.putIfAbsent(
                                            m.uid,
                                            () => TextEditingController(),
                                          );
                                        }
                                      } else {
                                        selectedMemberIds.remove(m.uid);
                                        customControllers.remove(m.uid);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),

                          if (splitType == 'Custom' &&
                              amountController.text.isNotEmpty &&
                              selectedMemberIds.isNotEmpty)
                            _buildCustomSplitInputs(),

                          const SizedBox(height: 20),
                          if (amountController.text.isNotEmpty &&
                              selectedMemberIds.isNotEmpty)
                            _buildSplitSummary(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _submitExpense,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save Expense'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCustomSplitInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text('Enter each participant share:'),
        ...groupMembers.where((m) => selectedMemberIds.contains(m.uid)).map((
          m,
        ) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TextField(
              controller: customControllers[m.uid],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: m.name,
                prefixText:
                    '${getCurrencySymbol(widget.currentUser.currency)} ',
              ),
            ),
          );
        }),
        if (customError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              customError!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }

  Widget _buildSplitSummary() {
    final amt = double.tryParse(amountController.text) ?? 0;
    final perPerson = (splitType == 'Equally' && selectedMemberIds.isNotEmpty)
        ? (amt / selectedMemberIds.length)
        : amt;

    // Map of name -> share
    final List<Map<String, dynamic>> shares = [];
    for (var m in groupMembers) {
      if (!selectedMemberIds.contains(m.uid)) continue;
      double val = 0;
      if (splitType == 'Equally') {
        val = perPerson;
      } else {
        val = double.tryParse(customControllers[m.uid]?.text ?? '0') ?? 0;
      }
      shares.add({
        'name': m.name,
        'value': val,
        'color': Colors.blue,
      }); // color placeholder
    }

    return Card(
      color: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Split Summary',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (shares.isNotEmpty)
              SizedBox(
                height: 120,
                child: PieChart(
                  PieChartData(
                    sections: [
                      for (int i = 0; i < shares.length; i++)
                        PieChartSectionData(
                          value: shares[i]['value'],
                          color: Colors.primaries[i % Colors.primaries.length],
                          title: shares[i]['name'],
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
            ...shares.map(
              (s) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s['name']),
                  Text(
                    '${getCurrencySymbol(widget.currentUser.currency)}${(s['value'] as double).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitExpense() async {
    if (_isSaving) return;
    if (selectedGroup == null) return;
    if (amountController.text.isEmpty || selectedMemberIds.isEmpty) return;

    final amount = double.tryParse(amountController.text) ?? 0;
    Map<String, double> shares = {};

    if (splitType == 'Equally') {
      final share = amount / selectedMemberIds.length;
      for (var uid in selectedMemberIds) shares[uid] = share;
    } else {
      double sum = 0;
      for (var uid in selectedMemberIds) {
        final val = double.tryParse(customControllers[uid]?.text ?? '0') ?? 0;
        shares[uid] = val;
        sum += val;
      }
      if ((sum - amount).abs() > 0.1) {
        setState(
          () => customError =
              'Total must be ${getCurrencySymbol(widget.currentUser.currency)}$amount (Current: ${getCurrencySymbol(widget.currentUser.currency)}$sum)',
        );
        return;
      } else {
        setState(() => customError = null);
      }
    }

    final currentUser = AuthService.instance.currentUser!;

    final expense = Expense(
      id: '', // Firestore generates this if we use doc().set() with custom ID or .add()
      // Wait, firestore_service.dart addExpense uses doc().set() on new doc ref.
      groupId: selectedGroup!.id,
      title: descController.text.isEmpty ? 'Expense' : descController.text,
      amount: amount,
      payerId: currentUser.uid,
      participants: selectedMemberIds,
      splitType: splitType,
      shares: shares,
      createdAt: DateTime.now(),
      status: 'owed',
    );

    setState(() => _isSaving = true);
    try {
      await FirestoreService.instance.addExpense(expense);
      if (mounted) {
        widget.confettiController.play();
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Expense added!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save expense: $e')));
      }
    }
  }
}

class _ActivityTab extends StatefulWidget {
  final String selectedGroupId;
  final AppUser currentUser; // Added currentUser
  const _ActivityTab({this.selectedGroupId = 'All', required this.currentUser});

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  late String _selectedGroupId;
  String _selectedUserId = 'All';

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.selectedGroupId;
  }

  @override
  void didUpdateWidget(_ActivityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedGroupId != widget.selectedGroupId) {
      _selectedGroupId = widget.selectedGroupId;
    }
  }

  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  final List<String> _emojiOptions = ['👍', '😂', '🔥', '🎉', '😎'];

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
      return 'Yesterday';
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  void _showExpenseDetails(Expense exp, String groupName, String groupOwnerId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _ExpenseDetailsSheet(
          expense: exp,
          currentUser: widget.currentUser,
          groupName: groupName,
          groupOwnerId: groupOwnerId,
        );
      },
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

  void _showSimplificationModal(
    List<DebtMatch> suggestions,
    String currencyCode,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: AppTheme.card,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Debt Simplification',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Optimized settlement suggestions for the selected group:',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (suggestions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('All debts are settled!')),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final suggestion = suggestions[index];
                    return FutureBuilder<List<AppUser>>(
                      future: FirestoreService.instance.getUsers([
                        suggestion.from,
                        suggestion.to,
                      ]),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final users = snapshot.data!;
                        final fromUser = users.firstWhere(
                          (u) => u.uid == suggestion.from,
                          orElse: () => AppUser(
                            uid: suggestion.from,
                            email: '',
                            name: 'Unknown',
                            currency: 'INR',
                            createdAt: DateTime.now(),
                          ),
                        );
                        final toUser = users.firstWhere(
                          (u) => u.uid == suggestion.to,
                          orElse: () => AppUser(
                            uid: suggestion.to,
                            email: '',
                            name: 'Unknown',
                            currency: 'INR',
                            createdAt: DateTime.now(),
                          ),
                        );

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.blue.withOpacity(0.1),
                            child: const Icon(
                              Icons.payment,
                              color: AppTheme.blue,
                            ),
                          ),
                          title: Text(
                            '${fromUser.name} suggests to pay ${toUser.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing: Text(
                            '${getCurrencySymbol(currencyCode)}${suggestion.amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppTheme.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser; // Changed to widget.currentUser
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Activity'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: StreamBuilder<List<Group>>(
        stream: GroupService().getUserGroups(),
        builder: (context, groupSnapshot) {
          final groups = groupSnapshot.data ?? [];
          final allGroups = [
            Group(
              id: 'All',
              name: 'All',
              code: '',
              ownerId: '',
              createdAt: DateTime(0),
            ),
            ...groups,
          ];

          // Validate selected group
          if (!allGroups.any((g) => g.id == _selectedGroupId)) {
            _selectedGroupId = 'All';
          }

          return StreamBuilder<List<Expense>>(
            stream: FirestoreService.instance.streamFilteredExpenses(
              uid: user.uid,
              groupId: _selectedGroupId == 'All' ? null : _selectedGroupId,
              userFilterUid: _selectedUserId == 'All' ? null : _selectedUserId,
            ),
            builder: (context, expenseSnapshot) {
              final expenses = expenseSnapshot.data ?? [];

              // Local filtering for search and 'users' if not handled by stream fully
              final filtered = expenses.where((e) {
                final searchMatch =
                    _search.isEmpty ||
                    e.title.toLowerCase().contains(_search.toLowerCase());
                // userFilterUid in stream handles participation, but we might want precise payer filtering or such.
                // For now, streamFilteredExpenses logic:
                // if userFilterUid provided, it checks if that user is participant.
                return searchMatch;
              }).toList();

              // Calculate Summary
              double owe = 0;
              double owed = 0;
              double spent = 0;

              for (var e in filtered) {
                final myShare = e.shares[user.uid] ?? 0;

                // My absolute personal "spent" is whatever my share was, regardless of who fronted the cash.
                spent += myShare;

                if (e.payerId == user.uid) {
                  // I paid. Others owe me for the parts I covered for them.
                  if (e.status == 'owed') {
                    owed += (e.amount - myShare);
                  }
                } else {
                  // Someone else paid for me. I owe them my share.
                  if (e.status == 'owed') {
                    owe += myShare;
                  }
                }
              }

              // Group expenses by date
              final grouped = <String, List<Expense>>{};
              for (var exp in filtered) {
                final dateKey = _formatDate(exp.createdAt);
                grouped.putIfAbsent(dateKey, () => []).add(exp);
              }

              // Extract unique participants for User Filter
              // This is a bit heavy, but fine for small data
              final Set<String> participantIds = filtered
                  .expand((e) => e.participants)
                  .toSet();

              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Summary cards
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSummaryCard('You Owe', owe.toInt(), AppTheme.red),
                        _buildSummaryCard(
                          'You’re Owed',
                          owed.toInt(),
                          AppTheme.green,
                        ),
                        _buildSummaryCard(
                          'Spent',
                          spent.toInt(),
                          AppTheme.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_selectedGroupId != 'All')
                      ElevatedButton.icon(
                        onPressed: () {
                          final suggestions = DebtSimplifier.simplifyDebts(
                            filtered,
                          );
                          _showSimplificationModal(
                            suggestions,
                            widget.currentUser.currency,
                          );
                        },
                        icon: const Icon(Icons.auto_graph),
                        label: const Text('Simplify Debts'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedGroupId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Group',
                            ),
                            items: allGroups
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g.id,
                                    child: Text(
                                      g.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (g) =>
                                setState(() => _selectedGroupId = g!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // User Dropdown - populating from actual users would need fetching names.
                        // For simplicity, we'll keep it simple or just show IDs if we don't have mapping yet.
                        // Ideally we use a FutureBuilder to fetch names for participantIds.
                        Expanded(
                          child: FutureBuilder<List<AppUser>>(
                            future: FirestoreService.instance.getUsers(
                              participantIds.toList(),
                            ),
                            builder: (context, userSnap) {
                              final users = userSnap.data ?? [];
                              final items = [
                                const DropdownMenuItem(
                                  value: 'All',
                                  child: Text('All'),
                                ),
                                ...users.map(
                                  (u) => DropdownMenuItem(
                                    value: u.uid,
                                    child: Text(u.name),
                                  ),
                                ),
                              ];
                              // Ensure selected is valid
                              if (_selectedUserId != 'All' &&
                                  !users.any((u) => u.uid == _selectedUserId)) {
                                // If specific user not in list, maybe keep it or reset? Resetting is safer.
                                // But strictly, FutureBuilder rebuilds might cause valid selection to be momentarily invalid.
                                // We'll trust the logic.
                              }

                              return DropdownButtonFormField<String>(
                                value:
                                    items.any((i) => i.value == _selectedUserId)
                                    ? _selectedUserId
                                    : 'All',
                                decoration: const InputDecoration(
                                  labelText: 'User',
                                ),
                                items: items,
                                onChanged: (u) =>
                                    setState(() => _selectedUserId = u!),
                              );
                            },
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
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No activity yet.'))
                          : ListView(
                              children: [
                                for (var date in grouped.keys)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        (exp) =>
                                            _buildExpenseCard(exp, user.uid, allGroups),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildExpenseCard(Expense exp, String currentUserUid, List<Group> allGroups) {
    final groupName = allGroups.firstWhere(
      (g) => g.id == exp.groupId,
      orElse: () => Group(id: '', name: 'Unknown', code: '', ownerId: '', createdAt: DateTime(0)),
    ).name;

    final color =
        Colors.primaries[exp.groupId.hashCode % Colors.primaries.length];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Card(
        color: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: FutureBuilder<AppUser?>(
          future: FirestoreService.instance.getUser(exp.payerId),
          builder: (context, snapshot) {
            final payerName = snapshot.data?.uid == currentUserUid ? 'You' : (snapshot.data?.name ?? 'Unknown');

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: color,
                child: const Icon(Icons.attach_money, color: Colors.white),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      exp.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(exp.status),
                ],
              ),
              subtitle: Text(
                '$groupName • Paid by $payerName',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${getCurrencySymbol(widget.currentUser.currency)}${(exp.shares[currentUserUid] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  // Reactions
                  SizedBox(
                    height: 24,
                    child: StreamBuilder<String?>(
                      stream: FirestoreService.instance.streamUserReaction(
                        groupId: exp.groupId!,
                        expenseId: exp.id,
                        uid: currentUserUid,
                      ),
                      builder: (context, snap) {
                        final myReaction = snap.data;
                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          itemCount: _emojiOptions.length,
                          itemBuilder: (context, index) {
                            final emoji = _emojiOptions[index];
                            final isSelected = myReaction == emoji;
                            return GestureDetector(
                              onTap: () {
                                FirestoreService.instance.toggleReaction(
                                  groupId: exp.groupId!,
                                  expenseId: exp.id,
                                  emoji: emoji,
                                  uid: currentUserUid,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  emoji,
                                  style: TextStyle(
                                    fontSize: isSelected ? 18 : 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppTheme.yellow
                                        : AppTheme.textSecondary.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              onTap: () {
                final group = allGroups.firstWhere(
                  (g) => g.id == exp.groupId,
                  orElse: () => Group(id: '', name: 'Unknown', code: '', ownerId: '', createdAt: DateTime(0)),
                );
                _showExpenseDetails(exp, groupName, group.ownerId);
              },
            );
          },
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
              '${getCurrencySymbol(widget.currentUser.currency)}$value',
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

class _ExpenseDetailsSheet extends StatelessWidget {
  final Expense expense;
  final AppUser currentUser;
  final String groupName;
  final String groupOwnerId;

  const _ExpenseDetailsSheet({
    required this.expense,
    required this.currentUser,
    required this.groupName,
    required this.groupOwnerId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppUser>>(
      future: FirestoreService.instance.getUsers(
        {...expense.participants, expense.payerId}.toList(),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!;
        final payer = users.firstWhere(
          (u) => u.uid == expense.payerId,
          orElse: () => AppUser(
            uid: '',
            email: '',
            name: 'Unknown',
            createdAt: DateTime.now(),
          ),
        );

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            expense.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              color: AppTheme.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$groupName • Paid by ${payer.uid == currentUser.uid ? 'You' : payer.name}',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Total Amount: ${getCurrencySymbol(currentUser.currency)}${expense.amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: AppTheme.yellow,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          const Text('Participants & Shares', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          ...expense.participants.map((uid) {
                            final u = users.firstWhere(
                              (user) => user.uid == uid,
                              orElse: () => AppUser(uid: '', email: '', name: 'Unknown', createdAt: DateTime.now()),
                            );
                            final share = expense.shares[uid] ?? 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(u.uid == currentUser.uid ? 'You' : u.name, style: const TextStyle(fontSize: 16)),
                                  Text(
                                    '${getCurrencySymbol(currentUser.currency)}${share.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // RULE 1: Settle Up — only if current user owes money
                  if (currentUser.uid != expense.payerId &&
                      ((expense.shares[currentUser.uid] as num?)?.toDouble() ?? 0) > 0)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.payment),
                        label: Text(
                            'Settle Up ${getCurrencySymbol(currentUser.currency)}${((expense.shares[currentUser.uid] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _showSimpleSettle(context, expense);
                        },
                      ),
                    ),
                  // RULE 2: Edit — only if current user is the payer
                  if (expense.payerId == currentUser.uid)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Edit coming soon')));
                            Navigator.pop(context);
                          },
                          child: const Text('Edit'),
                        ),
                      ),
                    ),
                  // RULE 3: Delete — only if payer or group owner
                  if (expense.payerId == currentUser.uid ||
                      currentUser.uid == groupOwnerId)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton(
                        onPressed: () async {
                          await FirestoreService.instance
                              .deleteExpense(expense.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                            foregroundColor: AppTheme.red),
                        child: const Text('Delete Expense'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSimpleSettle(BuildContext context, Expense exp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settle Up'),
        content: const Text('Mark as settled?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await FirestoreService.instance.updateExpenseStatus(
                exp.groupId!,
                exp.id,
                'settled',
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  final AppUser currentUser; // Added currentUser
  const _ProfileTab({required this.currentUser}); // Added currentUser

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  final Map<String, String> _currencies = {
    'INR': '₹  Indian Rupee',
    'USD': r'$  US Dollar',
    'EUR': '€  Euro',
    'GBP': '£  British Pound',
  };

  Future<void> _pickProfilePhoto(AppUser user) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final url = await StorageService.instance.uploadProfileImage(
        user.uid,
        File(picked.path),
      );
      await FirestoreService.instance.updateUserPhotoUrl(user.uid, url);
    }
  }

  void _showSettingsDialog(AppUser user) {
    bool dailyReminder = user.requestDailyReminder;
    bool monthlyReminder = user.requestMonthlyReminder;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: dailyReminder,
                    onChanged: (val) async {
                      setDialogState(() => dailyReminder = val);
                      await FirestoreService.instance
                          .updateUserReminderSettings(user.uid, daily: val);
                      if (val) {
                        await NotificationService().enableDailyReminder();
                      } else {
                        await NotificationService().disableDailyReminder();
                      }
                    },
                    title: const Text('Daily Morning Reminder'),
                  ),
                  SwitchListTile(
                    value: monthlyReminder,
                    onChanged: (val) async {
                      setDialogState(() => monthlyReminder = val);
                      await FirestoreService.instance
                          .updateUserReminderSettings(user.uid, monthly: val);
                      if (val) {
                        await NotificationService().enableMonthlyReminder();
                      } else {
                        await NotificationService().disableMonthlyReminder();
                      }
                    },
                    title: const Text('Monthly Settlement Reminder'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.notifications_active,
                      color: AppTheme.yellow,
                    ),
                    title: const Text('Test Notification'),
                    onTap: () {
                      NotificationService().testNotification();
                    },
                  ),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    value: _currencies.containsKey(user.currency)
                        ? user.currency
                        : 'INR',
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: _currencies.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (c) async {
                      if (c != null && c != user.currency) {
                        await FirestoreService.instance.updateUserCurrency(
                          user.uid,
                          c,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
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

  void _showEditNameDialog(AppUser user) {
    final TextEditingController nameController = TextEditingController(
      text: user.name,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  nameController.text != user.name) {
                await FirestoreService.instance.updateUserName(
                  user.uid,
                  nameController.text,
                );
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser; // Changed to widget.currentUser
    if (user == null) return const Center(child: Text('Not logged in'));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.yellow),
            onPressed: () => _showSettingsDialog(user),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.red),
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.blue,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 40,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _pickProfilePhoto(user),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.yellow,
                        borderRadius: BorderRadius.circular(16),
                      ),
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
                  user.name,
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
                  onPressed: () => _showEditNameDialog(user),
                  tooltip: 'Edit Name',
                ),
              ],
            ),
            Text(
              user.email,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            // Stats from streams
            StreamBuilder<List<Expense>>(
              stream: FirestoreService.instance.streamUserExpenses(user.uid),
              builder: (context, expSnap) {
                final expenses = expSnap.data ?? [];
                double spent = 0;
                double owe = 0;
                double owed =
                    0; // Renamed from 'settled' to 'owed' for consistency with ActivityTab

                for (var e in expenses) {
                  final myShare = e.shares[user.uid] ?? 0;

                  // Personal consumption "spent" is what I am responsible for paying/consuming.
                  spent += myShare;

                  if (e.payerId == user.uid) {
                    // I paid the whole bill. People owe me the remainder.
                    if (e.status == 'owed') {
                      owed += (e.amount - myShare);
                    }
                  } else {
                    // Someone else paid. I owe them my share.
                    if (e.status == 'owed') {
                      owe += myShare;
                    }
                  }
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(
                      'Spent',
                      spent.toInt(),
                      AppTheme.blue,
                      user.currency,
                    ),
                    _buildStatCard(
                      'Owe',
                      owe.toInt(),
                      AppTheme.red,
                      user.currency,
                    ),
                    _buildStatCard(
                      'Owed',
                      owed.toInt(),
                      AppTheme.green,
                      user.currency,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            // Other options embedded...
            Card(
              color: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.person_add, color: AppTheme.green),
                title: const Text('Invite Friends'),
                onTap: () => Share.share('Join me on SPENDY!'),
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

  Widget _buildStatCard(
    String label,
    int value,
    Color color,
    String currencyCode,
  ) {
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
              '${getCurrencySymbol(currencyCode)}$value',
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
