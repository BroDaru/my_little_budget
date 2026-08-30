import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/daos/budget_dao.dart';
import '../../data/daos/transactions_dao.dart';

void showSpendingLimitWarnings(
  BuildContext context, {
  required CardLimitWarning? cardWarning,
  required List<BudgetLimitWarning> budgetWarnings,
}) {
  final messages = [
    if (cardWarning != null)
      cardWarning.exceeded
          ? '${cardWarning.accountName} 한도를 ${formatKRW(-cardWarning.remaining)} 초과했습니다.'
          : '${cardWarning.accountName} 한도까지 ${formatKRW(cardWarning.remaining)} 남았습니다.',
    for (final warning in budgetWarnings)
      warning.exceeded
          ? '${warning.groupName} 예산을 ${formatKRW(-warning.remaining)} 초과했습니다.'
          : '${warning.groupName} 예산까지 ${formatKRW(warning.remaining)} 남았습니다.',
  ];
  if (messages.isEmpty) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(messages.join('\n')),
      backgroundColor: context.appExpense,
    ),
  );
}
