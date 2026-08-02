import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_budget/data/supabase_table_sync_service.dart';

void main() {
  test('table sync schema is a complete single-query installer', () {
    final sql = File('supabase/table_sync_v2_schema.sql').readAsStringSync();

    for (final table in supabaseSyncTableNames) {
      expect(sql, contains("'$table'"), reason: '$table is missing');
    }
    expect(sql, contains("notify pgrst, 'reload schema';"));
    expect(sql, contains('installed_table_count'));
    expect(sql, contains('expected_table_count'));
  });
}
