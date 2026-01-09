// lib/services/ad_manager.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdManager {
  AdManager._privateConstructor();
  static final AdManager instance = AdManager._privateConstructor();

  // ---------- Ad Blocker Detection ----------

  /// Checks if an ad blocker or private DNS is likely blocking ads.
  /// Returns `true` if ads are blocked.
  Future<bool> detectAdBlocker() async {
    // 1. Check general internet connectivity first
    bool hasInternet = false;
    try {
      final googleIps = await InternetAddress.lookup('google.com');
      if (googleIps.isNotEmpty && googleIps[0].rawAddress.isNotEmpty) {
        hasInternet = true;
      }
    } catch (_) {
      // If we can't reach google.com, we assume offline or severe network issues.
      // In this case, we don't report "Ad Blocked" because it's just "No Internet".
      return false;
    }

    if (!hasInternet) return false;

    // 2. Try to resolve/connect to a known ad server (Google Ads)
    // If this fails while general internet works, it is likely blocked.
    try {
      final adIps = await InternetAddress.lookup('googleads.g.doubleclick.net');
      if (adIps.isNotEmpty && adIps[0].rawAddress.isNotEmpty) {
        // Further verify by attempting a quick socket connection (optional but robust)
        // We use a short timeout to avoid lag.
        final socket = await Socket.connect(adIps[0], 80,
            timeout: const Duration(seconds: 2));
        socket.destroy();
        return false; // Reachable -> No ad blocker
      }
    } catch (_) {
      // Lookup failed or connection failed -> Ad Blocker likely active
      return true;
    }

    return false;
  }

  // ---------- Configuration ----------
  static const _kRewardTimestampKey = 'reward_watched_at_ms';
  static const Duration _kBlockDuration = Duration(hours: 12);

  // TEST Ad Unit IDs (change to your real IDs before production)
  // Android: Interstitial test id, Rewarded test id
  static const String interstitialAdUnitIdAndroid =
      'ca-app-pub-3974720629399229/3274331950';
  static const String rewardedAdUnitIdAndroid =
      'ca-app-pub-3974720629399229/7269417287';
  static const String rewardedInterstitialAdUnitIdAndroid =
      'ca-app-pub-3974720629399229/3807450897';
  static const String bannerAdUnitIdAndroid =
      'ca-app-pub-3974720629399229/1692004589';

  // iOS test ids (if you publish on iOS, replace accordingly)
  static const String interstitialAdUnitIdIos =
      'ca-app-pub-3974720629399229/3274331950';
  static const String rewardedAdUnitIdIos =
      'ca-app-pub-3974720629399229/7269417287';
  static const String rewardedInterstitialAdUnitIdIos =
      'ca-app-pub-3974720629399229/3807450897';
  static const String bannerAdUnitIdIos =
      'ca-app-pub-3974720629399229/1692004589';

  // Choose correct id based on platform at runtime
  String get _interstitialAdUnitId {
    // If you only target Android for now, return Android id;
    // replace logic if you also support iOS.
    return interstitialAdUnitIdAndroid;
  }

  String get _rewardedAdUnitId {
    return rewardedAdUnitIdAndroid;
  }

  String get _rewardedInterstitialAdUnitId {
    return rewardedInterstitialAdUnitIdAndroid;
  }

  // ---------- State ----------
  InterstitialAd? _interstitialAd;
  bool _isLoadingInterstitial = false;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  void setPremium(bool value) {
    _isPremium = value;
    if (_isPremium) {
      // If switched to premium, clean up existing ads
      dispose();
    }
  }

  // Optional: keep reference to last load failure attempts to backoff
  int _interstitialLoadAttempts = 0;
  final int _maxLoadAttempts = 3;

  // ---------- Initialization ----------
  /// Call this once (e.g. after MobileAds.instance.initialize()).
  Future<void> init() async {
    // Preload one interstitial
    loadInterstitial();
  }

  // ---------- Persistence helpers ----------
  Future<void> _setRewardTimestampNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _kRewardTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<int?> _getRewardTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kRewardTimestampKey);
  }

  /// Returns `true` if interstitials are allowed (i.e. no recent reward within block duration)
  Future<bool> canShowInterstitial() async {
    if (_isPremium) return false; // Premium users don't see ads

    final ts = await _getRewardTimestamp();
    if (ts == null) return true;
    final watchedAt = DateTime.fromMillisecondsSinceEpoch(ts);
    final diff = DateTime.now().difference(watchedAt);
    return diff >= _kBlockDuration;
  }

  /// Call this when user *earns* a reward (after rewarded ad grants reward).
  Future<void> markRewardWatched() async {
    await _setRewardTimestampNow();
  }

  // ---------- Interstitial Ad Logic ----------
  /// Load interstitial if not already loaded or loading.
  void loadInterstitial() {
    if (_isPremium) return; // Don't load if premium
    if (_interstitialAd != null || _isLoadingInterstitial) return;

    _isLoadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isLoadingInterstitial = false;
          _interstitialLoadAttempts = 0;

          // Attach callbacks
          _interstitialAd!.setImmersiveMode(true);
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdShowedFullScreenContent: (adInstance) {
              // nothing for now
            },
            onAdDismissedFullScreenContent: (adInstance) {
              try {
                adInstance.dispose();
              } catch (_) {}
              _interstitialAd = null;
              // preload next one
              _scheduleReloadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (adInstance, error) {
              try {
                adInstance.dispose();
              } catch (_) {}
              _interstitialAd = null;
              _scheduleReloadInterstitial();
            },
            onAdImpression: (adInstance) {
              // optional: track impressions
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoadingInterstitial = false;
          _interstitialAd = null;
          _interstitialLoadAttempts += 1;
          // exponential backoff (simple)
          final backoffSeconds = 2 * _interstitialLoadAttempts;
          if (_interstitialLoadAttempts <= _maxLoadAttempts) {
            Future.delayed(
                Duration(seconds: backoffSeconds > 30 ? 30 : backoffSeconds),
                () {
              loadInterstitial();
            });
          }
        },
      ),
    );
  }

  void _scheduleReloadInterstitial() {
    if (_isPremium) return;
    // small delay before reloading to avoid hammering
    Future.delayed(const Duration(seconds: 3), () => loadInterstitial());
  }

  /// Show interstitial only if allowed by reward-blocking logic.
  /// - `onAdComplete` will be called after ad dismissed OR immediately if ad is blocked / not ready.
  /// - This function never blocks UI; it will either show ad (and call onAdComplete after dismiss)
  ///   or call onAdComplete immediately.
  Future<void> showInterstitialIfAllowed({VoidCallback? onAdComplete}) async {
    if (kDebugMode) {
      debugPrint('AdManager: showInterstitialIfAllowed called');
    }

    if (_isPremium) {
      if (kDebugMode) debugPrint('AdManager: Premium user - skipping ad');
      if (onAdComplete != null) onAdComplete();
      return;
    }

    final allowed = await canShowInterstitial();
    if (!allowed) {
      // Blocked due to recent reward -> immediately call completion
      if (kDebugMode) {
        debugPrint(
            'AdManager: Interstitial blocked by reward (12h cooldown active)');
      }
      if (onAdComplete != null) onAdComplete();
      return;
    }

    if (_interstitialAd != null) {
      if (kDebugMode) {
        debugPrint('AdManager: Showing interstitial ad');
      }

      // Create a completer to wait for ad dismissal
      final completer = Completer<void>();

      // Set up callback to handle ad lifecycle
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) {
          if (kDebugMode) {
            debugPrint('AdManager: Interstitial ad showed full screen');
          }
        },
        onAdDismissedFullScreenContent: (ad) {
          if (kDebugMode) {
            debugPrint('AdManager: Interstitial ad dismissed');
          }
          try {
            ad.dispose();
          } catch (_) {}
          _interstitialAd = null;
          _scheduleReloadInterstitial();
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          if (kDebugMode) {
            debugPrint('AdManager: Interstitial ad failed to show: $error');
          }
          try {
            ad.dispose();
          } catch (_) {}
          _interstitialAd = null;
          _scheduleReloadInterstitial();
          if (!completer.isCompleted) completer.complete();
        },
      );

      try {
        await _interstitialAd!.show();
      } catch (e) {
        // In case show fails unexpectedly
        if (kDebugMode) {
          debugPrint('AdManager: Exception while showing interstitial: $e');
        }
        try {
          _interstitialAd!.dispose();
        } catch (_) {}
        _interstitialAd = null;
        _scheduleReloadInterstitial();
        if (onAdComplete != null) onAdComplete();
        return;
      }

      // Wait until ad is dismissed/failed, then call completion callback
      await completer.future;
      if (kDebugMode) {
        debugPrint(
            'AdManager: Interstitial ad completed, calling onAdComplete');
      }
      if (onAdComplete != null) onAdComplete();
    } else {
      // No interstitial ready -> preload and immediately continue (do not block UX)
      if (kDebugMode) {
        debugPrint(
            'AdManager: No interstitial ad ready, proceeding without ad');
      }
      if (!_isLoadingInterstitial) loadInterstitial();
      if (onAdComplete != null) onAdComplete();
    }
  }

  // Manual dispose (if you ever want to fully cleanup)
  void dispose() {
    try {
      _interstitialAd?.dispose();
    } catch (_) {}
    _interstitialAd = null;
    _isLoadingInterstitial = false;
  }

  // ---------- Rewarded Ad Helpers ----------
  /// Show a rewarded ad. Call `markRewardWatched()` after the user is granted reward (already handled here).
  /// Provide callbacks for success/failure.
  void showRewardedAd({
    required BuildContext context,
    required Function(RewardItem) onUserEarnedReward,
    VoidCallback? onAdClosed,
    Function(LoadAdError)? onFailedToLoad,
  }) {
    if (_isPremium) {
      // Premium users get reward instantly without watching ad
      // Mock reward item
      onUserEarnedReward(RewardItem(1, 'premium_reward'));
      if (onAdClosed != null) onAdClosed();
      return;
    }

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        // ... (rest of the code same as before, no changes needed inside callback structure)
        onAdLoaded: (RewardedAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (adInstance) {
              try {
                adInstance.dispose();
              } catch (_) {}
              if (onAdClosed != null) onAdClosed();
            },
            onAdFailedToShowFullScreenContent: (adInstance, error) {
              try {
                adInstance.dispose();
              } catch (_) {}
              if (onAdClosed != null) onAdClosed();
            },
          );

          ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
            markRewardWatched().then((_) {
              onUserEarnedReward(reward);
            });
          });
        },
        onAdFailedToLoad: (error) {
          if (onFailedToLoad != null) onFailedToLoad(error);
        },
      ),
    );
  }

  // ---------- Rewarded Interstitial Ad Helpers ----------
  /// Show a rewarded interstitial ad.
  void showRewardedInterstitialAd({
    required BuildContext context,
    required Function(RewardItem) onUserEarnedReward,
    VoidCallback? onAdClosed,
    Function(LoadAdError)? onFailedToLoad,
    bool triggerAdBlocker = true,
  }) {
    if (_isPremium) {
      // Premium users get reward instantly
      onUserEarnedReward(RewardItem(1, 'premium_reward'));
      if (onAdClosed != null) onAdClosed();
      return;
    }

    RewardedInterstitialAd.load(
      adUnitId: _rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (adInstance) {
              try {
                adInstance.dispose();
              } catch (_) {}
              if (onAdClosed != null) onAdClosed();
            },
            onAdFailedToShowFullScreenContent: (adInstance, error) {
              try {
                adInstance.dispose();
              } catch (_) {}
              if (onAdClosed != null) onAdClosed();
            },
          );

          ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
            if (triggerAdBlocker) {
              markRewardWatched().then((_) {
                onUserEarnedReward(reward);
              });
            } else {
              onUserEarnedReward(reward);
            }
          });
        },
        onAdFailedToLoad: (error) {
          if (onFailedToLoad != null) onFailedToLoad(error);
        },
      ),
    );
  }
}

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget>
    with AutomaticKeepAliveClientMixin {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  // ... (rest of state variables)

  // Retry config
  int _loadAttempts = 0;
  final int _maxLoadAttempts = 3;
  bool _isDisposed = false;
  Timer? _retryTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Don't load if premium
    if (!AdManager.instance.isPremium) {
      _loadBannerAd();
    }
  }

  Future<void> _loadBannerAd() async {
    if (AdManager.instance.isPremium) return; // double check
    // ... (rest of loading logic same as before)
    // if already loaded or widget disposed, skip
    if (_isLoaded || _isDisposed) return;

    try {
      _bannerAd?.dispose();
    } catch (_) {}

    _loadAttempts++;

    final adUnitId = AdManager.bannerAdUnitIdAndroid;

    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (_isDisposed) {
            try {
              ad.dispose();
            } catch (_) {}
            return;
          }
          if (kDebugMode) {
            debugPrint('BannerAd loaded (attempt=$_loadAttempts)');
          }
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          try {
            ad.dispose();
          } catch (_) {}
          if (kDebugMode) debugPrint('BannerAd failed to load: $error');

          if (_loadAttempts < _maxLoadAttempts && !_isDisposed) {
            final backoffSeconds = (2 * _loadAttempts * 2).clamp(2, 60);
            _retryTimer?.cancel();
            _retryTimer = Timer(Duration(seconds: backoffSeconds), () {
              if (!_isDisposed && mounted) _loadBannerAd();
            });
          } else {
            if (mounted) {
              setState(() {
                _isLoaded = false;
                try {
                  _bannerAd?.dispose();
                } catch (_) {}
                _bannerAd = null;
              });
            }
          }
        },
        // ... other callbacks
      ),
    );
    // ...
    try {
      await _bannerAd!.load();
    } catch (e) {
      // ... error handling
      if (_loadAttempts < _maxLoadAttempts && !_isDisposed) {
        // ... retry logic
        final backoffSeconds = (2 * _loadAttempts * 2).clamp(2, 60);
        _retryTimer?.cancel();
        _retryTimer = Timer(Duration(seconds: backoffSeconds), () {
          if (!_isDisposed && mounted) _loadBannerAd();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // If premium, hide banner completely
    if (AdManager.instance.isPremium) {
      return const SizedBox.shrink();
    }

    // If ad loaded, render it with its actual height.
    if (_isLoaded && _bannerAd != null) {
      final width = MediaQuery.of(context).size.width;
      final height = _bannerAd!.size.height.toDouble();
      return SizedBox(
        width: width,
        height: height,
        child: AdWidget(ad: _bannerAd!),
      );
    }

    // Otherwise, return a blank placeholder
    return const SizedBox(
      width: double.infinity,
      height: 50,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _retryTimer?.cancel();
    try {
      _bannerAd?.dispose();
    } catch (_) {}
    _bannerAd = null;
    super.dispose();
  }
}
