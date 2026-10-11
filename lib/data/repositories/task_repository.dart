import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/task.dart';

class TaskRepository {
  TaskRepository() : _databaseHelper = DatabaseHelper.instance;

  final DatabaseHelper _databaseHelper;

  static const String _liveWhere = '${TaskFields.deletedAt} IS NULL';

  Future<Task> insert(Task task) async {
    final db = await _databaseHelper.database;
    final id = await db.insert(
      TaskFields.tableName,
      task.toMap()..remove(TaskFields.id),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return task.copyWith(id: id);
  }

  Future<void> update(Task task) async {
    assert(task.id != null, 'Cannot update a task that was never inserted');
    final db = await _databaseHelper.database;
    await db.update(
      TaskFields.tableName,
      task.toMap(),
      where: '${TaskFields.id} = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _databaseHelper.database;
    await db.delete(
      TaskFields.tableName,
      where: '${TaskFields.id} = ?',
      whereArgs: [id],
    );
  }

  Future<List<Task>> findByDate(String date) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.date} = ? AND $_liveWhere',
      whereArgs: [date],
      orderBy: '${TaskFields.startMinutes} ASC, ${TaskFields.id} ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> search(String query) async {
    final db = await _databaseHelper.database;
    // escape wildcards so the search stays literal
    final escaped = query.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await db.query(
      TaskFields.tableName,
      where: "(${TaskFields.title} LIKE ? ESCAPE '\\' "
          "OR ${TaskFields.notes} LIKE ? ESCAPE '\\') AND $_liveWhere",
      whereArgs: ['%$escaped%', '%$escaped%'],
      orderBy: '${TaskFields.date} DESC, ${TaskFields.startMinutes} ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> findBetweenDates(String fromDate, String toDate) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.date} >= ? AND ${TaskFields.date} <= ? '
          'AND $_liveWhere',
      whereArgs: [fromDate, toDate],
      orderBy: '${TaskFields.date} ASC, ${TaskFields.startMinutes} ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> findUpcomingWithAlarms(String todayDate) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.alarmEnabled} = 1 AND ${TaskFields.date} >= ? '
          'AND $_liveWhere',
      whereArgs: [todayDate],
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> findAllWithCustomSound() async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.alarmSoundType} = ? '
          'AND ${TaskFields.alarmSoundUri} IS NOT NULL',
      whereArgs: [AlarmSoundType.custom.name],
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> clearCustomSound(String path) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.alarmSoundUri} = ?',
      whereArgs: [path],
    );
    if (rows.isEmpty) return const [];

    final cleared = rows
        .map(Task.fromMap)
        .map((task) => task.copyWith(clearAlarmSound: true))
        .toList();
    final batch = db.batch();
    for (final task in cleared) {
      batch.update(
        TaskFields.tableName,
        {
          TaskFields.alarmSoundType: AlarmSoundType.system.name,
          TaskFields.alarmSoundUri: null,
          TaskFields.alarmSoundLabel: null,
        },
        where: '${TaskFields.id} = ?',
        whereArgs: [task.id],
      );
    }
    await batch.commit(noResult: true);
    return cleared;
  }

  Future<void> softDelete(int id, {DateTime? now}) async {
    final db = await _databaseHelper.database;
    await db.update(
      TaskFields.tableName,
      {TaskFields.deletedAt: (now ?? DateTime.now()).toIso8601String()},
      where: '${TaskFields.id} = ?',
      whereArgs: [id],
    );
  }

  Future<void> restoreFromTrash(int id) async {
    final db = await _databaseHelper.database;
    await db.update(
      TaskFields.tableName,
      {TaskFields.deletedAt: null},
      where: '${TaskFields.id} = ?',
      whereArgs: [id],
    );
  }

  Future<List<Task>> findTrashed() async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.deletedAt} IS NOT NULL',
      orderBy: '${TaskFields.deletedAt} DESC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<int> purgeExpiredTrash(Duration retention, {DateTime? now}) async {
    final db = await _databaseHelper.database;
    final cutoff =
        (now ?? DateTime.now()).subtract(retention).toIso8601String();
    return db.delete(
      TaskFields.tableName,
      where: '${TaskFields.deletedAt} IS NOT NULL '
          'AND ${TaskFields.deletedAt} < ?',
      whereArgs: [cutoff],
    );
  }

  Future<int> purgeAllTrash() async {
    final db = await _databaseHelper.database;
    return db.delete(
      TaskFields.tableName,
      where: '${TaskFields.deletedAt} IS NOT NULL',
    );
  }

  Future<List<Task>> findCompletedBefore(String beforeDate) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.isCompleted} = 1 AND ${TaskFields.date} < ? '
          'AND $_liveWhere',
      whereArgs: [beforeDate],
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> findUncompletedBefore(String beforeDate) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      TaskFields.tableName,
      where: '${TaskFields.isCompleted} = 0 AND ${TaskFields.date} < ? '
          'AND $_liveWhere',
      whereArgs: [beforeDate],
    );
    return rows.map(Task.fromMap).toList();
  }
}
