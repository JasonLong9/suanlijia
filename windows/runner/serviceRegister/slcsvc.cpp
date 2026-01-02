#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <wtsapi32.h>
#include <psapi.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

SERVICE_STATUS_HANDLE service_status_handle;
SERVICE_STATUS service_status;
HANDLE stop_event;

#define SERVICE_NAME  TEXT("SLCSvc")

static void AppendLogLine(const char* line) {
    // Best-effort file logging for service diagnostics.
    // Path: C:\ProgramData\SLC\logs\slcsvc.log
    CreateDirectoryW(L"C:\\ProgramData\\SLC", NULL);
    CreateDirectoryW(L"C:\\ProgramData\\SLC\\logs", NULL);
    HANDLE file = CreateFileW(
        L"C:\\ProgramData\\SLC\\logs\\slcsvc.log",
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    DWORD written = 0;
    WriteFile(file, line, (DWORD)strlen(line), &written, NULL);
    CloseHandle(file);
}

static void Logf(const char* fmt, ...) {
    SYSTEMTIME st;
    GetLocalTime(&st);

    char msg[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msg, sizeof(msg), fmt, args);
    va_end(args);

    char line[1200];
    snprintf(
        line,
        sizeof(line),
        "[%04u-%02u-%02u %02u:%02u:%02u.%03u] %s\r\n",
        st.wYear,
        st.wMonth,
        st.wDay,
        st.wHour,
        st.wMinute,
        st.wSecond,
        st.wMilliseconds,
        msg);
    AppendLogLine(line);
}

DWORD WINAPI HandlerEx(DWORD dwControl, DWORD dwEventType, LPVOID lpEventData, LPVOID lpContext) {
    switch (dwControl) {
    case SERVICE_CONTROL_INTERROGATE:
        return NO_ERROR;

    case SERVICE_CONTROL_STOP:
        // Let SCM know we're stopping in up to 30 seconds
        service_status.dwCurrentState = SERVICE_STOP_PENDING;
        service_status.dwControlsAccepted = 0;
        service_status.dwWaitHint = 30 * 1000;
        SetServiceStatus(service_status_handle, &service_status);

        // Trigger ServiceMain() to start cleanup
        SetEvent(stop_event);
        return NO_ERROR;

    default:
        return NO_ERROR;
    }
}

static bool SessionHasUser(DWORD session_id) {
    LPTSTR user = NULL;
    DWORD bytes = 0;
    if (!WTSQuerySessionInformation(WTS_CURRENT_SERVER_HANDLE, session_id, WTSUserName, &user, &bytes)) {
        return false;
    }
    const bool ok = (user != NULL && user[0] != 0);
    if (user) {
        WTSFreeMemory(user);
    }
    return ok;
}

static DWORD FindBestSessionId() {
    // Prefer the active console session if available.
    const DWORD console_session_id = WTSGetActiveConsoleSessionId();
    if (console_session_id != 0xFFFFFFFF && console_session_id != 0) {
        return console_session_id;
    }

    // Fallback: enumerate sessions and pick an active session with a logged-in user.
    PWTS_SESSION_INFO sessions = NULL;
    DWORD count = 0;
    if (!WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, &sessions, &count)) {
        return 0xFFFFFFFF;
    }

    DWORD best = 0xFFFFFFFF;
    // Pass 1: WTSActive sessions.
    for (DWORD i = 0; i < count; i++) {
        const DWORD sid = sessions[i].SessionId;
        if (sid == 0) continue; // session 0 is for services
        if (sessions[i].State != WTSActive) continue;
        if (!SessionHasUser(sid)) continue;
        best = sid;
        break;
    }
    // Pass 2: WTSConnected sessions (RDP connected but not necessarily active).
    if (best == 0xFFFFFFFF) {
        for (DWORD i = 0; i < count; i++) {
            const DWORD sid = sessions[i].SessionId;
            if (sid == 0) continue;
            if (sessions[i].State != WTSConnected) continue;
            if (!SessionHasUser(sid)) continue;
            best = sid;
            break;
        }
    }

    if (sessions) {
        WTSFreeMemory(sessions);
    }
    return best;
}

