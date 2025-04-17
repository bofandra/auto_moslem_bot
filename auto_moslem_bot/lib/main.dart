import 'package:flutter/material.dart';
import 'package:app_usage/app_usage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);
  await Hive.openBox('logs');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LogScreen(),
    );
  }
}

class LogScreen extends StatefulWidget {
  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<String> logs = [];
  String? deviceId;
  String? logDate;
  final AppUsage appUsage = AppUsage();

  @override
  void initState() {
    super.initState();
    getDeviceId();
  }

  Future<void> getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    setState(() {
      deviceId = androidInfo.id;
    });
  }

  Future<void> checkUsagePermission() async {
    if (Platform.isAndroid) {
      const intent = AndroidIntent(
        action: 'android.settings.USAGE_ACCESS_SETTINGS',
      );
      await intent.launch();
    }
  }

  Future<void> fetchUsage() async {
    await checkUsagePermission();
    try {
      // Fetch usage for the entire previous day (yesterday)
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day).subtract(Duration(days: 1));
      final startDate = yesterday;
      final endDate = DateTime(now.year, now.month, now.day).subtract(Duration(seconds: 1));

      List<AppUsageInfo> infoList =
          await appUsage.getAppUsage(startDate, endDate);
      List<String> newLogs = infoList
          .map((info) =>
              '${info.packageName} used for ${info.usage.inMinutes} minutes on ${startDate.toIso8601String().split("T")[0]}')
          .toList();
      Box logBox = Hive.box('logs');
      for (var log in newLogs) {
        logBox.add(log);
      }
      setState(() {
        logs = logBox.values.cast<String>().toList();
        logDate = startDate.toIso8601String().split("T")[0];
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> sendLogsToServer() async {
    var headers = {
      'X-API-Key': "a9ba6e3a-3179-44c3-a9ca-54bb641e9be3",
      'Access-Control-Allow-Origin': '*',
      'Content-Type': 'application/json',
      'Accept': '*/*'
    };
    final logBox = Hive.box('logs');
    final logData = logBox.values.cast<String>().toList();

    if (deviceId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Device ID not ready yet")));
      return;
    }

    final response = await http.post(
      Uri.parse("https://bofandra.pythonanywhere.com/upload_logs"),
      headers: headers,
      body: jsonEncode({
        "device_id": deviceId,
        "logs": logData,
        "log_date": logDate ?? "unknown"
      }),
    );
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Logs sent successfully")));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to send logs: ${response.body}")));
      print("Failed to send logs: ${response.body}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final logBox = Hive.box('logs');
    logs = logBox.values.cast<String>().toList();
    return Scaffold(
      appBar: AppBar(title: Text('User Activity Logger')),
      body: Column(
        children: [
          if (deviceId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Device ID: $deviceId'),
            ),
          if (logDate != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Log Date: $logDate',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
            ),
          ElevatedButton(
            onPressed: fetchUsage,
            child: Text('Fetch Usage'),
          ),
          ElevatedButton(
            onPressed: logDate == null ? null : sendLogsToServer,
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                if (states.contains(MaterialState.disabled)) {
                  return Colors.grey;
                }
                return null; // Use the default
              }),
            ),
            child: Text('Send to Server'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(logs[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
