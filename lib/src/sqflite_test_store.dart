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

    //var snapshot = await database.query(testCollectionTable);
    return results ?? [];
  }

  Future<bool> testWriter(
    BuildContext context,
    Test test,
  ) async {
    var result = false;

    try {
      await _createTablesIfNotExist();
      await _storeTest(testsOwner, test);

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
    String owner,
    Test test,
  ) async {
    var testName = test.name;
    var testData = _encodeTest(test);

    var ownerQuery = await database.query(
      ownersTable,
      where: 'name = \'$testsOwner\'',
    );

    int ownerId = ownerQuery.isEmpty ? null : ownerQuery[0]['id'];
    await database.transaction(
      _storeTransaction(
        owner: owner,
        ownerId: ownerId,
        testData: testData,
        testName: testName,
      ),
    );
  }

  Function _storeTransaction({
    @required String owner,
    @required int ownerId,
    @required String testData,
    @required String testName,
  }) {
    return (Transaction txn) async {
      ownerId ??= await txn.insert(ownersTable, {'name': owner});

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
        .toJson()
        .toString();

    return testData;
  }
}
