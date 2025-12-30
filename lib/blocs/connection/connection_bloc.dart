import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/websocket_service.dart';

part 'connection_event.dart';
part 'connection_state.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  final WebSocketService _webSocketService;

  ConnectionBloc(this._webSocketService) : super(ConnectionInitial()) {
    on<ConnectionConnectRequested>(_onConnectionConnectRequested);
    on<ConnectionDisconnectRequested>(_onConnectionDisconnectRequested);
    on<ConnectionDeviceListUpdated>(_onConnectionDeviceListUpdated);

    // Listen to device list changes from WebSocketService
    WebSocketService.onDeviceListchanged = (list) {
      add(ConnectionDeviceListUpdated(list));
    };
  }

  Future<void> _onConnectionConnectRequested(
    ConnectionConnectRequested event,
    Emitter<ConnectionState> emit,
  ) async {
    emit(ConnectionConnecting());
    try {
      WebSocketService.init();
      // Wait for connection or just emit connecting? 
      // WebSocketService.init is async but returns void and doesn't await connection fully in current impl.
      // We rely on onDeviceListchanged or onConnected callback to know if connected.
      // For now, let's assume it connects eventually.
    } catch (e) {
      emit(ConnectionFailure(e.toString()));
    }
  }

  Future<void> _onConnectionDisconnectRequested(
    ConnectionDisconnectRequested event,
    Emitter<ConnectionState> emit,
  ) async {
    await WebSocketService.disconnect();
    emit(ConnectionDisconnected());
  }

  Future<void> _onConnectionDeviceListUpdated(
    ConnectionDeviceListUpdated event,
    Emitter<ConnectionState> emit,
  ) async {
    emit(ConnectionConnected(devices: event.devices));
  }
}
