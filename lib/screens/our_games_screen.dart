import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';

/// "Oyunlarımız ve Uygulamalarımız" — diğer oyunlarımızın listesi.
/// Yeni oyun eklemek için [OurGamesScreen._apps] listesine bir satır eklemek yeter.
class _PromoApp {
  final String name;
  final String iconAsset;
  final String url;
  const _PromoApp(this.name, this.iconAsset, this.url);
}

class OurGamesScreen extends StatelessWidget {
  const OurGamesScreen({super.key});

  static const List<_PromoApp> _apps = [
    _PromoApp(
      'Worlds Merge: Puzzle & Town',
      'assets/icon/worlds_merge_icon.png',
      'https://play.google.com/store/apps/details?id=com.sitora.ai',
    ),
  ];

  static Future<void> open(BuildContext context) {
    AnalyticsService.instance.logScreen('our_games');
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OurGamesScreen()),
    );
  }

  Future<void> _launch(BuildContext context, _PromoApp app) async {
    SoundService.instance.buttonTap();
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(app.url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      CustomToast.show(context, t('ourGames_openFail'),
          icon: '⚠️', accentColor: AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.spaceTop,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.spaceTop, AppColors.spaceMid, AppColors.spaceBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        SoundService.instance.buttonTap();
                        Navigator.of(context).maybePop();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                          border: Border.all(
                              color: AppColors.tubeGlassBorder, width: 2),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF9A3C), Color(0xFF9D174D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white70, width: 2),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x66FF7A45),
                                blurRadius: 14,
                                offset: Offset(0, 3)),
                          ],
                        ),
                        child: Text(
                          t('ourGames_title'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            shadows: [Shadow(color: Color(0x99000000), blurRadius: 3)],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 54), // geri butonuyla simetri
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.55),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    itemCount: _apps.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _GameCard(
                      app: _apps[i],
                      onTap: () => _launch(context, _apps[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final _PromoApp app;
  final VoidCallback onTap;
  const _GameCard({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2447),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.accentSoft.withOpacity(0.7), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4)),
            BoxShadow(color: Color(0x225CC8FF), blurRadius: 16),
          ],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(app.iconAsset,
                    width: 72, height: 72, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.shop_2_rounded,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(t('ourGames_openPlay'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 30),
          ],
        ),
      ),
    );
  }
}
