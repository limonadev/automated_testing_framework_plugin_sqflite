import 'dart:convert';
import 'dart:typed_data';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

/// Test Store for the Automated Testing Framework that can read and write tests
/// to SQLite Database.
class SqfliteTestStore {
  /// Initializes the test store.  This requires the [Database] to be
  /// assigned and initialized.
  ///
  /// The [reportsTable] is optional and is the name of the table within SQLite
  /// database where the reports are stored. If omitted, this defaults
  /// to 'Reports'. Regardless of name, the table will have the following columns:
  ///
  /// * **id** INTEGER PRIMARY KEY,
  /// * **device_info** TEXT
  /// * **end_time** INTEGER
  /// * **error_steps** INTEGER
  /// * **images** TEXT
  /// * **logs** TEXT
  /// * **name** TEXT
  /// * **passed_steps** INTEGER
  /// * **runtime_exception** TEXT
  /// * **start_time** INTEGER
  /// * **steps** TEXT
  /// * **success** INTEGER
  /// * **suite_name** TEXT
  /// * **version** INTEGER
  ///
  /// The [suitesTable] is optional and is the name of the table within SQLite
  /// database where the suite names are stored. If omitted, this defaults
  /// to 'Suites'. Regardless of name, the table will have the following columns:
  ///
  /// * **id** INTEGER PRIMARY KEY,
  /// * **suite_name** TEXT
  ///
  /// The [testsTable] is optional and is the name of the table within SQLite
  /// database where the tests themselves are stored. If omitted, this defaults
  /// to 'Tests'. Regardless of name, the table will have the following columns:
  ///
  /// * **id** INTEGER PRIMARY KEY,
  /// * **name** TEXT
  /// * **suite_id** INTEGER
  ///
  /// It's highly recommended to use and mantain a defined pair of table names
  /// for [testsTable] and [suitesTable], instead of changing only one of them.
  SqfliteTestStore({
    @required this.database,
    String reportsTable,
    String suitesTable,
    String testsTable,
  })  : reportsTable = reportsTable ?? 'Reports',
        suitesTable = suitesTable ?? 'Suites',
        testsTable = testsTable ?? 'Tests',
        assert(database != null);

  static final Logger _logger = Logger('SQLiteTestStore');

  /// The initialized SQLite Database reference that will be used to
  /// save tests, read tests, or submit test reports.
  final Database database;

  /// Optional name of the reports table where the reports will be stored.
  final String reportsTable;

  /// Optional name of the suites table where the suite names will be stored.
  final String suitesTable;

  /// Optional name of the tests table where the tests will be stored.
  final String testsTable;

  /// Implementation of the [TestReader] functional interface that can read test
  /// data from SQLite Database.
  Future<List<PendingTest>> testReader(
    BuildContext context, {
    String suiteName,
  }) async {
    List<PendingTest> results;

    try {
      results = [];

      await _createTablesIfNotExist();

      int suiteId;
      if (suiteName != null) {
        suiteId = await _getSuiteId(suiteName);
      }

      var condition;
      if (suiteId != null) {
        condition = 'suite_id = $suiteId';
      }

      var testsList = await database.query(
        testsTable,
        where: condition,
      );

      testsList.forEach((testRow) {
        var test = _decodeTest(testRow);
        results.add(PendingTest.memory(test));
      });
    } catch (e, stack) {
      _logger.severe('Error loading tests', e, stack);
    }

    return results ?? [];
  }

  /// Implementation of the [TestReport] functional interface that can submit
  /// test reports to SQLite Database.
  Future<bool> testReporter(TestReport report) async {
    var result = false;

    try {
      await _createTablesIfNotExist();
      await _storeReport(report);

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing report', e, stack);
    }

    return result;
  }

  /// Implementation of the [TestWriter] functional interface that can submit
  /// test data to SQLite Database.
  Future<bool> testWriter(
    BuildContext context,
    Test test,
  ) async {
    var result = false;

    try {
      await _createTablesIfNotExist();
      await _storeTest(test);

      result = true;
    } catch (e, stack) {
      _logger.severe('Error writing test', e, stack);
    }
    return result;
  }

