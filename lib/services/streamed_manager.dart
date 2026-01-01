import 'dart:async';
import 'package:slc/base/constants.dart';
import 'package:slc/global_settings/streaming_settings.dart';
import 'package:slc/utils/hash_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/display_data.dart';
import 'package:synchronized/synchronized.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:universal_io/io.dart' as io;

import '../base/logging.dart';
import '../entities/device.dart';
import '../entities/session.dart';
import 'app_info_service.dart';
import 'node_agent_service.dart';

// ignore: constant_identifier_names
const int AUDIO_SYSTEM = 255;

class StreamedManager {
  static Map<String, StreamingSession> sessions = {};

  //We put localstream here because we want sessions share a local stream.
  //Screenid to MediaStream
  static Map<int, MediaStream> localVideoStreams = {};
  static Map<int, int> localVideoStreamsCount = {};

  //255: system audio
  //0~n: local microphones
  //AUDIO_SYSTEM = 255;
  static Map<int, MediaStream> localAudioStreams = {};
  static int audioSenderCount = 0;

  //auto increment. used for cursor hooks.
  static int cursorImageHookID = 0;
  static int cursorPositionUpdatedHookID = 0;

  static ValueNotifier<int> currentlyStreamedCount = ValueNotifier(0);
  static void setCurrentStreamedState(int value) {
    currentlyStreamedCount.value = value;
  }

  // Map from real screen id to virtual display id
  static Map<int, int> virtualDisplayIds = {};

  // 创建虚拟显示器
  static Future<int?> _createVirtualDisplay(int width, int height) async {
    try {
      // 初始化parsec-vdd
      bool initialized = await HardwareSimulator.initParsecVdd();
      if (!initialized) {
        VLOG0('初始化parsec-vdd失败');
        return null;
      }

      final customConfigs = await HardwareSimulator.getCustomDisplayConfigs();

      List<Map<String, dynamic>> newConfigs = List.from(customConfigs);

      bool isresolutionExist = false;

      for (var config in newConfigs) {
        if (config['width'] == width && config['height'] == height) {
          isresolutionExist = true;
          break;
        }
      }
      if (!isresolutionExist) {
        if (newConfigs.length > 4) {
          newConfigs.removeAt(0);
        }

        newConfigs.add({
          'width': width,
          'height': height,
          'refreshRate': 60,
        });

        bool success =
            await HardwareSimulator.setCustomDisplayConfigs(newConfigs);
        if (success) {
          VLOG0('添加虚拟显示器分辨率成功: ${width}x${height}');
        } else {
          VLOG0('添加虚拟显示器分辨率失败');
          return null;
        }
      }

      // 创建虚拟显示器
      int displayId = await HardwareSimulator.createDisplay();
      //refresh display list.
      await HardwareSimulator.getAllDisplays();
      if (displayId >= 0) {
        VLOG0('创建虚拟显示器成功,ID: $displayId');
        // 设置虚拟显示器分辨率
        int retry = 0;
        bool success = false;
        const Duration retryInterval = Duration(milliseconds: 500);
        while (retry < 10) {
          success = await HardwareSimulator.changeDisplaySettings(
              displayId, width, height, 60);
          if (success) {
            VLOG0('设置虚拟显示器分辨率成功: ${width}x${height}');
            break;
          } else {
            await Future.delayed(retryInterval);
            VLOG0('设置虚拟显示器分辨率失败');
          }
        }

        if (!success) {
          await HardwareSimulator.removeDisplay(displayId);
          return null;
        }

        return displayId;
      } else {
        VLOG0('创建虚拟显示器失败');
        return null;
      }
    } catch (e) {
      VLOG0('创建虚拟显示器异常: $e');
      return null;
    }
  }

  // 移除指定的虚拟显示器
  static Future<void> _removeVirtualDisplay(int displayId) async {
    try {
      bool removed = await HardwareSimulator.removeDisplay(displayId);
      if (removed) {
        //refresh display list.
        await HardwareSimulator.getAllDisplays();
        VLOG0('删除虚拟显示器成功,ID: $displayId');
      } else {
        VLOG0('删除虚拟显示器失败,ID: $displayId');
      }
    } catch (e) {
      VLOG0('删除虚拟显示器异常: $e');
    }
  }

