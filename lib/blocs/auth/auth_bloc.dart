import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/login_service.dart';
import '../../services/app_info_service.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginService _loginService;

  AuthBloc(this._loginService) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onAuthLoginRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final isLoggedIn = await LoginService.tryLoginWithCachedToken();
      if (isLoggedIn) {
        emit(AuthAuthenticated(ApplicationInfo.user.nickname)); 
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onAuthLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final result = await LoginService.login(event.username, event.password);
      if (result['status'] == 'success') {
        emit(AuthAuthenticated(event.username));
      } else {
        emit(AuthFailure(result['message'] ?? 'Login failed'));
      }
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    // await _loginService.logout(); // Implement logout in LoginService if needed
    emit(AuthUnauthenticated());
  }
}
