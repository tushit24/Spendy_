import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/user_model.dart';
import '../services/group_service.dart';
import '../services/firestore_service.dart';
import '../services/upi_service.dart';
import '../utils/settlement_utils.dart';

String getCurrencySymbol(String currencyCode) {
  switch (currencyCode) {
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'INR':
    default:
      return '₹';
  }
}

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  AppUser? currentUser;
  Group? group;
  bool _showFullGraph = false;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final userSnap = await FirestoreService.instance.getUser(currentUserId);
    if (mounted) {
      setState(() {
        currentUser = userSnap;
      });
    }
  }


  // ─── PART 4: Balance Header Section ───────────────────────────────────
  Widget _buildBalancesSection(List<Expense> expenses) {
    if (group == null || currentUser == null) return const SizedBox.shrink();

    final debtsMap = SettlementUtils.buildDebtsMap(expenses);
    final myBalance = SettlementUtils.getUserNetBalance(currentUserId, debtsMap);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your Balance',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
              Text(
                myBalance > 0.01
                    ? 'You are owed ${getCurrencySymbol(currentUser!.currency)}${myBalance.toStringAsFixed(0)}'
                    : myBalance < -0.01
                        ? 'You owe ${getCurrencySymbol(currentUser!.currency)}${myBalance.abs().toStringAsFixed(0)}'
                        : 'Settled up',
                style: TextStyle(
                  color: myBalance > 0.01
                      ? AppTheme.green
                      : (myBalance < -0.01
                          ? AppTheme.red
                          : AppTheme.textSecondary),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // ─── PART 4.5: Balances (Who Owes Who) Section ────────────────────────
  Widget _buildWhoOwesWhoSection(List<Expense> expenses) {
    if (group == null || currentUser == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Balances',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          FutureBuilder<List<AppUser>>(
            future: GroupService().loadGroupMembers(widget.groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = snapshot.data!;
              final debts = SettlementUtils.buildDebtsMap(expenses);

              final List<Map<String, dynamic>> youOwe = [];
              final List<Map<String, dynamic>> youAreOwed = [];

              for (var member in members) {
                if (member.uid == currentUserId) continue;
                
                final net = SettlementUtils.round2(SettlementUtils.getNet(currentUserId, member.uid, debts));
                
                if (net > 0.01) {
                  // net > 0 means currentUserId owes member.uid
                  youOwe.add({'uid': member.uid, 'name': member.name, 'amount': net});
                } else if (net < -0.01) {
                  // net < 0 means member.uid owes currentUserId
                  youAreOwed.add({'uid': member.uid, 'name': member.name, 'amount': -net});
                }
              }

              youOwe.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
              youAreOwed.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

              if (youOwe.isEmpty && youAreOwed.isEmpty) {
                return Card(
                  color: AppTheme.card,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text('All balances settled 🎉',
                          style: TextStyle(
                              color: AppTheme.green, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }

              return Card(
                  color: AppTheme.card,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (youOwe.isNotEmpty) ...[
                          const Row(
                            children: [
                              Text('🔴 ', style: TextStyle(fontSize: 16)),
                              Text('You owe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...youOwe.map((debt) => Padding(
                            padding: const EdgeInsets.only(left: 28.0, bottom: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('- ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                                    Text(
                                      '${debt['name']} ',
                                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                                    ),
                                    Text(
                                      '${getCurrencySymbol(currentUser!.currency)}${(debt['amount'] as double).toStringAsFixed(0)}',
                                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                ElevatedButton(
                                  onPressed: () => _showSettlePaymentModal(debt['uid'], debt['name'], debt['amount'] as double),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Settle', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          )),
                        ],
                        if (youOwe.isNotEmpty && youAreOwed.isNotEmpty)
                          const Divider(height: 24, color: AppTheme.background),
                        if (youAreOwed.isNotEmpty) ...[
                          const Row(
                            children: [
                              Text('🟢 ', style: TextStyle(fontSize: 16)),
                              Text('You are owed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...youAreOwed.map((debt) => Padding(
                            padding: const EdgeInsets.only(left: 28.0, bottom: 4.0),
                            child: Row(
                              children: [
                                const Text('- ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                                Text(
                                  '${debt['name']} ',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                                ),
                                Text(
                                  '${getCurrencySymbol(currentUser!.currency)}${(debt['amount'] as double).toStringAsFixed(0)}',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ],
                    ),
                  ),
                );
            },
          ),
        ],
      ),
    );
  }

  // ─── PART 5: Members Section ──────────────────────────────────────────
  Widget _buildMembersSection(List<Expense> expenses) {
    if (group == null || currentUser == null) return const SizedBox.shrink();

    final debtsMap = SettlementUtils.buildDebtsMap(expenses);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Members',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          FutureBuilder<List<AppUser>>(
            future: GroupService().loadGroupMembers(widget.groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = snapshot.data!;

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  final isMe = member.uid == currentUserId;
                  final bal = SettlementUtils.getUserNetBalance(member.uid, debtsMap);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isMe
                          ? AppTheme.blue.withOpacity(0.2)
                          : AppTheme.card,
                      child: Text(
                        member.name.isNotEmpty
                            ? member.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color:
                                isMe ? AppTheme.blue : AppTheme.textPrimary),
                      ),
                    ),
                    title: Text(isMe ? 'You' : member.name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold)),
                    trailing: Text(
                      bal > 0.01
                          ? '+${getCurrencySymbol(currentUser!.currency)}${bal.toStringAsFixed(0)}'
                          : bal < -0.01
                              ? '-${getCurrencySymbol(currentUser!.currency)}${bal.abs().toStringAsFixed(0)}'
                              : 'Settled',
                      style: TextStyle(
                        color: bal > 0.01
                            ? AppTheme.green
                            : (bal < -0.01
                                ? AppTheme.red
                                : AppTheme.textSecondary),
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
    );
  }

  // ─── PART 7: Expense Detail Modal ─────────────────────────────────────
  void _showExpenseDetailsModal(Expense exp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return FutureBuilder<AppUser?>(
          future: FirestoreService.instance.getUser(exp.payerId),
          builder: (context, payerSnap) {
            final payerName = payerSnap.data?.uid == currentUserId
                ? 'You'
                : (payerSnap.data?.name ?? 'Unknown');

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      exp.title,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${group?.name ?? ''} • Paid by $payerName',
                      style:
                          const TextStyle(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Total: ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${exp.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.yellow),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    const Text('Participants & Shares',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ...exp.participants.map((uid) {
                      return FutureBuilder<AppUser?>(
                        future: FirestoreService.instance.getUser(uid),
                        builder: (ctx, uSnap) {
                          final pName = uSnap.data?.uid == currentUserId
                              ? 'You'
                              : (uSnap.data?.name ?? 'Unknown');
                          final displayShare = (exp.shares[uid] as num?)?.toDouble() ?? 0.0;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(pName,
                                    style:
                                        const TextStyle(fontSize: 16)),
                                Text(
                                  '${getCurrencySymbol(currentUser?.currency ?? 'INR')}${displayShare.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }).toList(),
                    const SizedBox(height: 32),
                    // RULE 1: STRICT PRIORITY — If settled, show badge ONLY. Hide Settle Up entirely.
                    if (exp.isSettled)
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
                    // Settle Up button explicitly removed per requirements.
                    // RULE 2: Edit — only if current user is the payer
                    if (exp.payerId == currentUserId)
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
                    if (exp.payerId == currentUserId ||
                        currentUserId == group?.ownerId)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: () async {
                            await FirestoreService.instance
                                .deleteExpense(exp.id);
                            if (mounted) Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                              foregroundColor: AppTheme.red),
                          child: const Text('Delete Expense'),
                        ),
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

  // ─── Settle Payment Modal (Settle in App / Pay via UPI) ────────────────
  void _showSettlePaymentModal(String receiverId, String receiverName, double amount) {

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Settle Payment',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline,
                      color: AppTheme.green, size: 32),
                  title: const Text('Settle in App',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  subtitle: const Text(
                      'Mark this expense as settled manually',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  tileColor: AppTheme.background,
                  onTap: () async {
                    if (_isSettling) return;
                    setState(() => _isSettling = true);
                    Navigator.pop(ctx);

                    try {
                      // Recompute latest net to prevent stale/duplicate settlements
                      final latestExpenses = await FirestoreService.instance
                          .streamGroupExpenses(widget.groupId)
                          .first;
                      final latestDebts = SettlementUtils.buildDebtsMap(latestExpenses);
                      final latestNet = SettlementUtils.round2(
                          SettlementUtils.getNet(currentUserId, receiverId, latestDebts));

                      if (latestNet <= 0.01) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Already settled!')),
                          );
                        }
                        return;
                      }

                      final settlementExpense = Expense(
                        id: '',
                        groupId: widget.groupId,
                        title: "Settlement",
                        amount: latestNet,
                        payerId: currentUserId,
                        participants: [currentUserId, receiverId],
                        shares: {
                          currentUserId: 0,
                          receiverId: latestNet,
                        },
                        splitType: "Settlement",
                        status: "active",
                        createdAt: DateTime.now(),
                      );

                      await FirestoreService.instance.addExpense(settlementExpense);

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Settlement of ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${latestNet.toStringAsFixed(0)} recorded!'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isSettling = false);
                    }
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet,
                      color: AppTheme.blue, size: 32),
                  title: const Text('Pay via UPI',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  subtitle: const Text(
                      'Pay using Google Pay, PhonePe, Paytm, etc.',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  tileColor: AppTheme.background,
                  onTap: () async {
                    print("🔥 Pay via UPI clicked");

                    final receiverUid = receiverId;

                    final receiverUser = await FirestoreService.instance.getUser(receiverUid);
                    final receiverUpi = receiverUser?.upiId;
                    final resolvedReceiverName = receiverUser?.name ?? receiverName;

                    print("Receiver UPI: $receiverUpi");

                    if (receiverUpi == null || receiverUpi.trim().isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("$resolvedReceiverName hasn't added a UPI ID"),
                          ),
                        );
                      }
                      return;
                    }

                    final upiAmount = amount;

                    final uri = Uri.parse(
                      "upi://pay?pa=${receiverUpi.trim()}&pn=${Uri.encodeComponent(resolvedReceiverName)}&am=$upiAmount&cu=INR&tn=Spendy",
                    );

                    print("🚀 Launching UPI: $uri");

                    try {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (e) {
                      print("❌ Launch failed: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "No UPI app found. Please install Google Pay or PhonePe.",
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Post-UPI Payment Confirmation Dialog ─────────────────────────────
  void _showPaymentConfirmationDialog(String receiverId, String receiverName, String receiverUpi, double amount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Payment'),
        content: const Text('Did you complete the payment?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_isSettling) return;
              setState(() => _isSettling = true);
              Navigator.pop(ctx);

              try {
                // Recompute latest net to prevent stale/duplicate settlements
                final latestExpenses = await FirestoreService.instance
                    .streamGroupExpenses(widget.groupId)
                    .first;
                final latestDebts = SettlementUtils.buildDebtsMap(latestExpenses);
                final latestNet = SettlementUtils.round2(
                    SettlementUtils.getNet(currentUserId, receiverId, latestDebts));

                if (latestNet <= 0.01) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Already settled!')),
                    );
                  }
                  return;
                }

                final settlementExpense = Expense(
                  id: '',
                  groupId: widget.groupId,
                  title: "Settlement",
                  amount: latestNet,
                  payerId: currentUserId,
                  participants: [currentUserId, receiverId],
                  shares: {
                    currentUserId: 0,
                    receiverId: latestNet,
                  },
                  splitType: "Settlement",
                  status: "active",
                  createdAt: DateTime.now(),
                );

                await FirestoreService.instance.addExpense(settlementExpense);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Settlement of ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${latestNet.toStringAsFixed(0)} recorded!'),
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isSettling = false);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: Colors.white),
            child: const Text('Yes'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await launchUPI(
                context: context,
                upiId: receiverUpi,
                name: receiverName,
                amount: amount,
              );
              if (mounted) {
                _showPaymentConfirmationDialog(receiverId, receiverName, receiverUpi, amount);
              }
            },
            child: const Text('Open Again'),
          ),
        ],
      ),
    );
  }

  // ─── PART 6: Group Expense Card ───────────────────────────────────────
  Widget _buildExpensesList(List<Expense> expenses) {
    if (expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: Text('No expenses in this group yet',
                style: TextStyle(color: AppTheme.textSecondary))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final exp = expenses[index];
        final myShare = (exp.shares[currentUserId] as num?)?.toDouble() ?? 0.0;
        final isPayer = exp.payerId == currentUserId;

        return FutureBuilder<AppUser?>(
          future: FirestoreService.instance.getUser(exp.payerId),
          builder: (context, snapshot) {
            final payerName =
                isPayer ? 'You' : (snapshot.data?.name ?? 'Unknown');

            String trailingLabel;
            Color trailingColor;

            // RAW PER-EXPENSE LOGIC — no group-level netting
            if (exp.isSettlement) {
              final rounded = SettlementUtils.round2(exp.amount);
              trailingLabel = 'Settled ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${rounded.toStringAsFixed(0)}';
              trailingColor = AppTheme.green;
            } else if (isPayer) {
              double totalOwedToYou = 0;
              exp.shares.forEach((userId, share) {
                if (userId != currentUserId) {
                  totalOwedToYou += (share as num).toDouble();
                }
              });
              final rounded = SettlementUtils.round2(totalOwedToYou);
              trailingLabel = 'You are owed ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${rounded.toStringAsFixed(0)}';
              trailingColor = AppTheme.green;
            } else if (exp.shares.containsKey(currentUserId)) {
              final rounded = SettlementUtils.round2(myShare);
              trailingLabel = 'You owe ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${rounded.toStringAsFixed(0)}';
              trailingColor = AppTheme.red;
            } else {
              trailingLabel = 'Not involved';
              trailingColor = AppTheme.textSecondary;
            }

            return Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppTheme.card,
              child: ListTile(
                onTap: () => _showExpenseDetailsModal(exp),
                leading: const Icon(Icons.receipt_long_rounded,
                    color: AppTheme.blue),
                title: Text(exp.title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${group?.name ?? ''} • Paid by $payerName'),
                trailing: Text(
                  trailingLabel,
                  style: TextStyle(
                    color: trailingColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── PART 1: Build method with correct query ──────────────────────────
  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<Group?>(
      stream: GroupService().streamGroup(widget.groupId).timeout(const Duration(seconds: 30)),
      builder: (context, groupSnapshot) {
        if (groupSnapshot.hasError) {
          final isTimeout = groupSnapshot.error.toString().contains('TimeoutException');
          return _AutoRetryWrapper(
            onRetry: () => setState(() {}),
            child: Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(backgroundColor: AppTheme.background, elevation: 0),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isTimeout ? Icons.hourglass_top_rounded : Icons.wifi_off, size: 60, color: isTimeout ? AppTheme.yellow : Colors.grey),
                    const SizedBox(height: 16),
                    Text(isTimeout ? 'Taking longer than usual' : 'Something went wrong', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(isTimeout ? 'The server is slow to respond.' : 'Please check your connection and try again.', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!groupSnapshot.hasData) {
          return const Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(child: CircularProgressIndicator()));
        }
        group = groupSnapshot.data!;

        // PART 1: Query ALL expenses for this group (no status filter)
        return StreamBuilder<List<Expense>>(
          stream: FirestoreService.instance
              .streamGroupExpenses(widget.groupId).timeout(const Duration(seconds: 30)),
          builder: (context, expenseSnapshot) {
            if (expenseSnapshot.hasError) {
              final isTimeout = expenseSnapshot.error.toString().contains('TimeoutException');
              return _AutoRetryWrapper(
                onRetry: () => setState(() {}),
                child: Scaffold(
                  backgroundColor: AppTheme.background,
                  appBar: AppBar(backgroundColor: AppTheme.background, elevation: 0, title: Text(group!.name)),
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isTimeout ? Icons.hourglass_top_rounded : Icons.wifi_off, size: 60, color: isTimeout ? AppTheme.yellow : Colors.grey),
                        const SizedBox(height: 16),
                        Text(isTimeout ? 'Taking longer than usual' : 'Could not load expenses', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (expenseSnapshot.connectionState == ConnectionState.waiting && !expenseSnapshot.hasData) {
              return Scaffold(
                backgroundColor: AppTheme.background,
                appBar: AppBar(backgroundColor: AppTheme.background, elevation: 0, title: Text(group!.name)),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Connecting...', style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              );
            }
            final expenses = expenseSnapshot.data ?? [];

            return Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(
                backgroundColor: AppTheme.background,
                elevation: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group!.name,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${group!.members.length} Members',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      // Group settings
                    },
                  )
                ],
              ),
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Action Buttons Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Code: ${group!.code}')));
                            },
                            icon: const Icon(Icons.person_add),
                            label: const Text('Invite'),
                          ),
                        ],
                      ),
                    ),

                    _buildBalancesSection(expenses),
                    const SizedBox(height: 8),
                    _buildWhoOwesWhoSection(expenses),
                    const SizedBox(height: 16),
                    _buildMembersSection(expenses),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Expenses',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary)),
                    ),
                    const SizedBox(height: 8),
                    _buildExpensesList(expenses),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AutoRetryWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onRetry;
  const _AutoRetryWrapper({required this.child, required this.onRetry});

  @override
  State<_AutoRetryWrapper> createState() => _AutoRetryWrapperState();
}

class _AutoRetryWrapperState extends State<_AutoRetryWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) widget.onRetry();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
