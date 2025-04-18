import 'package:flutter/material.dart';
import 'package:app_usage/app_usage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

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
  DateTime? selectedDate;
  bool isLoading = false;
  final AppUsage appUsage = AppUsage();

  @override
  void initState() {
    super.initState();
    getDeviceId();
  }

  Future<void> getDeviceId() async {
    setState(() => isLoading = true);
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    setState(() {
      deviceId = androidInfo.id;
      setState(() => isLoading = false);
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
    setState(() => isLoading = true);
    try {
      // By default, fetch usage for the entire previous day (yesterday)
      final now = selectedDate ?? DateTime.now().subtract(Duration(days: 1));
      final startDate = DateTime(now.year, now.month, now.day);
      final endDate = startDate.add(Duration(days: 1)).subtract(Duration(seconds: 1));

      List<AppUsageInfo> infoList =
          await appUsage.getAppUsage(startDate, endDate);
      List<String> newLogs = infoList
          .map((info) =>
              '${info.packageName} used for ${info.usage.inMinutes} minutes on ${startDate.toIso8601String().split("T")[0]}')
          .toList();
      Box logBox = Hive.box('logs');
      await logBox.clear();
      for (var log in newLogs) {
        logBox.add(log);
      }
      setState(() {
        logs = logBox.values.cast<String>().toList();
        logDate = startDate.toIso8601String().split("T")[0];
      });
    } catch (e) {
      await checkUsagePermission();
      print("Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> sendLogsToServer() async {
    setState(() => isLoading = true);
    var headers = {
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
    try {
      if (response.statusCode == 200) {
            final Map<String, dynamic> jsonBody = jsonDecode(response.body);
            final formattedResponse = jsonBody["response"]
                .toString()
                .replaceAll(r'\n', '\n')
                .replaceAll(r'\"', '"')
                .replaceAll(r'\:', ':')
                .replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!);

            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text("Success"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$formattedResponse"),
                    ]
                  )
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: response.body));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Copied to clipboard")),
                      );
                    },
                    child: Text("Copy to Clipboard"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text("OK"),
                  ),
                ],
              ),
            );
          /*if (response.statusCode == 200) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text("Logs sent successfully")));*/
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text("Failed to send logs: ${response.body}")));
            print("Failed to send logs: ${response.body}");
          }
    } finally {
      setState(() => isLoading = false);
    }
    
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now().subtract(Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _copyLogsToClipboard() {
    final logText = logs.join("\n");
    Clipboard.setData(ClipboardData(text: logText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Logs copied to clipboard")),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final logBox = Hive.box('logs');
    logs = logBox.values.cast<String>().toList();
    return Scaffold(
      appBar: AppBar(title: Text('User Activity Logger')),
      body: Stack(
        children: [
          Column(
            children: [
              if (deviceId != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Device ID: $deviceId'),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _pickDate(context),
                      child: Text('Pick Date'),
                    ),
                    SizedBox(width: 12),
                    Text(
                      selectedDate != null
                          ? '${selectedDate!.toIso8601String().split("T")[0]}'
                          : 'No date selected',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: (isLoading || selectedDate == null) ? null : fetchUsage,
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(MaterialState.disabled)) {
                            return Colors.grey;
                          }
                          return null;
                        }),
                      ),
                      child: Text('Fetch Usage'),
                    ),
                  ],
                ),
              ),
              Row(
                  children: [
                    if (logDate != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'Log Date: $logDate',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: (isLoading || logDate == null ) ? null : sendLogsToServer,
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
                    TextButton(
                      onPressed: _copyLogsToClipboard,
                      child: Text("Copy Logs"),
                    ),
                  ]
              ),
              SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(logs[index]),
                  ),
                ),
              ),
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ],
          ),
        ]
      )
    );
  }
}
