import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../entities/device.dart';
import '../../services/streaming_manager.dart';

part 'streaming_event.dart';
part 'streaming_state.dart';

class StreamingBloc extends Bloc<StreamingEvent, StreamingState> {
  final StreamingManager _streamingManager;

  StreamingBloc(this._streamingManager) : super(StreamingInitial()) {
    on<StreamingStartRequested>(_onStreamingStartRequested);
    on<StreamingStopRequested>(_onStreamingStopRequested);
  }

  Future<void> _onStreamingStartRequested(
    StreamingStartRequested event,
    Emitter<StreamingState> emit,
  ) async {
    emit(StreamingLoading());
    try {
      StreamingManager.startStreaming(event.device);
      emit(const StreamingActionSuccess("Streaming started"));
    } catch (e) {
      emit(StreamingFailure(e.toString()));
    }
  }

  Future<void> _onStreamingStopRequested(
    StreamingStopRequested event,
    Emitter<StreamingState> emit,
  ) async {
    emit(StreamingLoading());
    try {
      StreamingManager.stopStreaming(event.device);
      emit(const StreamingActionSuccess("Streaming stopped"));
    } catch (e) {
      emit(StreamingFailure(e.toString()));
    }
  }
}
