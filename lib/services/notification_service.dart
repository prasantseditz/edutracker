import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../app_globals.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print("Handling background message: ${message.messageId}");
  }
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Initialize notifications and set up listeners
  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Initialize Timezone database
    tz.initializeTimeZones();
    // Default to local/device timezone
    // timezone package's local is configured automatically inside initializeTimeZones()
    
    // 2. Local Notifications Initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    // 3. Initialize Local Notifications Plugin
    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationClick(response.payload);
      },
    );

    // Create high importance notification channels on Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // 4. Configure Firebase Cloud Messaging (FCM)
    await _initFirebaseMessaging();

    // 5. Schedule recurring local notification timers (Monthly Fee check, etc.)
    await scheduleMonthlyDueReminder();
    await scheduleMidMonthDuesReminder();

    _isInitialized = true;
    if (kDebugMode) {
      print("NotificationService initialized successfully.");
    }
  }

  /// Request runtime permissions for notifications (Android 13+ and iOS)
  Future<bool> requestPermissions() async {
    // 1. Request local notification permissions
    bool? localPermission = false;
    if (Platform.isAndroid) {
      localPermission = await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      localPermission = await _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // 2. Request FCM permissions
    final NotificationSettings fcmSettings =
        await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final bool isGranted = localPermission == true ||
        fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
        fcmSettings.authorizationStatus == AuthorizationStatus.provisional;

    return isGranted;
  }

  /// Setup high importance channels for Android
  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel duesChannel = AndroidNotificationChannel(
      'dues_reminders_channel',
      'Fee Dues Reminders',
      description: 'Reminders for checking monthly student fee dues',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel backupChannel = AndroidNotificationChannel(
      'backup_reminders_channel',
      'Backup Sync Warnings',
      description: 'Reminders to sync local data to Firebase',
      importance: Importance.high,
      playSound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(duesChannel);
      await androidImplementation.createNotificationChannel(backupChannel);
    }
  }

  /// Initialize Firebase Messaging listeners
  Future<void> _initFirebaseMessaging() async {
    // Register background messaging handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Configure foreground messaging: Show a local notification when an FCM is received in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (kDebugMode) {
        print("FCM message received in foreground: ${message.notification?.title}");
      }
      final RemoteNotification? notification = message.notification;
      final AndroidNotification? android = message.notification?.android;

      if (notification != null) {
        await _localNotifications.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'dues_reminders_channel',
              'Fee Dues Reminders',
              channelDescription: 'Reminders for checking monthly student fee dues',
              importance: Importance.max,
              priority: Priority.high,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              presentBadge: true,
            ),
          ),
          payload: message.data['screen'] ?? 'due-details',
        );
      }
    });

    // Handle background notification clicks that open the app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        print("FCM message clicked: ${message.data}");
      }
      _handleNotificationClick(message.data['screen']);
    });

    // Check if the app was opened from a terminated state via a notification
    final RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationClick(initialMessage.data['screen']);
    }

    // Subscribe to general announcements topic
    try {
      await FirebaseMessaging.instance.subscribeToTopic('announcements');
      if (kDebugMode) {
        print("Subscribed to announcements FCM topic");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Failed to subscribe to FCM announcements topic: $e");
      }
    }
  }

  /// Handles page routing when a user clicks a notification
  void _handleNotificationClick(String? payload) {
    if (payload == null) return;
    
    // We add a short delay to ensure the navigation stack is fully ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (payload == 'due-details') {
        rootNavigatorKey.currentState?.pushNamed('/due-details');
      } else if (payload == 'subscribe') {
        rootNavigatorKey.currentState?.pushNamed('/subscribe');
      } else if (payload == 'settings') {
        rootNavigatorKey.currentState?.pushNamed('/settings');
      }
    });
  }

  /// Gets the FCM device token to register on Firestore
  Future<String?> getDeviceToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      if (kDebugMode) {
        print("Error getting FCM device token: $e");
      }
      return null;
    }
  }

  // ==========================================
  // LOCAL SCHEDULING METHODS
  // ==========================================

  /// Schedules a monthly dues reminder for the 1st of every month at 9:00 AM
  Future<void> scheduleMonthlyDueReminder() async {
    const int monthlyReminderId = 1001;

    // Get current time in local timezone
    final now = tz.TZDateTime.now(tz.local);
    
    // Target 1st of this month
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, 1, 9, 0);
    // If the 1st of this month has already passed, schedule for the 1st of next month
    if (scheduledDate.isBefore(now)) {
      scheduledDate = tz.TZDateTime(tz.local, now.year, now.month + 1, 1, 9, 0);
    }

    await _localNotifications.zonedSchedule(
      id: monthlyReminderId,
      title: 'Monthly Fee Due Reminder 📅',
      body: 'It\'s the start of the month! Check which students have dues pending.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'dues_reminders_channel',
          'Fee Dues Reminders',
          channelDescription: 'Reminders for checking monthly student fee dues',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      payload: 'due-details',
    );
    
    if (kDebugMode) {
      print("Scheduled monthly due reminder for: $scheduledDate");
    }
  }

  /// Schedules a mid-month dues follow-up reminder for the 15th of every month at 10:00 AM
  Future<void> scheduleMidMonthDuesReminder() async {
    const int midMonthReminderId = 1002;

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, 15, 10, 0);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = tz.TZDateTime(tz.local, now.year, now.month + 1, 15, 10, 0);
    }

    await _localNotifications.zonedSchedule(
      id: midMonthReminderId,
      title: 'Outstanding Dues Check 💰',
      body: 'Mid-month check: Review and update student payment records.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'dues_reminders_channel',
          'Fee Dues Reminders',
          channelDescription: 'Reminders for checking monthly student fee dues',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      payload: 'due-details',
    );

    if (kDebugMode) {
      print("Scheduled mid-month due reminder for: $scheduledDate");
    }
  }

  /// Sets an alarm to fire 5 days in the future warning the user that a backup is pending.
  /// This should be reset every time a Firestore sync succeeds.
  Future<void> resetBackupReminder() async {
    const int backupReminderId = 1003;

    // 1. Cancel the previous scheduled backup warning
    await _localNotifications.cancel(id: backupReminderId);

    // 2. Schedule a new one for 5 days from now
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(const Duration(days: 5));

    await _localNotifications.zonedSchedule(
      id: backupReminderId,
      title: 'Backup Sync Pending ☁️',
      body: 'You haven\'t backed up your batch records in 5 days. Sync now to protect your data.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'backup_reminders_channel',
          'Backup Sync Warnings',
          channelDescription: 'Reminders to sync local data to Firebase',
          importance: Importance.high,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'settings',
    );

    if (kDebugMode) {
      print("Reset backup sync reminder. Next reminder on: $scheduledDate");
    }
  }

  /// Cancels the backup sync reminder (e.g. if the user turns off sync or logs out)
  Future<void> cancelBackupReminder() async {
    const int backupReminderId = 1003;
    await _localNotifications.cancel(id: backupReminderId);
    if (kDebugMode) {
      print("Cancelled backup sync reminder.");
    }
  }
}
