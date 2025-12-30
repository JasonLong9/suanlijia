part of 'device_control_bloc.dart';

abstract class DeviceControlState extends Equatable {
  const DeviceControlState();
  
  @override
  List<Object> get props => [];
}

class DeviceControlInitial extends DeviceControlState {}

class DeviceControlLoading extends DeviceControlState {}

class DeviceControlSuccess extends DeviceControlState {
  final String message;

  const DeviceControlSuccess(this.message);

  @override
  List<Object> get props => [message];
}

class DeviceControlFailure extends DeviceControlState {
  final String message;

  const DeviceControlFailure(this.message);

  @override
  List<Object> get props => [message];
}
