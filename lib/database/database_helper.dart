import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final projectDir = Directory.current.path;
    final dbDir = Directory(join(projectDir, 'database'));

    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final path = join(dbDir.path, 'safebuddy.db');

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1, // 第一次建就用 version 1
        onCreate: (db, version) async {
          // 建立 users table
          await db.execute('''
            CREATE TABLE users (
              userId TEXT PRIMARY KEY,
              username TEXT NOT NULL,
              password TEXT NOT NULL,
              name TEXT NOT NULL
            )
          ''');

          // 建立 alerts table
          await db.execute('''
            CREATE TABLE alerts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              area TEXT NOT NULL,
              category TEXT NOT NULL,
              time TEXT NOT NULL,
              userId TEXT NOT NULL,
              FOREIGN KEY(userId) REFERENCES users(userId) ON DELETE CASCADE
            )
          ''');
        },
      ),
    );
  }

  Future<String?> validateRegistration({
    required String name,
    required String username,
    required String password,
    }) async {
    // 檢查名稱是否已存在
    final allUsers = await DatabaseHelper.instance.getAllUsers();
    for (var user in allUsers) {
        if (user['name'] == name) {
        return '名稱已存在';
        }
        if (user['username'] == username) {
        return '帳號已存在';
        }
        if (user['password'] == password) {
        return '密碼已被使用';
        }
    }

    // 都沒重複
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return await db.query('users');
  }

  Future<Map<String, dynamic>?> getUserById(String userId) async {
    final db = await database;
    final res = await db.query(
      'users',
      where: 'userId = ?',
      whereArgs: [userId],
    );
    
    if (res.isEmpty) return null; // 沒找到
    return res.first;             // 回傳使用者資料
  }

  Future<String> updateUser(String userId, Map<String, dynamic> newData) async {
    final db = await database;

    // 先檢查 username 或 name 是否重複（排除自己）
    final existingUser = await db.query(
      'users',
      where: '(username = ? OR name = ?) AND userId != ?',
      whereArgs: [newData['username'], newData['name'], userId],
    );

    if (existingUser.isNotEmpty) {
      return '帳號或名稱已存在';
    }

    await db.update(
      'users',
      newData,
      where: 'userId = ?',
      whereArgs: [userId],
    );

    return 'success';
  }

  Future<int> insertAlert(Map<String, dynamic> alert) async {
    final db = await database;
    return await db.insert('alerts', alert);
  }

  // 取得某使用者的所有 alerts
  Future<List<Map<String, dynamic>>> getAlertsByUserId(String userId) async {
    final db = await database;
    return await db.query(
      'alerts',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'time DESC', // 可依時間排序，最新的在前面
    );
  }

  // 其他方法保持不變
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final db = await database;
    final res = await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (res.isEmpty) return null;
    return res.first;
  }

  Future<String> insertUser(Map<String, dynamic> user) async {
    final db = await database;

    // 先檢查 username 是否存在
    final existingUser = await db.query(
        'users',
        where: 'username = ? OR userId = ? OR name = ?',
        whereArgs: [user['username'], user['userId'], user['name']],
    );

    if (existingUser.isNotEmpty) {
        // 回傳錯誤訊息
        return '帳號或名稱已存在';
    }

    // 如果不存在，才插入
    await db.insert('users', user);
    return 'success';
    }

}