  // 恢复显示器配置，带重试机制
  static Future<void> _restoreDisplayConfigurationWithRetry() async {
    int retryCount = 0;
    const int maxRetries = 5;
    const Duration retryInterval = Duration(milliseconds: 500);

    while (retryCount < maxRetries) {
      try {
        bool success = await HardwareSimulator.restoreDisplayConfiguration();
        if (success) {
          VLOG0("恢复显示器配置成功，重试次数: $retryCount");
          return;
        }
      } catch (e) {
        VLOG0("恢复显示器配置异常: $e");
      }

      retryCount++;
      if (retryCount < maxRetries) {
        VLOG0(
            "恢复显示器配置失败，${retryInterval.inMilliseconds}ms后重试 (${retryCount}/$maxRetries)");
        await Future.delayed(retryInterval);
      }
    }

    VLOG0("恢复显示器配置失败，已达到最大重试次数: $maxRetries");
  }

  Future<void> _loadCurrentMultiDisplayMode() async {
    try {
      MultiDisplayMode mode =
          await HardwareSimulator.getCurrentMultiDisplayMode();
      VLOG0('Current multi-display mode: $mode');
    } catch (e) {
      VLOG0('Failed to load current multi-display mode: $e');
    }
  }

  Future<void> _setMultiDisplayMode(MultiDisplayMode mode) async {
    await HardwareSimulator.setMultiDisplayMode(mode);
    await _loadCurrentMultiDisplayMode();
  }

