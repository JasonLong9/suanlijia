part of 'connection_bloc.dart';

abstract class ConnectionState extends Equatable {
  const ConnectionState();
  
  @override
  List<Object> get props => [];
}

class ConnectionInitial extends ConnectionState {}

class ConnectionConnecting extends ConnectionState {}

class ConnectionConnected extends ConnectionState {
  final List<dynamic> devices;

  const ConnectionConnected({this.devices = const []});

  @override
  List<Object> get props => [devices];
}

class ConnectionDisconnected extends ConnectionState {}

class ConnectionFailure extends ConnectionState {
  final String message;

  const ConnectionFailure(this.message);

  @override
  List<Object> get props => [message];
}
