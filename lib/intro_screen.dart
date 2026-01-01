
import 'dart:ui'; // Needed for ImageFilter

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:slc/pages/login_screen.dart';
import 'package:slc/services/app_info_service.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:provider/provider.dart';

import 'services/shared_preferences_manager.dart';

import 'theme/theme_provider.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _introKey = GlobalKey<IntroductionScreenState>();
  int _themeIndex = SharedPreferencesManager.getInt('themeIndex') ?? 0;
  int _streamingmode = SharedPreferencesManager.getInt('streamingMode') ?? 0;
  
  // Define brand colors
  final Color _brandOrange = const Color(0xFFEF6C00); // Deep Orange


  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    // Custom decoration needed for the new style
    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(fontSize: 28.0, fontWeight: FontWeight.w700, color: Colors.white),
      bodyTextStyle: TextStyle(fontSize: 19.0, color: Colors.white70),
      bodyPadding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      pageColor: Colors.transparent, // Important for background gradient
      imagePadding: EdgeInsets.zero,
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0F2027), // Deep Blue/Black
              const Color(0xFF203A43),
              const Color(0xFF2C5364),
              _brandOrange.withOpacity(0.2), // Hint of orange
            ],
          ),
        ),
        child: IntroductionScreen(
          key: _introKey,
          globalBackgroundColor: Colors.transparent,
          allowImplicitScrolling: true,
          pages: [
            // Slide 1: Welcome / Brand
            PageViewModel(
              title: "", // Using custom body
              bodyWidget: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  // Logo Container with Glassmorphism
                  _buildGlassCard(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/images/suanlicheng_logo.png',
                          height: 120, // Adjust size as needed
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 20),
                        Image.asset(
                          'assets/images/suanlicheng_text.png',
                          height: 60, // Adjust size as needed
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    '一款跨全平台的高性能',
                    style: TextStyle(fontSize: 28.0, color: Colors.white, fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(height: 20),
                   SizedBox(
                    height: 60.0,
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 40.0,
                        fontWeight: FontWeight.bold,
                        color: _brandOrange,
                        shadows: [
                          Shadow(
                            blurRadius: 10.0,
                            color: _brandOrange,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: AnimatedTextKit(
                        animatedTexts: [
                          RotateAnimatedText('办公'),
                          RotateAnimatedText('协作'),
                          RotateAnimatedText('娱乐'),
                        ],
                        repeatForever: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '串流工具',
                    style: TextStyle(fontSize: 28.0, color: Colors.white, fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(height: 40),
                  // Platform Icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPlatformIcon(FontAwesomeIcons.windows),
                      const SizedBox(width: 15),
                      _buildPlatformIcon(Icons.apple),
                      if (!AppPlatform.isIOS) const SizedBox(width: 15),
                      if (!AppPlatform.isIOS) _buildPlatformIcon(Icons.android),
                      const SizedBox(width: 15),
                      _buildPlatformIcon(FontAwesomeIcons.linux),
                      const SizedBox(width: 15),
                      _buildPlatformIcon(Icons.web),
                    ],
                  ),
                ],
              ),
              decoration: pageDecoration,
            ),
            
            // Slide 2: Settings
            PageViewModel(
              title: "设置您的主题 & 模式",
              bodyWidget: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildGlassCard(
                    child: Column(
                      children: [
                        const Text("主题偏好", style: TextStyle(color: Colors.white, fontSize: 18)),
                        const SizedBox(height: 15),
                        ToggleButtons(
                          isSelected: [_themeIndex == 0, _themeIndex == 1, _themeIndex == 2],
                          onPressed: (int index) {
                            setState(() {
                              _themeIndex = index;
                              SharedPreferencesManager.setInt('themeIndex', _themeIndex);
                              themeProvider.setThemeMode(index);
                            });
                          },
                          color: Colors.white60,
                          selectedColor: Colors.white,
                          fillColor: _brandOrange,
                          borderRadius: BorderRadius.circular(10),
                          borderColor: Colors.white24,
                          selectedBorderColor: _brandOrange,
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('日间')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('跟随系统')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('夜间')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildGlassCard(
                    child: Column(
                      children: [
                        const Text("使用模式", style: TextStyle(color: Colors.white, fontSize: 18)),
                         const SizedBox(height: 15),
                        ToggleButtons(
                          isSelected: [_streamingmode == 0, _streamingmode == 1],
                          onPressed: (int index) {
                            setState(() {
                              _streamingmode = index;
                              SharedPreferencesManager.setInt('streamingMode', _streamingmode);
                              themeProvider.setStreamingMode(_streamingmode);
                              // Logic from original code
                              if (_streamingmode == 0) {
                                SharedPreferencesManager.setBool("autoHideLocalCursor", false);
                              } else {
                                SharedPreferencesManager.setBool("autoHideLocalCursor", true);
                              }
                            });
                          },
                           color: Colors.white60,
                          selectedColor: Colors.white,
                          fillColor: _brandOrange,
                          borderRadius: BorderRadius.circular(10),
                          borderColor: Colors.white24,
                          selectedBorderColor: _brandOrange,
                          children: const [
                             Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: Text('办公')),
                             Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: Text('游戏')),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Mode Details
                         if (_streamingmode == 0)
                          _buildModeDetails([
                            '* 4K 30帧',
                            '* 低至 100毫秒延迟',
                            '* 高清晰度',
                            '* 低带宽消耗'
                          ]),
                        if (_streamingmode == 1)
                          _buildModeDetails([
                            '* 最高 4K 60帧',
                            '* 低至 40 毫秒延迟',
                            '* 高清晰度',
                            '* 硬件加速（需显卡支持）'
                          ]),
                      ],
                    ),
                  ),
                ],
              ),
              decoration: pageDecoration,
            ),
          ],
          onDone: () {
            SharedPreferencesManager.setBool('appintroFinished', true);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
          showSkipButton: true,
          skip: const Text("跳过", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
          next: const Icon(Icons.arrow_forward, color: Colors.white),
          done: const Text("完成", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
          dotsDecorator: DotsDecorator(
            size: const Size.square(10.0),
            activeSize: const Size(20.0, 10.0),
            activeColor: _brandOrange,
            color: Colors.white24,
            spacing: const EdgeInsets.symmetric(horizontal: 3.0),
            activeShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25.0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildPlatformIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  Widget _buildModeDetails(List<String> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: details.map((detail) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          detail,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      )).toList(),
    );
  }
}