  static Future<void> startStreaming(
      Device target, StreamedSettings settings) async {
    // === DEBUG LOGGING START ===
    VLOG0('[STREAM_DEBUG] ========================================');
    VLOG0('[STREAM_DEBUG] startStreaming called!');
    VLOG0(
        '[STREAM_DEBUG] target.websocketSessionid: ${target.websocketSessionid}');
    VLOG0('[STREAM_DEBUG] target.devicename: ${target.devicename}');
    VLOG0(
        '[STREAM_DEBUG] ApplicationInfo.connectable: ${ApplicationInfo.connectable}');
    VLOG0('[STREAM_DEBUG] settings.targetScreenId: ${settings.screenId}');
    VLOG0('[STREAM_DEBUG] settings.streamMode: ${settings.streamMode}');
    VLOG0(
        '[STREAM_DEBUG] settings.customScreen: ${settings.customScreenWidth}x${settings.customScreenHeight}');
    VLOG0(
        '[STREAM_DEBUG] settings.connectPassword: ${settings.connectPassword}');
    VLOG0(
        '[STREAM_DEBUG] StreamingSettings.connectPasswordHash: ${StreamingSettings.connectPasswordHash}');
    if (settings.connectPassword != null) {
      VLOG0(
          '[STREAM_DEBUG] Hash of received password: ${HashUtil.hash(settings.connectPassword!)}');
    }
    // === DEBUG LOGGING END ===

    await NodeAgentService.remoteLog(
      'INFO',
      '[v3.19] startStreaming params',
      {
        'platform': kIsWeb
            ? 'web'
            : (io.Platform.isWindows
                ? 'windows'
                : (io.Platform.isMacOS
                    ? 'macos'
                    : (io.Platform.isLinux ? 'linux' : 'other'))),
        'isSystem': ApplicationInfo.isSystem,
        'screenCount': ApplicationInfo.screenCount,
        'connectable': ApplicationInfo.connectable,
        'sessionName': io.Platform.environment['SESSIONNAME'],
        'username': io.Platform.environment['USERNAME'],
        'streamMode': settings.streamMode,
        'targetScreenId': settings.screenId,
        'framerate': settings.framerate,
        'bitrate': settings.bitrate,
      },
      const Duration(seconds: 1),
    );

    try {
      bool allowConnect = ApplicationInfo.connectable;
      if (!allowConnect) {
        VLOG0('[STREAM_DEBUG] REJECTED: allowConnect is false!');
        await NodeAgentService.remoteLog(
          'WARN',
          '[v3.19] startStreaming REJECTED: connectable=false',
          null,
          const Duration(seconds: 1),
        );
        return;
      }
      if (settings.connectPassword == null) {
        VLOG0('[STREAM_DEBUG] REJECTED: connectPassword is null!');
        await NodeAgentService.remoteLog(
          'WARN',
          '[v3.19] startStreaming REJECTED: connectPassword=null',
          null,
          const Duration(seconds: 1),
        );
        return;
      }
      if (settings.screenId == null) {
        VLOG0('[STREAM_DEBUG] REJECTED: targetScreenId is null!');
        await NodeAgentService.remoteLog(
          'WARN',
          '[v3.19] startStreaming REJECTED: targetScreenId=null',
          null,
          const Duration(seconds: 1),
        );
        return;
      }
      if (StreamingSettings.connectPasswordHash !=
          HashUtil.hash(settings.connectPassword!)) {
        VLOG0('[STREAM_DEBUG] REJECTED: password hash mismatch!');
        VLOG0(
            '[STREAM_DEBUG] Expected: ${StreamingSettings.connectPasswordHash}');
        VLOG0(
            '[STREAM_DEBUG] Received: ${HashUtil.hash(settings.connectPassword!)}');
        await NodeAgentService.remoteLog(
          'WARN',
          '[v3.19] startStreaming REJECTED: password hash mismatch',
          {
            'expected_hash_set': StreamingSettings.connectPasswordHash.isNotEmpty,
          },
          const Duration(seconds: 1),
        );
        return;
      }
      VLOG0(
          '[STREAM_DEBUG] PASSED: All validation checks OK, proceeding to create session...');
      unawaited(NodeAgentService.remoteLog(
        'INFO',
        '[v3.19] startStreaming validation passed',
        null,
        const Duration(seconds: 1),
      ));
    } catch (e, stack) {
      VLOG0('[STREAM_DEBUG] validation exception: $e\n$stack');
      unawaited(NodeAgentService.remoteLog(
        'ERROR',
        '[v3.19] startStreaming validation exception',
        {
          'error': e.toString(),
        },
        const Duration(seconds: 1),
      ));
      return;
    }

    try {
      await _lock.synchronized(() async {
        final perfSw = Stopwatch()..start();
        int createVirtualDisplayMs = 0;
        int getSourcesMs = 0;
        int getDisplayMediaMs = 0;
        int sourcesCount = -1;

        if (sessions.containsKey(target.websocketSessionid)) {
          VLOG0(
              "Starting session which is already started: $target.websocketSessionid");
          return;
        }

        Completer<void>? displayCallbackCompleter;

        if (settings.streamMode == VDISPLAY_OCCUPY ||
            settings.streamMode == VDSIPLAY_EXTEND) {
          //bool hasPending = await HardwareSimulator.hasPendingConfiguration();
          /*if (settings.streamMode == VDISPLAY_OCCUPY && isVdisplayOccupied) {
            VLOG0("其它连接正在修改显示器配置，无法连接");
            return;
          }*/
          // 独占模式或扩展屏模式，需要创建虚拟显示器
          int width = settings.customScreenWidth ?? 1920;
          int height = settings.customScreenHeight ?? 1080;

          // 创建全局的Completer来等待显示器数量变化回调
          ApplicationInfo.displayCountChangedCompleter = Completer<void>();
          final vddSw = Stopwatch()..start();
          int? virtualDisplayId = await _createVirtualDisplay(width, height);
          createVirtualDisplayMs = vddSw.elapsedMilliseconds;
          if (virtualDisplayId != null) {
            // 使用虚拟显示器的ID作为screenId
            VLOG0("新建虚拟显示器,等待显示器被系统加载");
            //如果我们删除然后添加一个虚拟显示器，且配置不变，可能永远不会触发显示器数量变化回调。
            //TODO:有时候删除最后一个显示器 再添加时不会触发displayCountChangedCompleter回调 为什么？
            //目前只能等2秒来保证虚拟显示器加载完成
            //await ApplicationInfo.displayCountChangedCompleter!.future;
            await Future.delayed(const Duration(milliseconds: 2000));
            if (settings.streamMode == VDISPLAY_OCCUPY ||
                settings.streamMode == VDSIPLAY_EXTEND) {
              virtualDisplayIds[settings.screenId!] = virtualDisplayId;
            }
            VLOG0('使用虚拟显示器模式，显示器ID: $virtualDisplayId');
          } else {
            VLOG0('创建虚拟显示器失败');
            ApplicationInfo.displayCountChangedCompleter = null;
            return;
          }
        }
        int? autoVirtualDisplayId;
        bool sessionCreated = false;
        try {
          // Default mode fallback: if Windows has no display, create one automatically.
          final isVirtualDisplayMode = settings.streamMode == VDISPLAY_OCCUPY ||
              settings.streamMode == VDSIPLAY_EXTEND;
          if (!isVirtualDisplayMode && AppPlatform.isWindows) {
            int displayCount = ApplicationInfo.screenCount;
            try {
              displayCount = await HardwareSimulator.getAllDisplays();
            } catch (_) {}
            if (displayCount <= 0) {
              final width = settings.customScreenWidth ?? 1920;
              final height = settings.customScreenHeight ?? 1080;
              await NodeAgentService.remoteLog(
                'WARN',
                '[v3.19] 未检测到显示器，尝试创建虚拟显示器',
                {
                  'desired': '${width}x${height}',
                },
                const Duration(seconds: 1),
              );
              final vddSw = Stopwatch()..start();
              autoVirtualDisplayId = await _createVirtualDisplay(width, height);
              createVirtualDisplayMs = vddSw.elapsedMilliseconds;
              if (autoVirtualDisplayId != null) {
                virtualDisplayIds[settings.screenId!] = autoVirtualDisplayId!;
                await Future.delayed(const Duration(milliseconds: 2000));
                await NodeAgentService.remoteLog(
                  'INFO',
                  '[v3.19] 已创建虚拟显示器',
                  {'display_id': autoVirtualDisplayId},
                  const Duration(seconds: 1),
                );
              } else {
                await NodeAgentService.remoteLog(
                  'ERROR',
                  '[v3.19] 创建虚拟显示器失败',
                  null,
                  const Duration(seconds: 1),
                );
                return;
              }
            }
          }

          if (!localVideoStreams.containsKey(settings.screenId!)) {
            MediaStream? stream;

            if (AppPlatform.isWeb) {
              final Map<String, dynamic> mediaConstraints = {
                'audio': false,
                'video': {
                  'frameRate': {
                    'ideal': settings.framerate,
                    'max': settings.framerate,
                  },
                },
              };
              try {
                await NodeAgentService.remoteLog(
                  'INFO',
                  '[v3.19] 准备调用 getDisplayMedia',
                  null,
                  const Duration(seconds: 1),
                );
                final getDisplayMediaSw = Stopwatch()..start();
                stream = await navigator.mediaDevices
                    .getDisplayMedia(mediaConstraints);
                getDisplayMediaMs = getDisplayMediaSw.elapsedMilliseconds;
                await NodeAgentService.remoteLog(
                  'INFO',
                  '[v3.19] getDisplayMedia 成功',
                  null,
                  const Duration(seconds: 1),
                );
              } catch (e) {
                await NodeAgentService.remoteLog(
                  'ERROR',
                  '[v3.19] getDisplayMedia 失败',
                  {'error': e.toString()},
                  const Duration(seconds: 1),
                );
                VLOG0("getDisplayMedia failed.$e");
                return;
              }
            } else {
              // 先尝试“默认抓屏”（不依赖 desktopCapturer.getSources）。
              if (!isVirtualDisplayMode && settings.screenId == 0) {
                final directConstraints = <String, dynamic>{
                  'video': {
                    'mandatory': {
                      'frameRate': settings.framerate,
                      'hasCursor': false,
                    }
                  },
                  'audio': false,
                };
                try {
                  await NodeAgentService.remoteLog(
                    'INFO',
                    '[v3.19] 尝试默认抓屏: getDisplayMedia(无 deviceId)',
                    null,
                    const Duration(seconds: 1),
                  );
                  final getDisplayMediaSw = Stopwatch()..start();
                  stream = await navigator.mediaDevices
                      .getDisplayMedia(directConstraints);
                  getDisplayMediaMs = getDisplayMediaSw.elapsedMilliseconds;
                  await NodeAgentService.remoteLog(
                    'INFO',
                    '[v3.19] 默认抓屏 getDisplayMedia 成功',
                    null,
                    const Duration(seconds: 1),
                  );
                } catch (e) {
                  await NodeAgentService.remoteLog(
                    'WARN',
                    '[v3.19] 默认抓屏 getDisplayMedia 失败，回退到 getSources',
                    {'error': e.toString()},
                    const Duration(seconds: 1),
                  );
                  stream = null;
                }
              }

              if (stream == null) {
                late List<DesktopCapturerSource> sources;
                try {
                  VLOG0(
                      '[STREAM_DEBUG] Calling desktopCapturer.getSources(types: [Screen])...');
                  await NodeAgentService.remoteLog(
                    'INFO',
                    '[v3.19] 准备调用 desktopCapturer.getSources',
                    null,
                    const Duration(seconds: 1),
                  );
                  final getSourcesSw = Stopwatch()..start();
                  sources = await desktopCapturer
                      .getSources(types: [SourceType.Screen]);
                  getSourcesMs = getSourcesSw.elapsedMilliseconds;
                  sourcesCount = sources.length;
                  await NodeAgentService.remoteLog(
                    'INFO',
                    '[v3.19] getSources 成功',
                    {'count': sources.length},
                    const Duration(seconds: 1),
                  );
                  VLOG0(
                      '[STREAM_DEBUG] desktopCapturer.getSources returned ${sources.length} sources');
                } catch (e, stack) {
                  await NodeAgentService.remoteLog(
                    'ERROR',
                    '[v3.19] getSources 崩溃',
                    {'error': e.toString()},
                    const Duration(seconds: 1),
                  );
                  VLOG0('desktopCapturer.getSources failed: $e\n$stack');
                  return;
                }

                if (!isVirtualDisplayMode) {
                  // Default mode: do not touch system display config; just validate.
                  if (sources.isEmpty) {
                    await NodeAgentService.remoteLog(
                      'WARN',
                      '[v3.19] 屏幕源为空',
                      null,
                      const Duration(seconds: 1),
                    );
                    VLOG0(
                        'No screen sources found (desktopCapturer.getSources returned empty).');
                    return;
                  }
                  if (settings.screenId! < 0 ||
                      settings.screenId! >= sources.length) {
                    await NodeAgentService.remoteLog(
                      'ERROR',
                      '[v3.19] targetScreenId 越界',
                      {
                        'targetScreenId': settings.screenId,
                        'count': sources.length,
                      },
                      const Duration(seconds: 1),
                    );
                    VLOG0(
                        'Invalid targetScreenId=${settings.screenId} (available screens=${sources.length}).');
                    return;
                  }
                } else {
                  // Virtual display mode: keep legacy behavior to wait for new display to appear.
                  int retryCount = 0;
                  while (sources.length <= settings.screenId!) {
                    try {
                      MultiDisplayMode currentMode =
                          await HardwareSimulator.getCurrentMultiDisplayMode();
                      if (currentMode != MultiDisplayMode.extend) {
                        await HardwareSimulator.setMultiDisplayMode(
                            MultiDisplayMode.extend);
                      }
                    } catch (e, stack) {
                      VLOG0('get/set multi-display mode failed: $e\n$stack');
                      return;
                    }

                    retryCount++;
                    if (retryCount > 10) {
                      VLOG0('创建虚拟显示器后 等待超时');
                      if (virtualDisplayIds.containsKey(settings.screenId)) {
                        _removeVirtualDisplay(
                            virtualDisplayIds[settings.screenId]!);
                        virtualDisplayIds.remove(settings.screenId);
                      }
                      return;
                    }

                    try {
                      sources = await desktopCapturer
                          .getSources(types: [SourceType.Screen]);
                    } catch (e, stack) {
                      VLOG0(
                          'desktopCapturer.getSources retry failed: $e\n$stack');
                      return;
                    }
                  }

                  // 独占模式，需要重置新显示器为主显示器
                  if (settings.streamMode == VDISPLAY_OCCUPY) {
                    try {
                      await Future.delayed(const Duration(milliseconds: 500));
                      sources = await desktopCapturer
                          .getSources(types: [SourceType.Screen]);
                      if (sources.length != 1) {
                        await HardwareSimulator.setPrimaryDisplayOnly(
                            virtualDisplayIds[0]!);
                        retryCount = 0;
                        while (sources.length != 1) {
                          retryCount++;
                          if (retryCount > 10) {
                            VLOG0('创建虚拟显示器后 设置主屏超时');
                            HardwareSimulator.restoreDisplayConfiguration();
                            return;
                          }
                          await Future.delayed(
                              const Duration(milliseconds: 500));
                          sources = await desktopCapturer
                              .getSources(types: [SourceType.Screen]);
                        }
                      }
                      settings.screenId = 0;
                    } catch (e, stack) {
                      VLOG0('setPrimaryDisplayOnly failed: $e\n$stack');
                      return;
                    }
                  }

                  if (sources.isEmpty) {
                    VLOG0(
                        'No screen sources found after virtual display setup (sources empty).');
                    return;
                  }
                  if (settings.screenId! < 0 ||
                      settings.screenId! >= sources.length) {
                    VLOG0(
                        'Invalid targetScreenId=${settings.screenId} (available screens=${sources.length}) after virtual display setup.');
                    return;
                  }
                }

                final source = sources[settings.screenId!];
                final mediaConstraints = <String, dynamic>{
                  'video': {
                    'deviceId': {'exact': source.id},
                    'mandatory': {
                      'frameRate': settings.framerate,
                      //Todo(haichao): currently disable this because it will cause crash on some devices.
                      'hasCursor': false //settings.showRemoteCursor
                    }
                  },
                  'audio': false
                };

                try {
                  VLOG0(
                      '[STREAM_DEBUG] Calling navigator.mediaDevices.getDisplayMedia(...)');
                  await NodeAgentService.remoteLog(
                    'INFO',
                    '[v3.19] 准备调用 getDisplayMedia',
                    null,
                    const Duration(seconds: 1),
                  );
                  final getDisplayMediaSw = Stopwatch()..start();
                  stream = await navigator.mediaDevices
                      .getDisplayMedia(mediaConstraints);
                  getDisplayMediaMs = getDisplayMediaSw.elapsedMilliseconds;
                  await NodeAgentService.remoteLog(
                    'INFO',
                    '[v3.19] getDisplayMedia 成功',
                    null,
                    const Duration(seconds: 1),
                  );
                } catch (e) {
                  await NodeAgentService.remoteLog(
                    'ERROR',
                    '[v3.19] getDisplayMedia 失败',
                    {'error': e.toString()},
                    const Duration(seconds: 1),
                  );
                  //This happens on Web when user choose not to share the content.
                  VLOG0("getDisplayMedia failed.$e");
                  return;
                }
              }
            }

            if (stream == null) {
              await NodeAgentService.remoteLog(
                'ERROR',
                '[v3.19] getDisplayMedia 返回空流',
                null,
                const Duration(seconds: 1),
              );
              return;
            }
            localVideoStreams[settings.screenId!] = stream;
            localVideoStreamsCount[settings.screenId!] = 1;
          } else {
            //TODO:串流过程中显示器配置发生改变如何考虑?
            localVideoStreamsCount[settings.screenId!] =
                localVideoStreamsCount[settings.screenId!]! + 1;
          }

          await NodeAgentService.remoteLog(
            'INFO',
            '[v3.19] 准备调用 session.acceptRequest (发送 offer)',
            null,
            const Duration(seconds: 1),
          );
          StreamingSession session =
              StreamingSession(target, ApplicationInfo.thisDevice);
          cursorImageHookID++;
          session.cursorImageHookID = cursorImageHookID;
          cursorPositionUpdatedHookID++;
          session.cursorPositionUpdatedHookID = cursorPositionUpdatedHookID;
          try {
            session.acceptRequest(settings);
          } catch (e, stack) {
            await NodeAgentService.remoteLog(
              'ERROR',
              '[v3.19] session.acceptRequest 失败',
              {'error': e.toString()},
              const Duration(seconds: 1),
            );
            VLOG0('session.acceptRequest failed: $e\n$stack');
            return;
          }
          await NodeAgentService.remoteLog(
            'INFO',
            '[v3.19] acceptRequest 已调用，offer 应已发送',
            null,
            const Duration(seconds: 1),
          );
          sessions[target.websocketSessionid] = session;
          sessionCreated = true;
          setCurrentStreamedState(sessions.length);
          VLOG0(
              '[STREAM_PERF] startStreaming mode=${settings.streamMode} screenId=${settings.screenId} vdd=${createVirtualDisplayMs}ms getSources=${getSourcesMs}ms sources=${sourcesCount} getDisplayMedia=${getDisplayMediaMs}ms total=${perfSw.elapsedMilliseconds}ms');
        } finally {
          if (!sessionCreated && autoVirtualDisplayId != null) {
            await NodeAgentService.remoteLog(
              'INFO',
              '[v3.19] 自动虚拟显示器清理',
              {'display_id': autoVirtualDisplayId},
              const Duration(seconds: 1),
            );
            await _removeVirtualDisplay(autoVirtualDisplayId!);
            virtualDisplayIds.remove(settings.screenId);
          }
        }
      });
    } catch (e, stack) {
      VLOG0('[STREAM_DEBUG] startStreaming exception: $e\n$stack');
      return;
    }
  }

