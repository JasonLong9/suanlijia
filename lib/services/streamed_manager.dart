import 'dart:async';
import 'package:slc/base/constants.dart';
import 'package:slc/global_settings/streaming_settings.dart';
import 'package:slc/utils/hash_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/display_data.dart';
import 'package:synchronized/synchronized.dart';
import 'package:hardware_simulator/hardware_simulator.dart';

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

        bool success = await HardwareSimulator.setCustomDisplayConfigs(newConfigs);
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

        if (!success){
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
        VLOG0("恢复显示器配置失败，${retryInterval.inMilliseconds}ms后重试 (${retryCount}/$maxRetries)");
        await Future.delayed(retryInterval);
      }
    }
    
    VLOG0("恢复显示器配置失败，已达到最大重试次数: $maxRetries");
  }

  Future<void> _loadCurrentMultiDisplayMode() async {
    try {
      MultiDisplayMode mode = await HardwareSimulator.getCurrentMultiDisplayMode();
      VLOG0('Current multi-display mode: $mode');
    } catch (e) {
      VLOG0('Failed to load current multi-display mode: $e');
    }
  }

  Future<void> _setMultiDisplayMode(MultiDisplayMode mode) async {
      await HardwareSimulator.setMultiDisplayMode(mode);
      await _loadCurrentMultiDisplayMode();
  }

  static Future<void> startStreaming(Device target, StreamedSettings settings) async {
    // === DEBUG LOGGING START ===
    VLOG0('[STREAM_DEBUG] ========================================');
    VLOG0('[STREAM_DEBUG] startStreaming called!');
    VLOG0('[STREAM_DEBUG] target.websocketSessionid: ${target.websocketSessionid}');
    VLOG0('[STREAM_DEBUG] target.devicename: ${target.devicename}');
    VLOG0('[STREAM_DEBUG] ApplicationInfo.connectable: ${ApplicationInfo.connectable}');
    VLOG0('[STREAM_DEBUG] settings.targetScreenId: ${settings.screenId}');
    VLOG0('[STREAM_DEBUG] settings.streamMode: ${settings.streamMode}');
    VLOG0('[STREAM_DEBUG] settings.customScreen: ${settings.customScreenWidth}x${settings.customScreenHeight}');
    VLOG0('[STREAM_DEBUG] settings.connectPassword: ${settings.connectPassword}');
    VLOG0('[STREAM_DEBUG] StreamingSettings.connectPasswordHash: ${StreamingSettings.connectPasswordHash}');
    if (settings.connectPassword != null) {
      VLOG0('[STREAM_DEBUG] Hash of received password: ${HashUtil.hash(settings.connectPassword!)}');
    }
    // === DEBUG LOGGING END ===

    try {
      bool allowConnect = ApplicationInfo.connectable;
      if (!allowConnect) {
        VLOG0('[STREAM_DEBUG] REJECTED: allowConnect is false!');
        return;
      }
      if (settings.connectPassword == null) {
        VLOG0('[STREAM_DEBUG] REJECTED: connectPassword is null!');
        return;
      }
      if (settings.screenId == null) {
        VLOG0('[STREAM_DEBUG] REJECTED: targetScreenId is null!');
        return;
      }
      if (StreamingSettings.connectPasswordHash !=
          HashUtil.hash(settings.connectPassword!)) {
        VLOG0('[STREAM_DEBUG] REJECTED: password hash mismatch!');
        VLOG0('[STREAM_DEBUG] Expected: ${StreamingSettings.connectPasswordHash}');
        VLOG0('[STREAM_DEBUG] Received: ${HashUtil.hash(settings.connectPassword!)}');
        return;
      }
      VLOG0(
          '[STREAM_DEBUG] PASSED: All validation checks OK, proceeding to create session...');
    } catch (e, stack) {
      VLOG0('[STREAM_DEBUG] validation exception: $e\n$stack');
      return;
    }

    try {
      await _lock.synchronized(() async {
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
          int? virtualDisplayId = await _createVirtualDisplay(width, height);
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
        if (!localVideoStreams.containsKey(settings.screenId!)) {
          final Map<String, dynamic> mediaConstraints;
          if (AppPlatform.isWeb) {
            mediaConstraints = {
              'audio': false,
              'video': {
                'frameRate': {'ideal': settings.framerate, 'max': settings.framerate}
              }
            };
          } else {
            var sources;
            try {
              VLOG0('[STREAM_DEBUG] Calling desktopCapturer.getSources(types: [Screen])...');
              await NodeAgentService.remoteLog('INFO', '[v3.19] 准备调用 desktopCapturer.getSources');
              sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
              await NodeAgentService.remoteLog('INFO', '[v3.19] getSources 成功', {'count': sources.length});
              VLOG0('[STREAM_DEBUG] desktopCapturer.getSources returned ${sources.length} sources');
            } catch (e, stack) {
              await NodeAgentService.remoteLog('ERROR', '[v3.19] getSources 崩溃', {'error': e.toString()});
              VLOG0('desktopCapturer.getSources failed: $e\n$stack');
              return;
            }

            final isVirtualDisplayMode = settings.streamMode == VDISPLAY_OCCUPY ||
                settings.streamMode == VDSIPLAY_EXTEND;

            if (!isVirtualDisplayMode) {
              // Default mode: do not touch system display config; just validate.
              if (sources.isEmpty) {
                await NodeAgentService.remoteLog('WARN', '[v3.19] 屏幕源为空');
                VLOG0(
                    'No screen sources found (desktopCapturer.getSources returned empty).');
                return;
              }
              if (settings.screenId! < 0 || settings.screenId! >= sources.length) {
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
                    _removeVirtualDisplay(virtualDisplayIds[settings.screenId]!);
                    virtualDisplayIds.remove(settings.screenId);
                  }
                  return;
                }

                try {
                  sources =
                      await desktopCapturer.getSources(types: [SourceType.Screen]);
                } catch (e, stack) {
                  VLOG0('desktopCapturer.getSources retry failed: $e\n$stack');
                  return;
                }
              }

              // 独占模式，需要重置新显示器为主显示器
              if (settings.streamMode == VDISPLAY_OCCUPY) {
                try {
                  await Future.delayed(const Duration(milliseconds: 500));
                  sources =
                      await desktopCapturer.getSources(types: [SourceType.Screen]);
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
                      await Future.delayed(const Duration(milliseconds: 500));
                      sources = await desktopCapturer.getSources(
                          types: [SourceType.Screen]);
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
              if (settings.screenId! < 0 || settings.screenId! >= sources.length) {
                VLOG0(
                    'Invalid targetScreenId=${settings.screenId} (available screens=${sources.length}) after virtual display setup.');
                return;
              }
            }

            final source = sources[settings.screenId!];
            mediaConstraints = <String, dynamic>{
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
          }
          try {
            VLOG0('[STREAM_DEBUG] Calling navigator.mediaDevices.getDisplayMedia(...)');
            await NodeAgentService.remoteLog('INFO', '[v3.19] 准备调用 getDisplayMedia');
            localVideoStreams[settings.screenId!] =
                await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
            await NodeAgentService.remoteLog('INFO', '[v3.19] getDisplayMedia 成功');
            localVideoStreamsCount[settings.screenId!] = 1;
          } catch (e) {
            await NodeAgentService.remoteLog('ERROR', '[v3.19] getDisplayMedia 失败', {'error': e.toString()});
            //This happens on Web when user choose not to share the content.
            VLOG0("getDisplayMedia failed.$e");
            return;
          }
        } else {
          //TODO:串流过程中显示器配置发生改变如何考虑?
          localVideoStreamsCount[settings.screenId!] =
              localVideoStreamsCount[settings.screenId!]! + 1;
        }
        await NodeAgentService.remoteLog('INFO', '[v3.19] 准备调用 session.acceptRequest (发送 offer)');
        StreamingSession session = StreamingSession(target, ApplicationInfo.thisDevice);
        cursorImageHookID++;
        session.cursorImageHookID = cursorImageHookID;
        cursorPositionUpdatedHookID++;
        session.cursorPositionUpdatedHookID = cursorPositionUpdatedHookID;
        session.acceptRequest(settings);
        await NodeAgentService.remoteLog('INFO', '[v3.19] acceptRequest 已调用，offer 应已发送');
        sessions[target.websocketSessionid] = session;
        setCurrentStreamedState(sessions.length);
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
