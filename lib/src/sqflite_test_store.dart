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
    String testsOwner,
    String testsTable,
  })  : ownersTable = ownersTable ?? 'Owners',
        testsOwner = testsOwner ?? 'default',
        testsTable = testsTable ?? 'Tests',
        assert(database != null);

  final Database database;
  final String ownersTable;
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

          var test = Test(
            active: active,
            name: name,
            steps: steps,
            version: version,
          );

          results.add(PendingTest.memory(test));
        });
      }
    } catch (e) {
      print(e);
      //TODO: Log the exception
    }

    return results ?? [];
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
    });
  }

  Future<void> _storeTest(
    Test test,
  ) async {
    int ownerId = await _getOwnerId();
    var testData = _encodeTest(test);
    var testName = test.name;

    await database.transaction(
      _storeTransaction(
        ownerId: ownerId,
        testData: testData,
        testName: testName,
      ),
    );
  }

  Future<int> _getOwnerId() async {
    var ownerQuery = await database.query(
      ownersTable,
      where: 'name = \'$testsOwner\'',
    );

    return ownerQuery.isEmpty ? null : ownerQuery[0]['id'];
  }

  Function _storeTransaction({
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

      /*var lol = await txn.query(ownersTable);
      print('Owners:');
      lol.forEach((element) => print(element));
      var kappa = await txn.query(testsTable);
      print('Tests:');
      kappa.forEach((element) => print(element));*/
    };
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
}