HANDLE DuplicateTokenForConsoleSession() {
    const DWORD target_session_id = FindBestSessionId();
    if (target_session_id == 0xFFFFFFFF || target_session_id == 0) {
        // No interactive session yet (or only service session 0).
        Logf("No usable interactive session found (target_session_id=%lu)", (unsigned long)target_session_id);
        return NULL;
    }

    HANDLE current_token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_DUPLICATE, &current_token)) {
        Logf("OpenProcessToken failed: %lu", (unsigned long)GetLastError());
        return NULL;
    }

    // Duplicate our own LocalSystem token
    HANDLE new_token;
    if (!DuplicateTokenEx(current_token, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation, TokenPrimary, &new_token)) {
        CloseHandle(current_token);
        Logf("DuplicateTokenEx failed: %lu", (unsigned long)GetLastError());
        return NULL;
    }

    CloseHandle(current_token);

    // Change the duplicated token to the target session ID.
    if (!SetTokenInformation(new_token, TokenSessionId, &target_session_id, sizeof(target_session_id))) {
        CloseHandle(new_token);
        Logf("SetTokenInformation(TokenSessionId=%lu) failed: %lu", (unsigned long)target_session_id, (unsigned long)GetLastError());
        return NULL;
    }

    Logf("Launching slc.exe in session %lu", (unsigned long)target_session_id);
    return new_token;
}

VOID WINAPI ServiceMain(DWORD dwArgc, LPTSTR* lpszArgv) {
    stop_event = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (stop_event == NULL) {
        return;
    }

    service_status_handle = RegisterServiceCtrlHandlerEx(SERVICE_NAME, HandlerEx, NULL);
    if (service_status_handle == NULL) {
        return;
    }

    // Tell SCM we're running
    service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    service_status.dwServiceSpecificExitCode = 0;
    service_status.dwWin32ExitCode = NO_ERROR;
    service_status.dwWaitHint = 0;
    service_status.dwControlsAccepted = SERVICE_ACCEPT_STOP;
    service_status.dwCheckPoint = 0;
    service_status.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(service_status_handle, &service_status);
    Logf("Service started");

    // Loop every 3 seconds until the stop event is set or slc.exe is running
    while (WaitForSingleObject(stop_event, 3000) != WAIT_OBJECT_0) {
        auto console_token = DuplicateTokenForConsoleSession();
        if (console_token == NULL) {
            continue;
        }

        STARTUPINFOW startup_info = {};
        startup_info.cb = sizeof(startup_info);
        startup_info.lpDesktop = (LPWSTR)L"winsta0\\default";
        startup_info.dwFlags = STARTF_USESHOWWINDOW;
        startup_info.wShowWindow = SW_HIDE;

        PROCESS_INFORMATION process_info;
        // Pass --headless to trigger headless mode (no GUI, no window)
        // Note: When lpApplicationName is provided, lpCommandLine must still 
        // include the program name as first token (argv[0]) for proper argument parsing
        WCHAR cmdLine[] = L"\"slc.exe\" --headless";
        if (!CreateProcessAsUserW(console_token,
            L"slc.exe",
            cmdLine,
            NULL,
            NULL,
            FALSE,
            ABOVE_NORMAL_PRIORITY_CLASS | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
            NULL,
            NULL,
            &startup_info,
            &process_info)) {
            CloseHandle(console_token);
            Logf("CreateProcessAsUserW failed: %lu", (unsigned long)GetLastError());
            continue;
        }

        // Close handles that are no longer needed
        CloseHandle(console_token);
        CloseHandle(process_info.hThread);

        // Wait for either the stop event to be set or ClodPlayPlus.exe to terminate
        const HANDLE wait_objects[] = { stop_event, process_info.hProcess };
        switch (WaitForMultipleObjects(_countof(wait_objects), wait_objects, FALSE, INFINITE)) {
        case WAIT_OBJECT_0:
            // The service is shutting down, so terminate ClodPlayPlus.exe.
            // TODO: Send a graceful exit request and only terminate forcefully as a last resort.
            TerminateProcess(process_info.hProcess, ERROR_PROCESS_ABORTED);
            break;

        case WAIT_OBJECT_0 + 1:
            // CloudPlayPlus terminated itself.
            break;
        }

        CloseHandle(process_info.hProcess);
    }

    // Let SCM know we've stopped
    service_status.dwCurrentState = SERVICE_STOPPED;
    SetServiceStatus(service_status_handle, &service_status);
    Logf("Service stopped");
}

int main(int argc, char* argv[])
{
    static const SERVICE_TABLE_ENTRY service_table[] = {
      { (LPWSTR)SERVICE_NAME, ServiceMain },
      { NULL, NULL }
    };

    // By default, services have their current directory set to %SYSTEMROOT%\System32.
    // We want to use the directory where CloudPlayPlus.exe is located instead of system32.
    // This requires stripping off 2 path components: the file name and the last folder
    WCHAR module_path[MAX_PATH];
    GetModuleFileNameW(NULL, module_path, _countof(module_path));
    for (auto i = 0; i < 1; i++) {
        auto last_sep = wcsrchr(module_path, '\\');
        if (last_sep) {
            *last_sep = 0;
        }
    }
    SetCurrentDirectoryW(module_path);

    // Trigger our ServiceMain()
    return StartServiceCtrlDispatcher(service_table);
}
