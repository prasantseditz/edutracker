import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';

class AchievementService {
  AchievementService._internal();
  static final AchievementService instance = AchievementService._internal();

  final _channelId = 'achievements_channel';
  final _channelName = 'Achievements';
  final _channelDesc = 'App milestones and achievements';

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

  Future<void> _checkAndFire(String key, int id, String title, String body) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) return; // Already fired

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notificationDetails,
    );
    await prefs.setBool(key, true);
  }

  // --- External Hooks ---

  Future<void> checkStudentMilestones(int studentCount) async {
    if (studentCount == 1) {
      await _checkAndFire('achieve_student_1', 6001, 'Student Added 👨‍🎓', 'Congratulations! You added your first student.');
    } else if (studentCount == 10) {
      await _checkAndFire('achieve_student_10', 6010, '10 Students! 🎉', 'Congratulations! You now have 10 Students in your coaching.');
    } else if (studentCount == 50) {
      await _checkAndFire('achieve_student_50', 6050, '50 Students! 🏆', 'Awesome! You\'ve reached 50 Students.');
    } else if (studentCount == 100) {
      await _checkAndFire('achieve_student_100', 6100, '100 Students! 🚀', 'Great job! Your coaching is growing fast with 100 Students!');
    }
  }

  Future<void> checkBatchMilestones(int batchCount) async {
    if (batchCount == 1) {
      await _checkAndFire('achieve_batch_1', 7001, 'Batch Created 🏅', 'First batch created successfully.');
    }
  }

  Future<void> checkPaymentMilestones(int paymentCount) async {
    if (paymentCount == 1) {
      await _checkAndFire('achieve_payment_1', 8001, 'Payment Added 💰', 'First payment successfully added. 🎉');
    } else if (paymentCount == 100) {
      await _checkAndFire('achieve_payment_100', 8100, '100 Payments! 🎯', '100 Payment Records completed.');
    }
  }

  Future<void> triggerAppLockReminder() async {
    await _plugin.show(
      id: 9001,
      title: 'Security Alert 🔒',
      body: 'Enable App Lock to secure your data.',
      notificationDetails: _notificationDetails,
    );
  }

  Future<void> triggerBackupSuccess() async {
    // Disabled as per user request
    // await _plugin.show(
    //   id: 9002,
    //   title: 'Backup Complete ☁️',
    //   body: 'All your data has been successfully backed up to the Cloud.',
    //   notificationDetails: _notificationDetails,
    // );
  }

  Future<void> triggerBackupError() async {
    // Disabled as per user request
    // await _plugin.show(
    //   id: 9003,
    //   title: 'Backup Failed ⚠️',
    //   body: 'Some data couldn\'t sync. Please check your internet connection.',
    //   notificationDetails: _notificationDetails,
    // );
  }
}
