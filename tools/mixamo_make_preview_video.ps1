param([ValidateSet('left_turn','right_turn','left_turn_90','right_turn_90')][string]$Clip='right_turn')
$ErrorActionPreference='Stop'
$taskProject=Split-Path -Parent $PSScriptRoot
$taskShots=[IO.Path]::GetFullPath((Join-Path $taskProject 'shots'))
$taskFrames=[IO.Path]::GetFullPath((Join-Path $taskShots ('mixamo-detail-'+$Clip)))
if (-not $taskFrames.StartsWith($taskShots+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Video path escaped experiment shots'}
$taskSequence=Get-Content -LiteralPath (Join-Path $taskFrames 'sequence.json') -Raw | ConvertFrom-Json
if ($taskSequence.original_time_hz -ne 60 -or $taskSequence.fps_time_warp -ne $false -or $taskSequence.failures -ne 0) {throw 'Capture is not a clean original-time 60Hz experiment'}
$taskFirst=[int]$taskSequence.capture_range[0]
$taskCount=[int]$taskSequence.capture_range[1]-$taskFirst+1
$taskEncodeCount=$taskCount
$taskEndpointOnly=$false
if ($taskFirst -eq 0 -and [Math]::Abs([double]$taskSequence.frames[-1].original_time_s-[double]$taskSequence.original_duration_s) -lt .000001) {
  # The endpoint t=duration is a boundary sample, not another 1/60s interval.
  # Retain its PNG, but avoid adding an extra held frame to the full clip video.
  $taskEncodeCount=[Math]::Max(1,$taskCount-1)
  $taskEndpointOnly=$true
}
$taskOutput=Join-Path $taskFrames 'preview.mp4'
$taskFfmpeg=(Get-Command ffmpeg -ErrorAction Stop).Source
# Encode original-time intervals once, preserving the exact complete-clip length.
# No loops, slow-motion interpolation, FPS-conversion filter or image resampling.
& $taskFfmpeg -hide_banner -loglevel error -y -framerate 60 -start_number $taskFirst -i (Join-Path $taskFrames 'frame-%04d.png') -frames:v $taskEncodeCount -c:v libx264 -threads 2 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart $taskOutput
if ($LASTEXITCODE -ne 0) {throw "ffmpeg exited $LASTEXITCODE"}
$taskVersion=(& $taskFfmpeg -version | Select-Object -First 1)
$taskRecord=[ordered]@{clip=$Clip;video=$taskOutput;source_capture='sequence.json';source_first_frame=$taskFirst;source_capture_frames=$taskCount;encoded_frames=$taskEncodeCount;terminal_boundary_png_only=$taskEndpointOnly;fps=60;original_clip_duration_s=[double]$taskSequence.original_duration_s;encoded_duration_s=$taskEncodeCount/60.0;fps_time_warp=$false;loop=$false;physics_controller_connected=$false;is_pose_sequence_not_gameplay_video=$true;accepted_for_production=$false;ffmpeg=$taskVersion;video_sha256=(Get-FileHash -LiteralPath $taskOutput -Algorithm SHA256).Hash.ToLowerInvariant()}
$taskRecord | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskFrames 'video_record.json') -Encoding utf8
$taskRecord | ConvertTo-Json -Compress
