import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:slc/entities/device.dart';
import 'package:slc/services/marketplace_service.dart';
import 'package:slc/services/websocket_service.dart';
import 'package:slc/services/streaming_manager.dart';
import 'package:slc/services/webrtc_service.dart';
import 'package:slc/services/app_info_service.dart';
import 'package:slc/utils/widgets/device_tile_page.dart';

part 'device_list_event.dart';
part 'device_list_state.dart';

class DeviceListBloc extends Bloc<DeviceListEvent, DeviceListState> {
  final WebSocketService _webSocketService;
  final MarketplaceService _marketplaceService;
  final StreamingManager _streamingManager;

  DeviceListBloc(this._webSocketService, this._marketplaceService, this._streamingManager) : super(DeviceListInitial()) {
    on<LoadDevices>(_onLoadDevices);
    on<UpdateMyDevices>(_onUpdateMyDevices);
    on<LoadPublicDevices>(_onLoadPublicDevices);
    on<RentDevice>(_onRentDevice);

    _webSocketService.onDeviceListchanged = (list) {
      add(UpdateMyDevices(list));
    };
  }

  Future<void> _onLoadDevices(LoadDevices event, Emitter<DeviceListState> emit) async {
    emit(DeviceListLoading());
    add(LoadPublicDevices());
    // My devices will be updated via WebSocket callback
  }

  void _onUpdateMyDevices(UpdateMyDevices event, Emitter<DeviceListState> emit) {
    final List<Device> newDeviceList = [];
    for (Map device in event.devices) {
        if (device['connective'] == false &&
            device['connection_id'] !=
                ApplicationInfo.thisDevice.websocketSessionid) {
          continue;
        }
        Device deviceInstance;
        if (WebrtcService.streams.containsKey(device['connection_id'])) {
           deviceInstance =
              _streamingManager.sessions[device['connection_id']]!.controlled;
          deviceInstance.devicename = device['device_name'];
          deviceInstance.connective = device['connective'];
          deviceInstance.screencount = device['screen_count'];
        } else if (device['connection_id'] == DeviceSelectManager.lastSelectedDevice?.websocketSessionid
          || (AppStateService.lastwebsocketSessionid != null && AppStateService.lastwebsocketSessionid == DeviceSelectManager.lastSelectedDevice?.websocketSessionid
          && device['connection_id'] == AppStateService.websocketSessionid)) {
          deviceInstance = DeviceSelectManager.lastSelectedDevice!;
          deviceInstance.devicename = device['device_name'];
          deviceInstance.connective = device['connective'];
          deviceInstance.screencount = device['screen_count'];
          deviceInstance.websocketSessionid = device['connection_id'];
        }
        else {
          deviceInstance = Device(
              uid: device['owner_id'],
              nickname: device['owner_nickname'],
              devicename: device['device_name'],
              devicetype: device['device_type'],
              websocketSessionid: device['connection_id'],
              connective: device['connective'],
              screencount: device['screen_count']);
        }
        newDeviceList.add(deviceInstance);
    }

    if (state is DeviceListLoaded) {
      emit((state as DeviceListLoaded).copyWith(myDevices: newDeviceList));
    } else {
      emit(DeviceListLoaded(myDevices: newDeviceList));
    }
  }

  Future<void> _onLoadPublicDevices(LoadPublicDevices event, Emitter<DeviceListState> emit) async {
    try {
      final publicDevices = await _marketplaceService.fetchPublicDevices();
      if (state is DeviceListLoaded) {
        emit((state as DeviceListLoaded).copyWith(publicDevices: publicDevices));
      } else {
        emit(DeviceListLoaded(publicDevices: publicDevices));
      }
    } catch (e) {
      emit(DeviceListError(e.toString()));
    }
  }

  Future<void> _onRentDevice(RentDevice event, Emitter<DeviceListState> emit) async {
    try {
      final success = await _marketplaceService.rentDevice(event.deviceId);
      if (success) {
        emit(RentSuccess('Device rented successfully!'));
        // Reload public devices to update status
        add(LoadPublicDevices());
      } else {
        emit(RentFailure('Failed to rent device.'));
      }
    } catch (e) {
      emit(RentFailure(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _webSocketService.onDeviceListchanged = null;
    return super.close();
  }
}
