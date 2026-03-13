import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/user_model.dart';
import '../services/group_service.dart';
import '../services/firestore_service.dart';
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
                    // RULE 1: Settle Up — only if current user owes money
                    if (currentUserId != exp.payerId &&
                        ((exp.shares[currentUserId] as num?)?.toDouble() ?? 0) > 0)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            // Trigger settle up flow
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

            if (exp.status == 'settled') {
              trailingLabel = 'Settled';
              trailingColor = AppTheme.textSecondary;
            } else if (isPayer && netOwed > 0.01) {
              trailingLabel = 'You are owed';
              trailingColor = AppTheme.green;
            } else if (!isPayer && myShare > 0.01) {
              trailingLabel = 'You owe';
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
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trailingLabel,
                      style: TextStyle(fontSize: 12, color: trailingColor),
                    ),
                    if (netOwed > 0.01 && exp.status != 'settled')
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
      stream: GroupService().streamGroup(widget.groupId),
      builder: (context, groupSnapshot) {
        if (!groupSnapshot.hasData) {
          return const Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(child: CircularProgressIndicator()));
        }
        group = groupSnapshot.data!;

        // PART 1: Query ALL expenses for this group (no status filter)
        return StreamBuilder<List<Expense>>(
          stream: FirestoreService.instance
              .streamGroupExpenses(widget.groupId),
          builder: (context, expenseSnapshot) {
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
