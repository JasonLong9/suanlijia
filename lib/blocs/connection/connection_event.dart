part of 'connection_bloc.dart';

abstract class ConnectionEvent extends Equatable {
  const ConnectionEvent();

  @override
  List<Object> get props => [];
}

class ConnectionConnectRequested extends ConnectionEvent {}

class ConnectionDisconnectRequested extends ConnectionEvent {}

class ConnectionDeviceListUpdated extends ConnectionEvent {
  final List<dynamic> devices;

  const ConnectionDeviceListUpdated(this.devices);

  @override
  List<Object> get props => [devices];
}
