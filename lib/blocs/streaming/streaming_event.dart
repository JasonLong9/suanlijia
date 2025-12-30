part of 'streaming_bloc.dart';

abstract class StreamingEvent extends Equatable {
  const StreamingEvent();

  @override
  List<Object> get props => [];
}

class StreamingStartRequested extends StreamingEvent {
  final Device device;

  const StreamingStartRequested(this.device);

  @override
  List<Object> get props => [device];
}

class StreamingStopRequested extends StreamingEvent {
  final Device device;

  const StreamingStopRequested(this.device);

  @override
  List<Object> get props => [device];
}
