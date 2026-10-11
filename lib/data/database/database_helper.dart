import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _dbFileName = 'advanced_todo.db';

  // version 2 added the soft delete column
  static const int _dbVersion = 2;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;

    final db = await _open();
    _database = db;
    return db;
  }

  Future<Database> _open() async {
    final dbDirectory = await getDatabasesPath();
    final dbPath = join(dbDirectory, _dbFileName);

    return openDatabase(
      dbPath,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _migrateSchema,
    );
  }

  Future<void> _migrateSchema(Database db, int from, int to) async {
    var version = from;
    while (version < to) {
      switch (version) {
        case 1:
          await db.execute(
            'ALTER TABLE ${TaskFields.tableName} '
            'ADD COLUMN ${TaskFields.deletedAt} TEXT',
          );
          await db.execute('''
            CREATE INDEX idx_tasks_deleted_at
            ON ${TaskFields.tableName} (${TaskFields.deletedAt})
            WHERE ${TaskFields.deletedAt} IS NOT NULL
          ''');
      }
      version++;
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${TaskFields.tableName} (
        ${TaskFields.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${TaskFields.title} TEXT NOT NULL,
        ${TaskFields.notes} TEXT NOT NULL DEFAULT '',
        ${TaskFields.date} TEXT NOT NULL,
        ${TaskFields.startMinutes} INTEGER NOT NULL,
        ${TaskFields.endMinutes} INTEGER NOT NULL,
        ${TaskFields.delayMinutes} INTEGER NOT NULL DEFAULT 0,
        ${TaskFields.isCompleted} INTEGER NOT NULL DEFAULT 0,
        ${TaskFields.alarmEnabled} INTEGER NOT NULL DEFAULT 0,
        ${TaskFields.alarmSoundType} TEXT NOT NULL DEFAULT 'system',
        ${TaskFields.alarmSoundUri} TEXT,
        ${TaskFields.alarmSoundLabel} TEXT,
        ${TaskFields.deletedAt} TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_tasks_date_start
      ON ${TaskFields.tableName} (${TaskFields.date}, ${TaskFields.startMinutes})
    ''');
    await db.execute('''
      CREATE INDEX idx_tasks_deleted_at
      ON ${TaskFields.tableName} (${TaskFields.deletedAt})
      WHERE ${TaskFields.deletedAt} IS NOT NULL
    ''');
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
