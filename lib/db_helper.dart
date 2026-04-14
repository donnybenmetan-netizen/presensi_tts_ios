import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DbHelper {
  static Database? _db;

  static const String _webAppUrl =
      "https://script.google.com/macros/s/AKfycbw-00a2tHw4t767-FR2CUTujd6hogVQKaNd_30dZCNsSyQSGxWSxUcjsAFitOFQjI4/exec";

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), 'absensi_tts.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute(
          "CREATE TABLE absensi("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "nama TEXT, "
          "nip TEXT, "
          "sekolah TEXT, "
          "waktu TEXT, "
          "lat TEXT, "
          "long TEXT, "
          "jenis_kehadiran TEXT, "
          "status TEXT, "
          "device_id TEXT)",
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE absensi ADD COLUMN device_id TEXT");
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE absensi ADD COLUMN nip TEXT");
          await db.execute("ALTER TABLE absensi ADD COLUMN sekolah TEXT");
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE absensi ADD COLUMN jenis_kehadiran TEXT",
          );
        }
      },
    );
  }

  Future<bool> cekSudahAbsen(String deviceId) async {
    final dbClient = await db;
    final hariIni = DateTime.now().toString().substring(0, 10);
    final res = await dbClient.query(
      'absensi',
      where: "device_id = ? AND waktu LIKE ?",
      whereArgs: [deviceId, '$hariIni%'],
    );
    return res.isNotEmpty;
  }

  Future<int> simpanAbsen(
    String nama,
    String lat,
    String long,
    String deviceId, {
    String? nip,
    String? sekolah,
    String jenisKehadiran = 'Hadir',
  }) async {
    final dbClient = await db;
    return dbClient.insert('absensi', {
      'nama': nama,
      'nip': nip ?? '',
      'sekolah': sekolah ?? '',
      'waktu': DateTime.now().toIso8601String(),
      'lat': lat,
      'long': long,
      'jenis_kehadiran': jenisKehadiran,
      'status': 'pending',
      'device_id': deviceId,
    });
  }

  Future<void> sinkronisasiData() async {
    final dbClient = await db;
    final antrean = await dbClient.query(
      'absensi',
      where: "status = ?",
      whereArgs: ['pending'],
      orderBy: 'id ASC',
    );

    for (final data in antrean) {
      try {
        final jenis = data['jenis_kehadiran'];
        final statusSheet = (jenis is String && jenis.trim().isNotEmpty)
            ? jenis.trim()
            : 'Hadir';

        final response = await http
            .post(
              Uri.parse(_webAppUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                "nama": data['nama'],
                "nip": data['nip'],
                "sekolah": data['sekolah'],
                "waktu": data['waktu'],
                "lat": data['lat'],
                "long": data['long'],
                "device": data['device_id'],
                "status": statusSheet,
              }),
            )
            .timeout(const Duration(seconds: 20));

        bool sukses = false;

        if (response.statusCode == 200) {
          try {
            final body = jsonDecode(response.body);
            if (body is Map && body['ok'] == true) {
              sukses = true;
            } else if (body is String &&
                body.toLowerCase().contains('berhasil')) {
              sukses = true;
            }
          } catch (_) {
            if (response.body.toLowerCase().contains('berhasil')) {
              sukses = true;
            }
          }
        }

        if (sukses) {
          await dbClient.update(
            'absensi',
            {'status': 'sent'},
            where: "id = ?",
            whereArgs: [data['id']],
          );
        } else {
          print(
            "Sinkron gagal id=${data['id']} code=${response.statusCode} body=${response.body}",
          );
        }
      } catch (e) {
        print("Sinkron exception id=${data['id']}: $e");
      }
    }
  }
}