  Future<void> _createTablesIfNotExist() async {
    await database.transaction((txn) async {
      await txn.execute(
        'create table if not exists $suitesTable (id INTEGER PRIMARY KEY, suite_name TEXT)',
      );
      await txn.execute(
        'create table if not exists $testsTable (id INTEGER PRIMARY KEY, data TEXT, name TEXT, suite_id INTEGER)',
      );
      await txn.execute(
        'create table if not exists $reportsTable ('
        'id INTEGER PRIMARY KEY, '
        'device_info TEXT, '
        'end_time INTEGER, '
        'error_steps INTEGER, '
        'images TEXT, '
        'logs TEXT, '
        'name TEXT, '
        'passed_steps INTEGER, '
        'runtime_exception TEXT, '
        'start_time INTEGER, '
        'steps TEXT, '
        'success INTEGER, '
        'suite_name TEXT, '
        'version INTEGER'
        ')',
      );
    });
  }

  Test _decodeTest(Map<String, dynamic> testRow) {
    var testData = json.decode(testRow['data']);

    var active = testData['active'];
    var name = testData['name'];
    var suiteName = testData['suiteName'];
    var version = testData['version'];

    var rawSteps = testData['steps'];

    List<TestStep> steps = [];
    rawSteps.forEach((raw) {
      var step = TestStep.fromDynamic(
        raw,
        ignoreImages: true,
      );
      steps.add(step);
    });

    return Test(
      active: active,
      name: name,
      steps: steps,
      suiteName: suiteName,
      version: version,
    );
  }

  String _encodeTest(Test test) {
    int version = (test.version ?? 0) + 1;

    var testData = test
        .copyWith(
          steps: test.steps
              .map((e) => e.copyWith(image: Uint8List.fromList([])))
              .toList(),
          version: version,
        )
        .toJson();

    return json.encode(testData);
  }

  Future<int> _getSuiteId(
    String suiteName, {
    Transaction transaction,
  }) async {
    var suiteQuery;

    var condition = 'suite_name = \'$suiteName\'';
    if (transaction != null) {
      suiteQuery = await transaction.query(
        suitesTable,
        where: condition,
      );
    } else {
      suiteQuery = await database.query(
        suitesTable,
        where: condition,
      );
    }

    return suiteQuery.isEmpty ? null : suiteQuery[0]['id'];
  }

  Future<void> _storeReport(TestReport report) async {
    var deviceInfo = json.encode(report.deviceInfo.toJson());
    var images = json.encode(
      report.images
          .map((entity) => String.fromCharCodes(entity.image))
          .toList(),
    );
    var logs = json.encode(report.logs);
    var steps = json.encode(
      report.steps.map((step) => step.toJson()).toList(),
    );
    var success = report.success ? 1 : 0;

    await database.transaction(
      _storeReportTransaction(
        deviceInfo: deviceInfo,
        images: images,
        logs: logs,
        report: report,
        steps: steps,
        success: success,
      ),
    );
  }

  Future<void> _storeTest(Test test) async {
    var suiteName = test.suiteName;
    var testData = _encodeTest(test);
    var testName = test.name;

    await database.transaction(
      _storeTestTransaction(
        suiteName: suiteName,
        testData: testData,
        testName: testName,
      ),
    );
  }

  Function _storeReportTransaction({
    @required String deviceInfo,
    @required String images,
    @required String logs,
    @required TestReport report,
    @required String steps,
    @required int success,
  }) {
    return (Transaction txn) async {
      await txn.insert(
        reportsTable,
        {
          'device_info': deviceInfo,
          'end_time': report.endTime?.millisecondsSinceEpoch,
          'error_steps': report.errorSteps,
          'images': images,
          'logs': logs,
          'name': report.name,
          'passed_steps': report.passedSteps,
          'runtime_exception': report.runtimeException,
          'start_time': report.startTime.millisecondsSinceEpoch,
          'steps': steps,
          'success': success,
          'suite_name': report.suiteName,
          'version': report.version,
        },
      );
    };
  }

  Function _storeTestTransaction({
    @required String suiteName,
    @required String testData,
    @required String testName,
  }) {
    return (Transaction txn) async {
      int suiteId;

      if (suiteName != null) {
        suiteId = await _getSuiteId(
          suiteName,
          transaction: txn,
        );
        suiteId ??= await txn.insert(suitesTable, {'suite_name': suiteName});
      }

      var conflicts = await txn.query(
        testsTable,
        where: 'name = \'$testName\' AND suite_id = $suiteId',
      );

      if (conflicts.isNotEmpty == true) {
        var testId = conflicts[0]['id'];
        await txn.update(
          testsTable,
          {
            'data': testData,
          },
          where: 'id = $testId',
        );
      } else {
        await txn.insert(
          testsTable,
          {
            'data': testData,
            'name': testName,
            'suite_id': suiteId,
          },
        );
      }
    };
  }
}