  static final _lock = Lock();

  static void stopStreaming(Device target) {
    _lock.synchronized(() {
      if (sessions.containsKey(target.websocketSessionid)) {
        StreamingSession? session = sessions[target.websocketSessionid];
        session?.stop();
        int screenId = session!.streamSettings!.screenId!;
        sessions.remove(target.websocketSessionid);
        localVideoStreamsCount[screenId] =
            localVideoStreamsCount[screenId]! - 1;
        if (localVideoStreamsCount[screenId] == 0) {
          if (localVideoStreams[screenId] != null) {
            localVideoStreams[screenId]?.getTracks().forEach((track) {
              track.stop();
            });
            localVideoStreams.remove(screenId);
          }

          // 如果这个screenId对应的是虚拟显示器，则移除它
          if (virtualDisplayIds.containsKey(screenId)) {
            VLOG0("removing monitor");
            _removeVirtualDisplay(virtualDisplayIds[screenId]!);
            virtualDisplayIds.remove(screenId);
            if (session.streamSettings?.streamMode == VDISPLAY_OCCUPY) {
              //虚拟显示器模式结束，恢复之前的屏幕设置。
              _restoreDisplayConfigurationWithRetry();
              VLOG0("restore monitor config");
            }
          }
        }
        if (sessions.isEmpty) {
          //TODO(Haichao): maybe restart app to save memory? 给用户一个按钮来重启app.
        }
      } else {
        VLOG0("No session found with sessionId: $target.websocketSessionid");
      }
      setCurrentStreamedState(sessions.length);
    });
  }

  static void stopAllSessions() {
    var targets = sessions.values.map((s) => s.controller).toList();
    for (var target in targets) {
      stopStreaming(target);
    }
  }

  static void onAnswerReceived(
      String targetConnectionid, Map<String, dynamic> answer) {
    if (sessions.containsKey(targetConnectionid)) {
      StreamingSession? session = sessions[targetConnectionid];
      session?.onAnswerReceived(answer);
    } else {
      VLOG0("No session found with sessionId: $targetConnectionid");
    }
  }

  static void onCandidateReceived(
      String targetConnectionid, Map<String, dynamic> candidate) {
    if (sessions.containsKey(targetConnectionid)) {
      StreamingSession? session = sessions[targetConnectionid];
      session?.onCandidateReceived(candidate);
    } else {
      VLOG0("No session found with sessionId: $targetConnectionid");
    }
  }
}
