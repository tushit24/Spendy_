import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for FirebaseAuth
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/group_service.dart'; // Added for GroupService
import 'services/storage_service.dart';
import 'models/group_model.dart';
import 'models/expense_model.dart';
import 'models/user_model.dart';
import 'services/notification_service.dart';
import 'services/upi_service.dart';
import 'screens/group_details_screen.dart';
import 'utils/settlement_utils.dart';

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

/// Returns true if the error is a timeout (not a real connectivity failure).
bool _isTimeoutError(Object? error) {
  if (error == null) return false;
  return error.toString().contains('TimeoutException');
}

/// Reusable error view — auto-detects timeout vs real errors, auto-retries after 5s.
Widget _buildErrorView({Object? error, String? message, VoidCallback? onRetry}) {
  return _AutoRetryErrorView(error: error, message: message, onRetry: onRetry);
}

class _AutoRetryErrorView extends StatefulWidget {
  final Object? error;
  final String? message;
  final VoidCallback? onRetry;

  const _AutoRetryErrorView({this.error, this.message, this.onRetry});

  @override
  State<_AutoRetryErrorView> createState() => _AutoRetryErrorViewState();
}

class _AutoRetryErrorViewState extends State<_AutoRetryErrorView> {
  Timer? _retryTimer;
  int _countdown = 2;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startAutoRetry();
  }

  void _startAutoRetry() {
    _retryTimer?.cancel();
    _countdownTimer?.cancel();
    _countdown = 2;

    // Countdown tick every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() { _countdown--; });
      if (_countdown <= 0) timer.cancel();
    });

    // Auto-retry after 2 seconds
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && widget.onRetry != null) {
        widget.onRetry!();
      }
    });
  }

  void _manualRetry() {
    _retryTimer?.cancel();
    _countdownTimer?.cancel();
    if (widget.onRetry != null) widget.onRetry!();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTimeout = _isTimeoutError(widget.error);
    final icon = isTimeout ? Icons.hourglass_top_rounded : Icons.wifi_off_rounded;
    final iconColor = isTimeout ? AppTheme.yellow : AppTheme.red;
    final title = widget.message ?? (isTimeout
        ? 'Taking longer than usual'
        : 'Something went wrong');
    final subtitle = isTimeout
        ? 'The server is slow to respond. Please try again.'
        : 'Please check your connection and try again.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: iconColor),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (widget.onRetry != null)
              ElevatedButton.icon(
                onPressed: _manualRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              _countdown > 0 ? 'Retrying in $_countdown s...' : 'Retrying...',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable shimmer-like loading view.
Widget _buildLoadingView({String? message}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: AppTheme.yellow,
            strokeWidth: 3,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ],
    ),
  );
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
        if (userSnap.hasError) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: _buildErrorView(
              error: userSnap.error,
              onRetry: () => setState(() {}),
            ),
          );
        }
        if (userSnap.connectionState == ConnectionState.waiting && !userSnap.hasData) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: _buildLoadingView(message: 'Connecting...'),
          );
        }
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
              return _buildErrorView(
                error: snapshot.error,
                onRetry: () => setState(() {}),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _buildLoadingView(message: 'Connecting...');
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
    print("DELETE CLICKED");
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
          'Start tracking You Paid from today?\n\nAll previous expenses will be excluded from the counter.',
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
        stream: FirestoreService.instance.streamUserExpenses(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorView(
              error: snapshot.error,
              onRetry: () => setState(() {}),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return _buildLoadingView(message: 'Connecting...');
          }
          final expenses = snapshot.data ?? [];
          print("HOME EXPENSE COUNT: ${expenses.length}");

          // Apply time filter locally for display (same base data as Activity/Profile)
          final filterDate = _getFilterStartDate();
          final displayExpenses = filterDate != null
              ? expenses.where((e) => !e.createdAt.isBefore(filterDate)).toList()
              : expenses;
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
                    if (displayExpenses.isNotEmpty)
                      _buildChartCard(displayExpenses)
                    else
                      Card(
                        color: AppTheme.card,
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              expenses.isEmpty
                                  ? 'No expenses yet'
                                  : 'No expenses this month',
                            ),
                          ),
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
                      Builder(
                        builder: (context) {
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: expenses.length,
                            itemBuilder: (context, i) {
                              final exp = expenses[i];
                              final myShare = (exp.shares[user.uid] as num?)?.toDouble() ?? 0.0;
                              final currentUserId = user.uid;

                              String label;
                              Color labelColor;

                              if (exp.isSettled == true || exp.isSettlement) {
                                final rounded = SettlementUtils.round2(exp.amount);
                                if (exp.isSettlement) {
                                  label = 'Settled ${getCurrencySymbol(currencyCode)}${rounded.toStringAsFixed(0)}';
                                  labelColor = AppTheme.green;
                                } else {
                                  label = 'Settled ✅';
                                  labelColor = AppTheme.textSecondary;
                                }
                              } else if (exp.payerId == currentUserId) {
                                double totalOwedToYou = 0;
                                exp.shares.forEach((userId, share) {
                                  if (userId != currentUserId) {
                                    totalOwedToYou += (share as num).toDouble();
                                  }
                                });
                                final rounded = SettlementUtils.round2(totalOwedToYou);
                                label = 'You are owed ${getCurrencySymbol(currencyCode)}${rounded.toStringAsFixed(0)}';
                                labelColor = AppTheme.green;
                              } else if (exp.shares.containsKey(currentUserId)) {
                                final rounded = SettlementUtils.round2(myShare);
                                label = 'You owe ${getCurrencySymbol(currencyCode)}${rounded.toStringAsFixed(0)}';
                                labelColor = AppTheme.red;
                              } else {
                                label = 'Not involved';
                                labelColor = AppTheme.textSecondary;
                              }

                              return ListTile(
                                leading: const Icon(
                                  Icons.receipt_long_rounded,
                                  color: AppTheme.blue,
                                ),
                                title: Text(exp.title),
                                subtitle: Text(
                                  '${exp.splitType} • ${getCurrencySymbol(currencyCode)}${myShare.toStringAsFixed(0)}',
                                ),
                                trailing: Text(
                                  label,
                                  style: TextStyle(
                                    color: labelColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
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
                      'You Paid',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      'Excludes settlements',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${getCurrencySymbol(currencyCode)}${SettlementUtils.calculateTotalSpent(expenses, authUid).toStringAsFixed(0)}',
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
      if (exp.isSettlement) continue; // Settlements are not spending
      if (exp.payerId != uid) continue; // Only what user PAID

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
      groupTotals[group] = (groupTotals[group] ?? 0) + exp.amount;
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
            stream: GroupService().getUserGroups().timeout(const Duration(seconds: 30)),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('Could not load groups', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final groups = snapshot.data ?? [];

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
      final equalShare = amount / selectedMemberIds.length;
      shares = {
        for (var uid in selectedMemberIds) uid: equalShare
      };
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

    print("🔥 Creating expense with shares: $shares");
    print("🔥 selectedMemberIds: $selectedMemberIds");
    print("🔥 splitType: $splitType, amount: $amount");

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
          currentUser: widget.currentUser!,
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

          // Removed Simplification modal
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
          if (groupSnapshot.hasError) {
            return _buildErrorView(
              error: groupSnapshot.error,
              onRetry: () => setState(() {}),
            );
          }
          if (groupSnapshot.connectionState == ConnectionState.waiting && !groupSnapshot.hasData) {
            return _buildLoadingView(message: 'Connecting...');
          }
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
            stream: FirestoreService.instance.streamUserExpenses(user.uid),
            builder: (context, expenseSnapshot) {
              if (expenseSnapshot.hasError) {
                return _buildErrorView(
                  error: expenseSnapshot.error,
                  onRetry: () => setState(() {}),
                );
              }
              if (expenseSnapshot.connectionState == ConnectionState.waiting && !expenseSnapshot.hasData) {
                return _buildLoadingView(message: 'Connecting...');
              }
              // ── FULL DATASET (for summary cards — never filtered) ──
              final allExpenses = expenseSnapshot.data ?? [];

              // ── Summary from FULL unfiltered list (single source of truth) ──
              final owe = SettlementUtils.getUserOwe(user.uid, allExpenses);
              final owed = SettlementUtils.getUserOwed(user.uid, allExpenses);
              final spent = SettlementUtils.getMonthlySpending(allExpenses, user.uid);

              // ── FILTERED list (for display list only) ──
              final displayExpenses = allExpenses.where((e) {
                // Must involve current user
                if (e.payerId != user.uid && !e.participants.contains(user.uid)) return false;
                // Group filter
                if (_selectedGroupId != 'All' && e.groupId != _selectedGroupId) return false;
                // User filter
                if (_selectedUserId != 'All' &&
                    e.payerId != _selectedUserId &&
                    !e.participants.contains(_selectedUserId)) return false;
                // Search filter
                if (_search.isNotEmpty &&
                    !e.title.toLowerCase().contains(_search.toLowerCase())) return false;
                return true;
              }).toList();

              // ── DEBUG ──
              print("ALL EXPENSE COUNT: ${allExpenses.length}");
              print("DISPLAY EXPENSE COUNT: ${displayExpenses.length}");
              print("OWE: $owe | OWED: $owed | SPENT: $spent");

              // Group expenses by date
              final grouped = <String, List<Expense>>{};
              for (var exp in displayExpenses) {
                final dateKey = _formatDate(exp.createdAt);
                grouped.putIfAbsent(dateKey, () => []).add(exp);
              }

              // Extract unique participants for User Filter
              // This is a bit heavy, but fine for small data
              final Set<String> participantIds = displayExpenses
                  .expand((e) => e.participants)
                  .toSet();

              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── FIXED: Summary cards ─────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSummaryCard('You Owe', owe.toInt(), AppTheme.red),
                        _buildSummaryCard(
                          "You're Owed",
                          owed.toInt(),
                          AppTheme.green,
                        ),
                        _buildSummaryCard(
                          'You Paid (This Month)',
                          spent.toInt(),
                          AppTheme.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ─── FIXED: Filters row ───────────────────────
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

                    // ─── FIXED: Search ────────────────────────────
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search by description',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) => setState(() => _search = val),
                    ),
                    const SizedBox(height: 12),

                    // ─── SCROLLABLE: Balances + Activity list ─────
                    Expanded(
                      child: displayExpenses.isEmpty
                          ? const Center(child: Text('No activity yet.'))
                          : ListView(
                              children: [


                                // Activity list grouped by date
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
                                              _buildExpenseCard(exp),
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

  Widget _buildExpenseCard(Expense exp) {
    final currentUserId = widget.currentUser.uid;
    final currencySymbol = getCurrencySymbol(widget.currentUser.currency);

    String trailingLabel;
    Color trailingColor;

    if (exp.isSettlement) {
      final rounded = SettlementUtils.round2(exp.amount);
      trailingLabel = 'Settlement $currencySymbol${rounded.toStringAsFixed(0)}';
      trailingColor = AppTheme.green;
    } else {
      // Accumulator-based per-expense impact
      double owe = 0;
      double owed = 0;

      exp.shares.forEach((participantId, shareVal) {
        if (participantId == exp.payerId) return; // skip payer's own share
        final contribution = (shareVal as num).toDouble();

        if (participantId == currentUserId) {
          owe += contribution;
        }
        if (exp.payerId == currentUserId) {
          owed += contribution;
        }
      });

      owe = SettlementUtils.round2(owe);
      owed = SettlementUtils.round2(owed);

      if (owed > 0) {
        trailingLabel = 'You are owed $currencySymbol${owed.toStringAsFixed(0)}';
        trailingColor = AppTheme.green;
      } else if (owe > 0) {
        trailingLabel = 'You owe $currencySymbol${owe.toStringAsFixed(0)}';
        trailingColor = AppTheme.red;
      } else {
        trailingLabel = 'Not involved';
        trailingColor = AppTheme.textSecondary;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Card(
        color: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: FutureBuilder<AppUser?>(
          future: FirestoreService.instance.getUser(exp.payerId),
          builder: (context, snapshot) {
            final payerName = snapshot.data?.uid == currentUserId ? 'You' : (snapshot.data?.name ?? 'Unknown');

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.primaries[exp.groupId.hashCode % Colors.primaries.length],
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
                'Paid by $payerName', // Leftover groupName removed because allGroups is removed from signature
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailingLabel,
                    style: TextStyle(
                      color: trailingColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  // Reactions
                  SizedBox(
                    height: 24,
                    child: StreamBuilder<String?>(
                      stream: FirestoreService.instance.streamUserReaction(
                        groupId: exp.groupId!,
                        expenseId: exp.id,
                        uid: currentUserId,
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
                                  uid: currentUserId,
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
              onTap: () async {
                final groupDoc = await FirebaseFirestore.instance.collection('groups').doc(exp.groupId).get();
                String groupName = 'Unknown';
                String groupOwnerId = '';
                if (groupDoc.exists && groupDoc.data() != null) {
                  final data = groupDoc.data()!;
                  groupName = data['name'] as String? ?? 'Unknown';
                  groupOwnerId = data['ownerId'] as String? ?? '';
                }
                if (!context.mounted) return;
                _showExpenseDetails(exp, groupName, groupOwnerId);
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
                  // RULE 1: STRICT PRIORITY — If settled, show badge ONLY.
                  if (expense.isSettled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.green.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Already Settled ✅',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
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

}

class _ProfileTab extends StatefulWidget {
  final AppUser currentUser; // Added currentUser
  const _ProfileTab({required this.currentUser}); // Added currentUser

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String? upiError;
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextFormField(
                initialValue: user.upiId,
                decoration: InputDecoration(
                  labelText: 'UPI ID',
                  hintText: 'example@oksbi',
                  errorText: upiError,
                  prefixIcon: const Icon(Icons.payment, color: AppTheme.yellow),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) async {
                  bool isValidUpi(String upi) {
                    return RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{3,}$').hasMatch(upi);
                  }
                  
                  final upi = value.trim();
                  if (!isValidUpi(upi) && upi.isNotEmpty) {
                    setState(() {
                      upiError = "Enter a valid UPI ID";
                    });
                    return;
                  }

                  setState(() {
                    upiError = null;
                  });

                  await FirestoreService.instance
                      .updateUserUpiId(user.uid, upi);
                },
              ),
            ),
            const SizedBox(height: 32),
            // Stats from streams
            StreamBuilder<List<Expense>>(
              stream: FirestoreService.instance.streamUserExpenses(user.uid).timeout(const Duration(seconds: 30)),
              builder: (context, expSnap) {
                if (expSnap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.wifi_off, size: 40, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text('Could not load stats', style: TextStyle(color: AppTheme.textSecondary)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (expSnap.connectionState == ConnectionState.waiting && !expSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final expenses = expSnap.data ?? [];
                print("PROFILE EXPENSE COUNT: ${expenses.length}");
                final spent = SettlementUtils.calculateTotalSpent(expenses, user.uid);
                final owe = SettlementUtils.getUserOwe(user.uid, expenses);
                final owed = SettlementUtils.getUserOwed(user.uid, expenses);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(
                      'You Paid',
                      spent.toInt(),
                      AppTheme.blue,
                      user.currency,
                    ),
                    _buildStatCard(
                      'You Owe',
                      owe.toInt(),
                      AppTheme.red,
                      user.currency,
                    ),
                    _buildStatCard(
                      'You\'re Owed',
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
