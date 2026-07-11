import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/student.dart';
import '../models/batch.dart';
import 'notification_service.dart';

class SmartNotificationService {
  SmartNotificationService._internal();
  static final SmartNotificationService instance = SmartNotificationService._internal();

  final _channelId = 'smart_reminders_channel';
  final _channelName = 'Smart Reminders';
  final _channelDesc = 'Reminders and tips for managing tuition';

  NotificationDetails get _notificationDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: const BigTextStyleInformation(''),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      );

  FlutterLocalNotificationsPlugin? _mockPlugin;
  FlutterLocalNotificationsPlugin get _plugin => _mockPlugin ?? NotificationService.instance.localNotifications;
  
  set mockPlugin(FlutterLocalNotificationsPlugin plugin) => _mockPlugin = plugin;

  /// IDs for scheduled notifications to avoid overlap
  static const int _dailyReminderBaseId = 5000;
  static const int _eveningReminderBaseId = 5100;
  static const int _weeklyReminderId = 2002;
  static const int _monthly1stReminderId = 2003;
  static const int _monthly10thReminderId = 2004;
  static const int _monthly20thReminderId = 2005;
  static const int _monthly28thReminderId = 2006;
  
  static const int _inactive3DaysId = 3003;
  static const int _inactive7DaysId = 3007;
  static const int _inactive15DaysId = 3015;
  static const int _inactive30DaysId = 3030;

  static const int _dueReminderId = 4001;
  
  Future<void> initSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Feature: First Login Notification
    bool hasLoggedInBefore = prefs.getBool('first_login_done') ?? false;
    if (!hasLoggedInBefore) {
      await _showImmediateNotification(
        id: 5001,
        title: 'Welcome!',
        body: 'Start by creating your first Batch.',
      );
      await prefs.setBool('first_login_done', true);
    }

    await scheduleDailyReminder();
    await scheduleEveningReminder();
    await scheduleWeeklyReminder();
    await scheduleMonthlyReminders();
    await scheduleDueReminders();
    
    // Initial check for features
    await checkFeatureBasedReminders();
  }

  Future<void> _showImmediateNotification({required int id, required String title, required String body, String? payload}) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notificationDetails,
      payload: payload,
    );
  }

  Future<void> scheduleDailyReminder() async {
    // 1. Cancel previous daily reminders first to prevent duplicates (IDs 5001 to 5007)
    for (int i = 1; i <= 7; i++) {
      await _plugin.cancel(id: _dailyReminderBaseId + i);
    }

    // 2. Fetch User Name from local settings or Google profile
    String name = 'Teacher';
    if (Hive.isBoxOpen('settings')) {
      final settingsBox = Hive.box('settings');
      final String? localName = settingsBox.get('name');
      final String? googleName = FirebaseAuth.instance.currentUser?.displayName?.split(' ').first;
      name = localName ?? googleName ?? 'Teacher';
    }

    // 3. Define the 7 fun, morning greeting messages in English
    final List<String> dailyMessages = [
      "Good morning, $name! ☕ Your coffee is hot, and those fee records are waiting. Let's keep EduTracker updated before classes start!",
      "Rise and shine, $name! ☀️ A fresh day means fresh logs. Quick check: are all student fee payments recorded in EduTracker?",
      "Good morning, $name! 🚀 Time to be a fee superhero today. Open EduTracker and make sure no student dues are left behind!",
      "Morning, $name! 🍎 Teaching is a work of heart, and tracking fees is a work of smart. Let's update those collections in EduTracker!",
      "Good morning, $name! 👋 Hope you slept well. Don't let pending dues pile up like grading papers—log them in EduTracker now!",
      "Rise and grind, $name! 🎯 A tidy dashboard leads to a peaceful mind. Let's take 2 minutes to keep all student fees up-to-date!",
      "Good morning, $name! 🌟 Let's start the morning with a clean slate and a clean ledger. Update your dues on EduTracker!"
    ];

    final now = tz.TZDateTime.now(tz.local);

    // 4. Schedule reminders for the next 7 days
    for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + dayOffset,
        7,  // Hour: 3 PM
        0,  // Minute: 7
        0,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }

      // Select message based on the weekday of the scheduled date (1 to 7)
      // This guarantees no consecutive repeats and a 6-day gap between identical messages!
      final int msgIndex = (scheduledDate.weekday - 1) % dailyMessages.length;
      final String message = dailyMessages[msgIndex];

      await _plugin.zonedSchedule(
        id: _dailyReminderBaseId + dayOffset + 1,
        title: 'Good Morning! 🌞',
        body: message,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '/batches',
      );
      if (kDebugMode) {
        print('>>> Daily Reminder Day ${dayOffset + 1} scheduled for: $scheduledDate');
      }
    }
  }

  Future<void> scheduleEveningReminder() async {
    // 1. Cancel previous evening reminders first to prevent duplicates (IDs 5101 to 5107)
    for (int i = 1; i <= 7; i++) {
      await _plugin.cancel(id: _eveningReminderBaseId + i);
    }

    // 2. Fetch User Name
    String name = 'Teacher';
    if (Hive.isBoxOpen('settings')) {
      final settingsBox = Hive.box('settings');
      final String? localName = settingsBox.get('name');
      final String? googleName = FirebaseAuth.instance.currentUser?.displayName?.split(' ').first;
      name = localName ?? googleName ?? 'Teacher';
    }

    // 3. Define the 7 fun evening greeting messages in English
    final List<String> eveningMessages = [
      "Good evening, $name! 🌆 Classes are done for the day! Let's wrap up by updating any pending payments in EduTracker before relaxing.",
      "Hey $name, hope you had a productive day! 📚 Don't let today's collections slip your mind. Quick update on EduTracker, and you're good to go!",
      "Good evening, $name! 🌙 Quick question: Did that last-minute student pay? Log it in EduTracker now so your reports stay crystal clear!",
      "Evening, $name! ☕ Put your feet up, but first, put those fee updates in! A few taps on EduTracker will save you tomorrow's headache.",
      "Good evening, $name! 🎯 Teach, track, triumph! Let's make sure today's tuition entries are all tidy in EduTracker. Sleep easy tonight!",
      "Hey $name! 🌟 Wrap up your day like a pro. Keep your ledgers updated in EduTracker so your dashboard always shows accurate earnings!",
      "Good evening, $name! 📅 Another day, another step closer to fee-collection zen. Update today's records on EduTracker and enjoy your night!"
    ];

    final now = tz.TZDateTime.now(tz.local);

    // 4. Schedule reminders for the next 7 days at 7:30 PM (19:30)
    for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + dayOffset,
        19, // Hour: 7 PM (19:00)
        30, // Minute: 30 (7:30 PM)
        0,
      );

      // If the time has already passed today, schedule for next week
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }

      final int msgIndex = (scheduledDate.weekday - 1) % eveningMessages.length;
      final String message = eveningMessages[msgIndex];

      await _plugin.zonedSchedule(
        id: _eveningReminderBaseId + dayOffset + 1,
        title: 'Good Evening! 🌙',
        body: message,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '/batches',
      );
      if (kDebugMode) {
        print('>>> Evening Reminder Day ${dayOffset + 1} scheduled for: $scheduledDate');
      }
    }
  }

  Future<void> scheduleWeeklyReminder() async {
    final List<String> weeklyMessages = [
      "Check out this week's Payment Report.",
      "Any Student information left to update?",
      "Check the list of students with Fee Dues."
    ];
    final randomMsg = weeklyMessages[Random().nextInt(weeklyMessages.length)];
    
    // Schedule for next Sunday 10 AM
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 10);
    while (scheduledDate.weekday != DateTime.sunday || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: _weeklyReminderId,
      title: 'Weekly Update 📅',
      body: randomMsg,
      scheduledDate: scheduledDate,
      notificationDetails: _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Repeat weekly
      payload: '/history',
    );
  }

  Future<void> scheduleMonthlyReminders() async {
    final now = tz.TZDateTime.now(tz.local);
    
    void scheduleForDay(int day, int id, String title, String body) async {
      tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, day, 10, 0);
      if (scheduledDate.isBefore(now)) {
        final nextMonth = now.month == 12 ? 1 : now.month + 1;
        final nextYear = now.month == 12 ? now.year + 1 : now.year;
        scheduledDate = tz.TZDateTime(tz.local, nextYear, nextMonth, day, 10, 0);
      }
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        payload: '/due-details',
      );
    }

    scheduleForDay(1, _monthly1stReminderId, 'New Month 🎉', 'A new month has started! Begin your fee collection for this month.');
    scheduleForDay(10, _monthly10thReminderId, 'Fee Dues Check 💰', 'Some students haven\'t paid fees yet. Check your Due List.');
    scheduleForDay(20, _monthly20thReminderId, 'Month End Approaching ⏰', 'Complete due collections before the month ends.');
    scheduleForDay(28, _monthly28thReminderId, 'Monthly Report 📊', 'Prepare your monthly report. Check your total collected amount.');
  }

  /// App Lifecycle - When app goes to background
  Future<void> scheduleInactiveReminders() async {
    final now = tz.TZDateTime.now(tz.local);

    void scheduleInactive(int days, int id, String body) async {
      final scheduledDate = now.add(Duration(days: days));
      await _plugin.zonedSchedule(
        id: id,
        title: 'Miss you! 👋',
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '/batches',
      );
    }

    scheduleInactive(3, _inactive3DaysId, "It's been a while! Take a quick look at the app.");
    scheduleInactive(7, _inactive7DaysId, "Your Dashboard is waiting for you.");
    scheduleInactive(15, _inactive15DaysId, "No updates for a long time.");
    scheduleInactive(30, _inactive30DaysId, "Welcome back! Your data is safely stored.");
  }

  /// App Lifecycle - When app comes to foreground
  Future<void> cancelInactiveReminders() async {
    await _plugin.cancel(id: _inactive3DaysId);
    await _plugin.cancel(id: _inactive7DaysId);
    await _plugin.cancel(id: _inactive15DaysId);
    await _plugin.cancel(id: _inactive30DaysId);
  }

  Future<void> checkFeatureBasedReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFeatureNotice = prefs.getString('last_feature_notice_date');
    final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    
    // Only fire feature reminders once a day maximum
    if (lastFeatureNotice == todayStr) return;

    if (!Hive.isBoxOpen('batches')) return;
    
    Box batchBox;
    try {
      batchBox = Hive.box<Batch>('batches');
    } catch (_) {
      try {
        batchBox = Hive.box('batches');
      } catch (_) {
        return;
      }
    }

    if (batchBox.isEmpty) {
      await _showImmediateNotification(
        id: 5002,
        title: 'No Batches Yet 📚',
        body: 'No batches created yet. Create a Batch now!',
        payload: '/create-batch',
      );
      await prefs.setString('last_feature_notice_date', todayStr);
      return; // Only show one feature reminder per day
    }

    if (Hive.isBoxOpen('students')) {
      Box studentBox;
      try {
        studentBox = Hive.box<Student>('students');
      } catch (_) {
        try {
          studentBox = Hive.box('students');
        } catch (_) {
          return;
        }
      }

      if (studentBox.isEmpty && batchBox.isNotEmpty) {
         await _showImmediateNotification(
          id: 5003,
          title: 'Add Students 👨‍🎓',
          body: 'Add your first Student to begin Tuition Management.',
          payload: '/add-student',
        );
        await prefs.setString('last_feature_notice_date', todayStr);
      }
    }
  }

  Future<void> scheduleDueReminders() async {
    if (!Hive.isBoxOpen('students')) return;
    
    // Due calculation
    Box studentBox;
    try {
      studentBox = Hive.box<Student>('students');
    } catch (_) {
      try {
        studentBox = Hive.box('students');
      } catch (_) {
        return;
      }
    }

    double totalDue = 0;
    int dueCount = 0;
    
    for (final element in studentBox.values) {
      if (element == null) continue;
      if (element is Student) {
        if (!element.feesPaid) {
          dueCount++;
          totalDue += element.monthlyFees;
        }
      } else {
        // Fallback for map type in dynamic box tests
        final map = element as Map;
        final fees = map['fees'] ?? [];
        for (var f in fees) {
          if (f['status'] == 'Due' || f['status'] == 'Partial') {
            totalDue += (f['dueAmount'] ?? 0);
          }
        }
        if (map['dueAmount'] != null && map['dueAmount'] > 0) {
          dueCount++;
        }
      }
    }

    if (dueCount > 0) {
      // Show immediately when app opens (since we don't have background workmanager)
      // but debounce it so it doesn't show every single time they open the app today.
      final prefs = await SharedPreferences.getInstance();
      final lastDueNotice = prefs.getString('last_due_notice_date');
      final todayStr = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
      
      if (lastDueNotice != todayStr) {
        await _showImmediateNotification(
          id: _dueReminderId,
          title: 'Fee Dues Reminder 💰',
          body: 'You have $dueCount students with Fee Dues. Total Due Amount is ₹${totalDue.toStringAsFixed(0)}.',
          payload: '/due-details',
        );
        await prefs.setString('last_due_notice_date', todayStr);
      }
    }
  }
}
