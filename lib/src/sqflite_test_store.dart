import 'dart:convert';
import 'dart:typed_data';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteTestStore {
  SqfliteTestStore({
    @required this.database,
    String ownersTable,
    String reportsTable,
    String testsOwner,
    String testsTable,
  })  : ownersTable = ownersTable ?? 'Owners',
        reportsTable = reportsTable ?? 'Reports',
        testsOwner = testsOwner ?? 'default',
        testsTable = testsTable ?? 'Tests',
        assert(database != null);

  final Database database;
  final String ownersTable;
  final String reportsTable;
  final String testsOwner;
  final String testsTable;

  Future<List<PendingTest>> testReader(BuildContext context) async {
    List<PendingTest> results;

    try {
      results = [];

      await _createTablesIfNotExist();

      int ownerId = await _getOwnerId();

      if (ownerId != null) {
        var testsList = await database.query(
          testsTable,
          where: 'owner_id = $ownerId',
        );

        testsList.forEach((testRow) {
          var test = _decodeTest(testRow);
          results.add(PendingTest.memory(test));
        });
      }
    } catch (e) {
      print(e);
      //TODO: Log the exception
    }

    return results ?? [];
  }

  Future<bool> testReporter(TestReport report) async {
    var result = false;

    try {
      await _createTablesIfNotExist();
      await _storeReport(report);

      result = true;
    } catch (e) {
      print(e);
      //TODO: Log the exception
    }

    return result;
  }

  Future<bool> testWriter(
    BuildContext context,
    Test test,
  ) async {
    var result = false;

    try {
      await _createTablesIfNotExist();
      await _storeTest(test);

      result = true;
    } catch (e) {
      print(e);
      //TODO: Log the exception
    }
    return result;
  }

  Future<void> _createTablesIfNotExist() async {
    await database.transaction((txn) async {
      await txn.execute(
        'create table if not exists $ownersTable (id INTEGER PRIMARY KEY, owner TEXT)',
      );
      await txn.execute(
        'create table if not exists $testsTable (id INTEGER PRIMARY KEY, name TEXT, data TEXT, owner_id INTEGER)',
      );
      await txn.execute(
        'create table if not exists $reportsTable ('
        'id INTEGER PRIMARY KEY, '
        'owner TEXT, '
        'name TEXT, '
        'version INTEGER, '
        'device_info TEXT, '
        'end_time INTEGER, '
        'error_steps INTEGER, '
        'images TEXT, '
        'inverted_start_time INTEGER, '
        'logs TEXT, '
        'passed_steps INTEGER, '
        'runtime_exception TEXT, '
        'start_time INTEGER, '
        'steps TEXT, '
        'success INTEGER'
        ')',
      );
    });
  }

  Test _decodeTest(Map<String, dynamic> testRow) {
    var testData = json.decode(testRow['data']);

    var active = testData['active'];
    var name = testData['name'];
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

  Future<int> _getOwnerId() async {
    var ownerQuery = await database.query(
      ownersTable,
      where: 'name = \'$testsOwner\'',
    );

    return ownerQuery.isEmpty ? null : ownerQuery[0]['id'];
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
    int ownerId = await _getOwnerId();
    var testData = _encodeTest(test);
    var testName = test.name;

    await database.transaction(
      _storeTestTransaction(
        ownerId: ownerId,
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
          'owner': testsOwner,
          'name': report.name,
          'version': report.version,
          'device_info': deviceInfo,
          'end_time': report.endTime?.millisecondsSinceEpoch,
          'error_steps': report.errorSteps,
          'images': images,
          'inverted_start_time': -1 * report.startTime.millisecondsSinceEpoch,
          'logs': logs,
          'passed_steps': report.passedSteps,
          'runtime_exception': report.runtimeException,
          'start_time': report.startTime.millisecondsSinceEpoch,
          'steps': steps,
          'success': success,
        },
      );
    };
  }

  Function _storeTestTransaction({
    @required int ownerId,
    @required String testData,
    @required String testName,
  }) {
    return (Transaction txn) async {
      ownerId ??= await txn.insert(ownersTable, {'name': testsOwner});

      var conflicts = await txn.query(
        testsTable,
        where: 'name = \'$testName\' AND owner_id = $ownerId',
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
            'owner_id': ownerId,
          },
        );
      }
    };
  }
}
