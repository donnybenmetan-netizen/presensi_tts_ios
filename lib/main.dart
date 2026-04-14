import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'db_helper.dart';

void main() => runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const PresensiGuruTTS(),
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
        ),
      ),
    );

class PresensiGuruTTS extends StatefulWidget {
  const PresensiGuruTTS({super.key});

  @override
  State<PresensiGuruTTS> createState() => _PresensiGuruTTSState();
}

class _PresensiGuruTTSState extends State<PresensiGuruTTS> {
  Map<String, String>? _guruTerpilih;
  List<Map<String, String>> _daftarGuru = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final String _urlWebApp =
      "https://script.google.com/macros/s/AKfycbw-00a2tHw4t767-FR2CUTujd6hogVQKaNd_30dZCNsSyQSGxWSxUcjsAFitOFQjI4/exec";

  @override
  void initState() {
    super.initState();
    _ambilDataGuru();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ambilDataGuru() async {
    try {
      final response = await http.get(Uri.parse(_urlWebApp));

      if (response.statusCode != 200) {
        _showErrorDialog("Gagal memuat data guru (HTTP ${response.statusCode}).");
        return;
      }

      final decoded = jsonDecode(response.body);

      final List<dynamic> rawList = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List)
              ? decoded['data'] as List<dynamic>
              : <dynamic>[];

      final list = rawList.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);

        final nama = (map['nama'] ?? map['Nama'] ?? '').toString().trim();
        final nip = (map['nip'] ?? map['NIP'] ?? '').toString().trim();
        final sekolah =
            (map['sekolah'] ?? map['Sekolah'] ?? '').toString().trim();

        return {
          "nama": nama,
          "nip": nip,
          "sekolah": sekolah,
        };
      }).where((g) => (g['nama'] ?? '').isNotEmpty).toList();

      setState(() {
        _daftarGuru = list;
      });

      if (_daftarGuru.isEmpty) {
        _showErrorDialog("Data guru kosong. Cek isi sheet Daftar_Guru.");
      }
    } catch (e) {
      _showErrorDialog("Error ambil data: $e");
    }
  }

  Future<void> _prosesAbsen({String jenisKehadiran = 'Hadir'}) async {
    if (_guruTerpilih == null) return;

    final now = DateTime.now();
    if (now.hour >= 9) {
      _showErrorDialog(
        "Maaf, pengisian daftar hadir sudah ditutup. Batas waktu maksimal adalah pukul 09.00.",
      );
      return;
    }

    final deviceInfo = DeviceInfoPlugin();
    String deviceId = '';

    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
    } else {
      deviceId = 'unknown_platform';
    }

    final sudahAbsen = await DbHelper().cekSudahAbsen(deviceId);
    if (sudahAbsen) {
      _showErrorDialog("Perangkat ini sudah digunakan untuk absen hari ini.");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String lat;
      String long;

      if (jenisKehadiran == 'Hadir') {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) Navigator.pop(context);
          _showErrorDialog("GPS/Layanan lokasi nonaktif. Silakan aktifkan GPS Anda.");
          return;
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (mounted) Navigator.pop(context);
          _showErrorDialog(
            "Izin lokasi ditolak. Aktifkan izin lokasi terlebih dahulu.",
          );
          return;
        }

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lat = pos.latitude.toString();
        long = pos.longitude.toString();
      } else {
        lat = '';
        long = '';
      }

      await DbHelper().simpanAbsen(
        _guruTerpilih!['nama']!,
        lat,
        long,
        deviceId,
        nip: _guruTerpilih!['nip'],
        sekolah: _guruTerpilih!['sekolah'],
        jenisKehadiran: jenisKehadiran,
      );

      if (mounted) Navigator.pop(context);

      final snackText = jenisKehadiran == 'Hadir'
          ? "BERHASIL! Data tersimpan offline & Lokasi tercatat."
          : "BERHASIL! Data tersimpan offline (status: $jenisKehadiran).";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green[700],
          content: Text(snackText),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      setState(() {
        _guruTerpilih = null;
        _searchController.clear();
        _searchQuery = '';
      });

      await DbHelper().sinkronisasiData();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (jenisKehadiran == 'Hadir') {
        _showErrorDialog("Gagal mengambil lokasi. Pastikan GPS aktif.");
      } else {
        _showErrorDialog("Gagal menyimpan data. Coba lagi.");
      }
    }
  }

  Widget _statusOutlineButton(String label, String jenisKehadiran) {
    final blue = Colors.blue[800]!;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: () => _prosesAbsen(jenisKehadiran: jenisKehadiran),
        style: OutlinedButton.styleFrom(
          foregroundColor: blue,
          backgroundColor: Colors.white,
          side: BorderSide(color: blue, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.center,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _statusTanpaGpsBar() {
    final blue = Colors.blue[800]!;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: blue.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Status lain (tanpa GPS)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _statusOutlineButton('Sakit', 'Sakit')),
                  const SizedBox(width: 6),
                  Expanded(child: _statusOutlineButton('Izin', 'Izin')),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _statusOutlineButton(
                      'Tugas\nDinas',
                      'Tugas Dinas',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Peringatan"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasilFilter = _daftarGuru
        .where((g) => (g['nama'] ?? '').toLowerCase().contains(_searchQuery))
        .take(20)
        .toList();

    final isSudahLewatWaktu = DateTime.now().hour >= 9;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[800],
        elevation: 0,
        toolbarHeight: 80,
        title: Row(
          children: [
            Image.asset(
              'assets/logo_dinas.png',
              height: 45,
              errorBuilder: (c, e, s) =>
                  const Icon(Icons.school, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "DINAS PENDIDIKAN DAN KEBUDAYAAN KABUPATEN TTS",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "DAFTAR HADIR GURU",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[800],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: "Cari Nama Anda...",
                      prefixIcon: Icon(Icons.search, color: Colors.blue[800]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                      });
                    },
                  ),
                  if (_searchQuery.isNotEmpty) const SizedBox(height: 10),
                  if (_searchQuery.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: hasilFilter.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text("Nama tidak ditemukan."),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: hasilFilter.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final g = hasilFilter[index];
                                return ListTile(
                                  title: Text(g['nama'] ?? '-'),
                                  subtitle: Text(
                                    "NIP: ${g['nip'] ?? '-'} | ${g['sekolah'] ?? '-'}",
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _guruTerpilih = g;
                                      _searchController.text = g['nama'] ?? '';
                                      _searchQuery =
                                          (g['nama'] ?? '').toLowerCase();
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  if (_guruTerpilih != null) ...[
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Text(
                              "Nama Dipilih:",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _guruTerpilih!['nama'] ?? '-',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              "NIP: ${_guruTerpilih!['nip'] ?? '-'}",
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              _guruTerpilih!['sekolah'] ?? '-',
                              style: const TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Divider(color: Colors.blue[200]),
                            if (isSudahLewatWaktu)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  "MAAF, PENGISIAN DAFTAR HADIR SUDAH DITUTUP (BATAS 09.00)",
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 65,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSudahLewatWaktu ? Colors.grey : Colors.blue[800],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        onPressed: isSudahLewatWaktu ? () => _showErrorDialog("Pengisian sudah ditutup (lewat 09.00).") : () => _prosesAbsen(),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app, size: 28),
                            SizedBox(width: 15),
                            Text(
                              "ISI DAFTAR HADIR SEKARANG",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isSudahLewatWaktu) _statusTanpaGpsBar(),
                  ] else ...[
                    const SizedBox(height: 36),
                    Icon(Icons.group_add, size: 100, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text(
                      "Silakan cari nama Anda pada kotak di atas.",
                      style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // Logo/banner bawah — kecil & rapat agar minim scroll
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/banner_bawah.png',
                    width: 120,
                    height: 40,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.grey[200],
                        child: const Text(
                          "Gambar bawah tidak ditemukan",
                          style: TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}