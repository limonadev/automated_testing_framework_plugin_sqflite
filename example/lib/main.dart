import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:automated_testing_framework_example/automated_testing_framework_example.dart';
import 'package:automated_testing_framework_plugin_sqflite/automated_testing_framework_plugin_sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      // ignore: avoid_print
      print('${record.error}');
    }
    if (record.stackTrace != null) {
      // ignore: avoid_print
      print('${record.stackTrace}');
    }
  });

  WidgetsFlutterBinding.ensureInitialized();

  var databasesPath = await getDatabasesPath();
  var dbPath = path.join(databasesPath, 'test_db.db');

  final database = await openDatabase(
    dbPath,
  );

  var store = SqfliteTestStore(database: database);

  var gestures = TestableGestures();

  runApp(App(
    options: TestExampleOptions(
      autorun: kProfileMode,
      enabled: true,
      gestures: gestures,
      // testReader: AssetTestStore(
      //   testAssetIndex:
      //       'packages/automated_testing_framework_example/assets/all_tests.json',
      // ).testReader,
      testReader: store.testReader,
      testReporter: store.testReporter,
      testWidgetsEnabled: true,
      testWriter: store.testWriter,
    ),
  ));
}
