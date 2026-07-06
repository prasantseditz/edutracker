import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:edutracker/services/smart_notification_service.dart';
import 'package:edutracker/services/achievement_service.dart';

// Fake FlutterLocalNotificationsPlugin for testing
class FakeFlutterLocalNotificationsPlugin extends Fake implements FlutterLocalNotificationsPlugin {
  final List<Map<String, dynamic>> showCalls = [];
  final List<Map<String, dynamic>> zonedScheduleCalls = [];
  final List<int> cancelCalls = [];

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    showCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'notificationDetails': notificationDetails,
      'payload': payload,
    });
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {
    zonedScheduleCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'scheduledDate': scheduledDate,
      'notificationDetails': notificationDetails,
      'androidScheduleMode': androidScheduleMode,
      'matchDateTimeComponents': matchDateTimeComponents,
      'payload': payload,
    });
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelCalls.add(id);
  }
}

void main() {
  late FakeFlutterLocalNotificationsPlugin fakePlugin;
  late Directory tempDir;

  setUp(() async {
    // Initialize timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));

    // Set up mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Set up mock Hive
    tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);

    // Instantiate Fake Plugin
    fakePlugin = FakeFlutterLocalNotificationsPlugin();

    // Inject Fake Plugin
    SmartNotificationService.instance.mockPlugin = fakePlugin;
    AchievementService.instance.mockPlugin = fakePlugin;
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AchievementService Tests', () {
    test('checkStudentMilestones - fires achievement on 1st student', () async {
      await AchievementService.instance.checkStudentMilestones(1);
      
      expect(fakePlugin.showCalls.length, 1);
      expect(fakePlugin.showCalls[0]['id'], 6001);
      expect(fakePlugin.showCalls[0]['title'], 'Student Added 👨‍🎓');
      expect(fakePlugin.showCalls[0]['body'], 'Congratulations! You added your first student.');

      // Check that it doesn't fire again
      fakePlugin.showCalls.clear();
      await AchievementService.instance.checkStudentMilestones(1);
      expect(fakePlugin.showCalls.length, 0);
    });

    test('checkStudentMilestones - fires achievement on 10, 50, 100 students', () async {
      await AchievementService.instance.checkStudentMilestones(10);
      expect(fakePlugin.showCalls[0]['id'], 6010);

      fakePlugin.showCalls.clear();
      await AchievementService.instance.checkStudentMilestones(50);
      expect(fakePlugin.showCalls[0]['id'], 6050);

      fakePlugin.showCalls.clear();
      await AchievementService.instance.checkStudentMilestones(100);
      expect(fakePlugin.showCalls[0]['id'], 6100);
    });

    test('checkBatchMilestones - fires on 1st batch', () async {
      await AchievementService.instance.checkBatchMilestones(1);
      expect(fakePlugin.showCalls[0]['id'], 7001);
      expect(fakePlugin.showCalls[0]['title'], 'Batch Created 🏅');
    });

    test('checkPaymentMilestones - fires on 1st and 100th payment', () async {
      await AchievementService.instance.checkPaymentMilestones(1);
      expect(fakePlugin.showCalls[0]['id'], 8001);

      fakePlugin.showCalls.clear();
      await AchievementService.instance.checkPaymentMilestones(100);
      expect(fakePlugin.showCalls[0]['id'], 8100);
    });

    test('triggerAppLockReminder - fires reminder', () async {
      await AchievementService.instance.triggerAppLockReminder();
      expect(fakePlugin.showCalls[0]['id'], 9001);
      expect(fakePlugin.showCalls[0]['title'], 'Security Alert 🔒');
    });

    // Disabled test as per user request to stop backup notifications
    // test('triggerBackupSuccess & triggerBackupError - fires notifications directly', () async {
    //   await AchievementService.instance.triggerBackupSuccess();
    //   expect(fakePlugin.showCalls[0]['id'], 9002);

    //   fakePlugin.showCalls.clear();
    //   await AchievementService.instance.triggerBackupError();
    //   expect(fakePlugin.showCalls[0]['id'], 9003);
    // });
  });

  group('SmartNotificationService Tests', () {
    test('scheduleDailyReminder - schedules daily reminder successfully', () async {
      await SmartNotificationService.instance.scheduleDailyReminder();
      
      expect(fakePlugin.zonedScheduleCalls.length, 7);
      final call = fakePlugin.zonedScheduleCalls[0];
      expect(call['id'], 5001);
      expect(call['title'], 'Good Morning! 🌞');
      expect(call['body'], isNotNull);
    });

    test('scheduleEveningReminder - schedules evening reminder successfully', () async {
      await SmartNotificationService.instance.scheduleEveningReminder();
      
      expect(fakePlugin.zonedScheduleCalls.length, 7);
      final call = fakePlugin.zonedScheduleCalls[0];
      expect(call['id'], 5101);
      expect(call['title'], 'Good Evening! 🌙');
      expect(call['body'], isNotNull);
    });

    test('scheduleWeeklyReminder - schedules weekly reminder successfully', () async {
      await SmartNotificationService.instance.scheduleWeeklyReminder();
      
      expect(fakePlugin.zonedScheduleCalls.length, 1);
      final call = fakePlugin.zonedScheduleCalls[0];
      expect(call['id'], 2002);
      expect(call['title'], 'Weekly Update 📅');
      expect(call['matchDateTimeComponents'], DateTimeComponents.dayOfWeekAndTime);
    });

    test('scheduleMonthlyReminders - schedules monthly reminders successfully', () async {
      await SmartNotificationService.instance.scheduleMonthlyReminders();
      
      expect(fakePlugin.zonedScheduleCalls.length, 4);
      final ids = fakePlugin.zonedScheduleCalls.map((c) => c['id'] as int).toList();
      expect(ids, containsAll([2003, 2004, 2005, 2006]));
    });

    test('scheduleInactiveReminders & cancelInactiveReminders - lifecycle helpers', () async {
      await SmartNotificationService.instance.scheduleInactiveReminders();
      expect(fakePlugin.zonedScheduleCalls.length, 4);
      final ids = fakePlugin.zonedScheduleCalls.map((c) => c['id'] as int).toList();
      expect(ids, containsAll([3003, 3007, 3015, 3030]));

      await SmartNotificationService.instance.cancelInactiveReminders();
      expect(fakePlugin.cancelCalls.length, 4);
      expect(fakePlugin.cancelCalls, containsAll([3003, 3007, 3015, 3030]));
    });

    test('checkFeatureBasedReminders - no batches', () async {
      await Hive.openBox('batches');
      await Hive.openBox('students');

      await SmartNotificationService.instance.checkFeatureBasedReminders();
      expect(fakePlugin.showCalls.length, 1);
      expect(fakePlugin.showCalls[0]['id'], 5002);
      expect(fakePlugin.showCalls[0]['title'], 'No Batches Yet 📚');
    });
  });
}
