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
import '../utils/debt_simplification.dart';

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

  /// Tracks expense IDs already cleaned up to prevent infinite Firestore writes.
  final Set<String> _cleanedExpenseIds = {};

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

  // ─── Legacy cleanup: fix old expenses with all-zero shares but wrong status ──
  void _cleanupLegacyExpenses(List<Expense> expenses) {
    for (final exp in expenses) {
      if (_cleanedExpenseIds.contains(exp.id)) continue;
      final allZero = exp.shares.values.every((v) => v == 0);
      if (allZero && !exp.isSettled) {
        _cleanedExpenseIds.add(exp.id);
        // Fire-and-forget; stream will re-emit automatically
        FirestoreService.instance.updateExpenseStatus(
          exp.groupId,
          exp.id,
          'settled',
        );
      }
    }
  }

  // ─── Helper: compute net balances from expenses ───────────────────────
  Map<String, double> _computeBalances(List<Expense> expenses) {
    Map<String, double> balances = {};
    for (var expense in expenses) {
      if (expense.status == 'settled') continue;

      final payerId = expense.payerId;
      // Credit the payer for the full amount they paid
      balances[payerId] = (balances[payerId] ?? 0) + expense.amount;

      // Debit each participant for their share
      expense.shares.forEach((participantId, shareAmount) {
        balances[participantId] =
            (balances[participantId] ?? 0) - (shareAmount as num).toDouble();
      });
    }
    return balances;
  }

  // ─── Settle Up ────────────────────────────────────────────────────────
  void _showSettleUp(List<Expense> expenses) {
    if (group == null || currentUser == null) return;

    final settlements =
        DebtSimplifier.simplifyDebts(expenses, groupId: widget.groupId);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Settle Up Suggestions',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (settlements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(
                      child: Text('All balances are settled!',
                          style: TextStyle(color: AppTheme.green)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: settlements.length,
                      itemBuilder: (context, index) {
                        final settlement = settlements[index];
                        return FutureBuilder<List<AppUser?>>(
                          future: Future.wait([
                            FirestoreService.instance
                                .getUser(settlement.from),
                            FirestoreService.instance.getUser(settlement.to),
                          ]),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final fromUser = snapshot.data![0];
                            final toUser = snapshot.data![1];

                            if (fromUser == null || toUser == null) {
                              return const SizedBox.shrink();
                            }

                            final fromName = fromUser.uid == currentUserId
                                ? 'You'
                                : fromUser.name;
                            final toName = toUser.uid == currentUserId
                                ? 'You'
                                : toUser.name;
                            final isMe = fromUser.uid == currentUserId ||
                                toUser.uid == currentUserId;

                            return ListTile(
                              leading: const Icon(
                                  Icons.compare_arrows_rounded,
                                  color: AppTheme.blue),
                              title: Text('$fromName → $toName',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: isMe
                                  ? const Text('Tap to record payment',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12))
                                  : null,
                              trailing: Text(
                                '${getCurrencySymbol(currentUser!.currency)}${settlement.amount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: AppTheme.yellow,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                              onTap: isMe
                                  ? () async {
                                      // PART 8: Record settlement as a new expense
                                      // from = debtor (pays), to = creditor (receives)
                                      await FirestoreService.instance
                                          .addExpense(Expense(
                                        id: '',
                                        title: 'Settlement',
                                        amount: settlement.amount,
                                        groupId: widget.groupId,
                                        payerId: settlement.from,
                                        participants: [
                                          settlement.from,
                                          settlement.to
                                        ],
                                        splitType: 'Custom',
                                        shares: {
                                          settlement.from:
                                              settlement.amount,
                                          settlement.to:
                                              settlement.amount,
                                        },
                                        status: 'settled',
                                        createdAt: DateTime.now(),
                                      ));
                                      if (mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Settlement of ${getCurrencySymbol(currentUser!.currency)}${settlement.amount.toStringAsFixed(0)} recorded!')),
                                        );
                                      }
                                    }
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── PART 4: Balance Header Section ───────────────────────────────────
  Widget _buildBalancesSection(List<Expense> expenses) {
    if (group == null || currentUser == null) return const SizedBox.shrink();

    final balances = _computeBalances(expenses);
    final myBalance = balances[currentUserId] ?? 0;

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

    final settlements =
        DebtSimplifier.simplifyDebts(expenses, groupId: widget.groupId);

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
          if (settlements.isEmpty)
            Card(
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
            )
          else
            FutureBuilder<List<AppUser>>(
              future: GroupService().loadGroupMembers(widget.groupId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final members = snapshot.data!;
                final membersMap = {for (var m in members) m.uid: m.name};

                return Card(
                  color: AppTheme.card,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    itemCount: settlements.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16, color: AppTheme.background),
                    itemBuilder: (context, index) {
                      final settlement = settlements[index];
                      final debtorId = settlement.from;
                      final creditorId = settlement.to;

                      final debtorName = debtorId == currentUserId
                          ? 'You'
                          : (membersMap[debtorId] ?? 'Unknown');
                      final creditorName = creditorId == currentUserId
                          ? 'You'
                          : (membersMap[creditorId] ?? 'Unknown');

                      final amountStr =
                          '${getCurrencySymbol(currentUser!.currency)}${settlement.amount.toStringAsFixed(0)}';

                      String text;
                      Color color;

                      if (creditorId == currentUserId) {
                        text = '$debtorName owes You $amountStr';
                        color = AppTheme.green;
                      } else if (debtorId == currentUserId) {
                        text = 'You owe $creditorName $amountStr';
                        color = AppTheme.red;
                      } else {
                        text = '$debtorName owes $creditorName $amountStr';
                        color = AppTheme.textPrimary;
                      }

                      return Text(
                        text,
                        style: TextStyle(
                            color: color,
                            fontSize: 16,
                            fontWeight: FontWeight.w500),
                      );
                    },
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

    final balances = _computeBalances(expenses);

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
                  final bal = balances[member.uid] ?? 0;

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
                          final share =
                              (exp.shares[uid] as num?)?.toDouble() ?? 0;
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
                                  '${getCurrencySymbol(currentUser?.currency ?? 'INR')}${share.toStringAsFixed(0)}',
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
                    // RULE 1: Settle Up — only if NOT settled AND current user owes money
                    if (!exp.isSettled &&
                        currentUserId != exp.payerId &&
                        ((exp.shares[currentUserId] as num?)?.toDouble() ?? 0) > 0)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showSettlePaymentModal(exp);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          child: Text(
                              'Settle Up ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${((exp.shares[currentUserId] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
                        ),
                      )
                    // Show "Already Settled" badge for settled expenses
                    else if (exp.isSettled)
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
  void _showSettlePaymentModal(Expense exp) {
    final amount =
        (exp.shares[currentUserId] as num?)?.toDouble() ?? 0;

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
                    Navigator.pop(ctx);
                    await FirestoreService.instance.updateExpenseStatus(
                      exp.groupId,
                      exp.id,
                      'settled',
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Settlement of ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${amount.toStringAsFixed(0)} recorded!'),
                        ),
                      );
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

                    final receiverUid = exp.payerId;

                    final receiverUser = await FirestoreService.instance.getUser(receiverUid);
                    final receiverUpi = receiverUser?.upiId;
                    final receiverName = receiverUser?.name ?? 'User';

                    print("Receiver UPI: $receiverUpi");

                    if (receiverUpi == null || receiverUpi.trim().isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("$receiverName hasn't added a UPI ID"),
                          ),
                        );
                      }
                      return;
                    }

                    final upiAmount = (exp.shares[currentUserId] as num?)?.toDouble() ?? 0;

                    final uri = Uri.parse(
                      "upi://pay?pa=${receiverUpi.trim()}&pn=${Uri.encodeComponent(receiverName)}&am=$upiAmount&cu=INR&tn=Spendy",
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
  void _showPaymentConfirmationDialog(Expense exp, String receiverUpi, String receiverName, double amount) {
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
              Navigator.pop(ctx);
              await FirestoreService.instance.updateExpenseStatus(
                exp.groupId,
                exp.id,
                'settled',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Settlement of ${getCurrencySymbol(currentUser?.currency ?? 'INR')}${amount.toStringAsFixed(0)} recorded!'),
                  ),
                );
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
                _showPaymentConfirmationDialog(exp, receiverUpi, receiverName, amount);
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

    // Compute net group balance for current user
    final balances = _computeBalances(expenses);
    final netBalance = balances[currentUserId] ?? 0;
    final isGroupSettled = netBalance.abs() < 0.01;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final exp = expenses[index];
        final myShare = (exp.shares[currentUserId] as num?)?.toDouble() ?? 0;
        final isPayer = exp.payerId == currentUserId;

        // Calculate what the current user's NET position is for this expense
        // If payer: net = amount - myShare (you are owed this much)
        // If not payer: net = myShare (you owe this much)
        final double netOwed = isPayer ? (exp.amount - myShare) : myShare;

        return FutureBuilder<AppUser?>(
          future: FirestoreService.instance.getUser(exp.payerId),
          builder: (context, snapshot) {
            final payerName =
                isPayer ? 'You' : (snapshot.data?.name ?? 'Unknown');

            String trailingLabel;
            Color trailingColor;

            if (exp.status == 'settled' || isGroupSettled) {
              trailingLabel = 'Settled ✅';
              trailingColor = AppTheme.textSecondary;
            } else if (netBalance > 0.01) {
              // Current user is owed money overall
              if (isPayer && netOwed > 0.01) {
                trailingLabel = 'You are owed';
                trailingColor = AppTheme.green;
              } else {
                trailingLabel = 'Settled ✅';
                trailingColor = AppTheme.textSecondary;
              }
            } else if (netBalance < -0.01) {
              // Current user owes money overall
              if (!isPayer && myShare > 0.01) {
                trailingLabel = 'You owe';
                trailingColor = AppTheme.red;
              } else {
                trailingLabel = 'Settled ✅';
                trailingColor = AppTheme.textSecondary;
              }
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
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trailingLabel,
                      style: TextStyle(fontSize: 12, color: trailingColor),
                    ),
                    if (netOwed > 0.01 && exp.status != 'settled' && !isGroupSettled)
                      Text(
                        '${getCurrencySymbol(currentUser?.currency ?? 'INR')}${netOwed.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: trailingColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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

            // One-time cleanup of legacy expenses with zeroed-out shares
            _cleanupLegacyExpenses(expenses);

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
                          ElevatedButton.icon(
                            onPressed: () => _showSettleUp(expenses),
                            icon: const Icon(Icons.handshake_rounded),
                            label: const Text('Settle Up'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.green,
                                foregroundColor: Colors.white),
                          ),
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
