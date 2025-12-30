part of 'device_control_bloc.dart';

abstract class DeviceControlEvent extends Equatable {
  const DeviceControlEvent();

  @override
  List<Object> get props => [];
}

class ReleaseDevice extends DeviceControlEvent {
  final String deviceId;

  const ReleaseDevice(this.deviceId);

  @override
  List<Object> get props => [deviceId];
}

class RebootDevice extends DeviceControlEvent {
  final String deviceId;

  const RebootDevice(this.deviceId);

  @override
  List<Object> get props => [deviceId];
}
