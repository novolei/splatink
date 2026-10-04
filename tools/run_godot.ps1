param([string]$EnginePath = 'D:\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe',[Parameter(ValueFromRemainingArguments=$true)][string[]]$GodotArgs)
$taskEngine = $EnginePath
$taskLock = [System.Threading.Mutex]::new($false,'Local\SplatinkEngineInvocation')
$taskAcquired = $false
try {
  $taskAcquired = $taskLock.WaitOne(60000)
  if (-not $taskAcquired) { throw 'Another Splatink verification is running.' }
  if ($taskEngine -notmatch '(?i)(?:_console|\.console)\.exe$') {
    # PowerShell does not wait for GUI subsystem executables invoked with &.
    $taskArguments = @($GodotArgs | ForEach-Object { '"' + $_.Replace('"','\"') + '"' })
    $taskProcess = Start-Process -FilePath $taskEngine -ArgumentList $taskArguments -WindowStyle Hidden -PassThru -Wait
    exit $taskProcess.ExitCode
  } else {
    & $taskEngine @GodotArgs
    exit $LASTEXITCODE
  }
} finally {
  if ($taskAcquired) { $taskLock.ReleaseMutex() }
  $taskLock.Dispose()
}
