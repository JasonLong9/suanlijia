part of 'device_list_bloc.dart';

abstract class DeviceListEvent extends Equatable {
  const DeviceListEvent();

  @override
  List<Object> get props => [];
}

class LoadDevices extends DeviceListEvent {}

class UpdateMyDevices extends DeviceListEvent {
  final List<dynamic> devices;

  const UpdateMyDevices(this.devices);

  @override
  List<Object> get props => [devices];
}

class LoadPublicDevices extends DeviceListEvent {}

class RentDevice extends DeviceListEvent {
  final String deviceId;

  const RentDevice(this.deviceId);

  @override
  List<Object> get props => [deviceId];
}
