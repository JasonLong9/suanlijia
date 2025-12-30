part of 'streaming_bloc.dart';

abstract class StreamingState extends Equatable {
  const StreamingState();
  
  @override
  List<Object> get props => [];
}

class StreamingInitial extends StreamingState {}

class StreamingLoading extends StreamingState {}

class StreamingActionSuccess extends StreamingState {
  final String message;

  const StreamingActionSuccess(this.message);

  @override
  List<Object> get props => [message];
}

class StreamingFailure extends StreamingState {
  final String error;

  const StreamingFailure(this.error);

  @override
  List<Object> get props => [error];
}
