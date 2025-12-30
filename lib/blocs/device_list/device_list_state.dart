part of 'device_list_bloc.dart';

abstract class DeviceListState extends Equatable {
  const DeviceListState();
  
  @override
  List<Object> get props => [];
}

class DeviceListInitial extends DeviceListState {}

class DeviceListLoading extends DeviceListState {}

class DeviceListLoaded extends DeviceListState {
  final List<Device> myDevices;
  final List<dynamic> publicDevices;

  const DeviceListLoaded({
    this.myDevices = const [],
    this.publicDevices = const [],
  });

  DeviceListLoaded copyWith({
    List<Device>? myDevices,
    List<dynamic>? publicDevices,
  }) {
    return DeviceListLoaded(
      myDevices: myDevices ?? this.myDevices,
      publicDevices: publicDevices ?? this.publicDevices,
    );
  }

  @override
  List<Object> get props => [myDevices, publicDevices];
}

class DeviceListError extends DeviceListState {
  final String message;

  const DeviceListError(this.message);

  @override
  List<Object> get props => [message];
}

class RentSuccess extends DeviceListState {
  final String message;

  const RentSuccess(this.message);

  @override
  List<Object> get props => [message];
}

class RentFailure extends DeviceListState {
  final String message;

  const RentFailure(this.message);

  @override
  List<Object> get props => [message];
}
