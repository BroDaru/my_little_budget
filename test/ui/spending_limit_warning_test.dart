import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_little_budget/data/daos/budget_dao.dart';
import 'package:my_little_budget/data/daos/transactions_dao.dart';
import 'package:my_little_budget/ui/shared/spending_limit_warning.dart';

void main() {
  testWidgets('카드와 예산 한도 경고를 하나의 메시지로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showSpendingLimitWarnings(
                context,
                cardWarning: const CardLimitWarning(
                  accountId: 1,
                  accountName: '신용카드',
                  limit: 100000,
                  used: 80000,
                  remaining: 20000,
                  thresholdPercent: 80,
                ),
                budgetWarnings: const [
                  BudgetLimitWarning(
                    groupId: 1,
                    groupName: '식비',
                    budgetAmount: 100000,
                    spentAmount: 105000,
                    remaining: -5000,
                    thresholdPercent: 80,
                  ),
                ],
              ),
              child: const Text('경고'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('경고'));
    await tester.pump();

    expect(
      find.text('신용카드 한도까지 ₩20,000 남았습니다.\n식비 예산을 ₩5,000 초과했습니다.'),
      findsOneWidget,
    );
  });
}
