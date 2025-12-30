import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:slc/services/admin_service.dart';

part 'device_control_event.dart';
part 'device_control_state.dart';

class DeviceControlBloc extends Bloc<DeviceControlEvent, DeviceControlState> {
  final AdminService _adminService;

  DeviceControlBloc(this._adminService) : super(DeviceControlInitial()) {
    on<ReleaseDevice>(_onReleaseDevice);
    on<RebootDevice>(_onRebootDevice);
  }

  Future<void> _onReleaseDevice(ReleaseDevice event, Emitter<DeviceControlState> emit) async {
    emit(DeviceControlLoading());
    try {
      await _adminService.forceReleaseNode(event.deviceId);
      emit(const DeviceControlSuccess('已强制释放并触发节点回收'));
    } catch (e) {
      emit(DeviceControlFailure(e.toString()));
    }
  }

  Future<void> _onRebootDevice(RebootDevice event, Emitter<DeviceControlState> emit) async {
    emit(DeviceControlLoading());
    try {
      await _adminService.rebootNode(event.deviceId);
      emit(const DeviceControlSuccess('已下发重启指�?));
    } catch (e) {
      emit(DeviceControlFailure(e.toString()));
    }
  }
}
