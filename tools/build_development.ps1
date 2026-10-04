param([ValidateSet('Windows','Android')][string]$Platform='Windows',[switch]$Probe,[switch]$NativeLocomotionMM,[string]$ResumeBuild='')
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($ResumeBuild){
 $taskBuild=[IO.Path]::GetFullPath($ResumeBuild)
 $taskBuildRoot=[IO.Path]::GetFullPath((Join-Path $taskRoot 'builds'))+[IO.Path]::DirectorySeparatorChar
 if(!$taskBuild.StartsWith($taskBuildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Resume build must be inside this project builds directory'}
 $taskStage=Join-Path $taskBuild 'stage'
 $taskPortable=Join-Path $taskBuild 'engine'
 $taskOutput=Join-Path $taskBuild 'output'
 $taskStamp=Get-Content -LiteralPath (Join-Path $taskStage 'data\build_stamp.json') -Raw | ConvertFrom-Json
 if($taskStamp.platform -ne $Platform -or [bool]$taskStamp.probe -ne [bool]$Probe -or [bool]$taskStamp.native_locomotion_mm -ne [bool]$NativeLocomotionMM){throw 'Resume platform/probe/native locomotion must match the immutable snapshot'}
 if(!(Test-Path -LiteralPath (Join-Path $taskStage 'export_presets.cfg'))){throw 'Resume snapshot has no export presets'}
}else{
$taskId=[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+$Platform.ToLower()
$taskBuild=Join-Path $taskRoot ('builds\'+$taskId)
$taskStage=Join-Path $taskBuild 'stage'
$taskPortable=Join-Path $taskBuild 'engine'
$taskOutput=Join-Path $taskBuild 'output'
New-Item -ItemType Directory -Path $taskStage,$taskPortable,$taskOutput -Force | Out-Null
# A fresh destination avoids destructive mirroring and never touches the live editor cache.
& robocopy $taskRoot $taskStage /E /XD .godot .git .tools builds shots tools tests /XF export_presets.cfg /NFL /NDL /NJH /NJS /NP | Out-Null
if($LASTEXITCODE -gt 7){throw 'Staging copy failed'}
$taskOriginalEngine='D:\Godot_v4.7.1'
Copy-Item -LiteralPath (Join-Path $taskOriginalEngine 'Godot_v4.7.1-stable_win64_console.exe'),(Join-Path $taskOriginalEngine 'Godot_v4.7.1-stable_win64.exe') -Destination $taskPortable
New-Item -ItemType File -Path (Join-Path $taskPortable '_sc_') -Force | Out-Null
$taskEditorData=Join-Path $taskPortable 'editor_data'
New-Item -ItemType Directory -Path $taskEditorData -Force | Out-Null
if($Platform -eq 'Android'){
 $taskSdk='H:\GDP\mini-tanks\.tools\android-setup'
 $taskEditorSettings=@"
[gd_resource type="EditorSettings" format=3]
[resource]
export/android/java_sdk_path="$($taskSdk.Replace('\','/'))/jdk"
export/android/android_sdk_path="$($taskSdk.Replace('\','/'))/sdk"
export/android/debug_keystore="$($taskSdk.Replace('\','/'))/debug.keystore"
export/android/debug_keystore_user="androiddebugkey"
export/android/debug_keystore_pass="android"
"@
 [IO.File]::WriteAllText((Join-Path $taskEditorData 'editor_settings-4.7.tres'),$taskEditorSettings,[Text.UTF8Encoding]::new($false))
}
$taskTemplates=Join-Path $taskEditorData 'export_templates\4.7.1.stable'
New-Item -ItemType Directory -Path $taskTemplates -Force | Out-Null
$taskTemplateNames=if($Platform -eq 'Windows'){@('version.txt','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe')}else{@('version.txt','android_debug.apk','android_release.apk')}
foreach($taskTemplateName in $taskTemplateNames){Copy-Item -LiteralPath (Join-Path "$env:APPDATA\Godot\export_templates\4.7.1.stable" $taskTemplateName) -Destination $taskTemplates}
& 'C:\Program Files\nodejs\node.exe' (Join-Path $PSScriptRoot 'generate_export_presets.mjs') $taskStage
if($LASTEXITCODE){throw 'Preset generation failed'}
if($Probe){
 if($Platform -ne 'Android'){throw 'Probe mode is for the Android device run'}
 $taskPresets=Join-Path $taskStage 'export_presets.cfg'
 $taskPresetText=[IO.File]::ReadAllText($taskPresets)
 $taskPresetText=$taskPresetText.Replace('[preset.1.options]',"[preset.1.options]`ncommand_line/extra_args=`"-- --autostart=180 --autopilot --capture=user://phone-probe.png --capture-after=40`"")
 [IO.File]::WriteAllText($taskPresets,$taskPresetText,[Text.UTF8Encoding]::new($false))
}
$taskCommit=(& git -C (Split-Path $taskRoot) rev-parse HEAD 2>$null)
$taskStamp=@{id=$taskId;platform=$Platform;channel='development';probe=[bool]$Probe;native_locomotion_mm=[bool]$NativeLocomotionMM;engine='4.7.1.stable.official.a13da4feb';commit="$taskCommit-dirty";source='workspace snapshot';utc=[DateTime]::UtcNow.ToString('o')}
$taskStamp | ConvertTo-Json | Set-Content (Join-Path $taskStage 'data\build_stamp.json') -Encoding UTF8
}
$taskEngine=Join-Path $taskPortable 'Godot_v4.7.1-stable_win64_console.exe'
for($taskPass=1;$taskPass -le 2;$taskPass++){
 $taskLog=Join-Path $taskBuild "import-$taskPass.log"
 & (Join-Path $PSScriptRoot 'run_godot.ps1') -EnginePath $taskEngine -GodotArgs @('--headless','--path',$taskStage,'--editor','--import','--log-file',$taskLog) *>&1 | Out-File -LiteralPath ($taskLog+'.stdout') -Encoding utf8
 if($LASTEXITCODE -or (Select-String -LiteralPath @($taskLog,($taskLog+'.stdout')) -Pattern 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' -Quiet)){throw 'Staged import failed'}
}
$taskPreset=if($Platform -eq 'Windows'){'Windows Development'}else{'Android Development'}
$taskArtifact=Join-Path $taskOutput $(if($Platform -eq 'Windows'){'Splatink.exe'}else{'Splatink.apk'})
$taskLog=Join-Path $taskBuild 'export.log'
& (Join-Path $PSScriptRoot 'run_godot.ps1') -EnginePath $taskEngine -GodotArgs @('--headless','--path',$taskStage,'--export-debug',$taskPreset,$taskArtifact,'--log-file',$taskLog) *>&1 | Out-File -LiteralPath ($taskLog+'.stdout') -Encoding utf8
if($LASTEXITCODE -or !(Test-Path -LiteralPath $taskArtifact) -or (Select-String -LiteralPath @($taskLog,($taskLog+'.stdout')) -Pattern 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' -Quiet)){throw 'Development export failed'}
if($Platform -eq 'Windows'){
 foreach($taskSmoke in @('boot','match')){
  $taskLog=Join-Path $taskBuild "smoke-$taskSmoke.log"
  & (Join-Path $PSScriptRoot 'run_godot.ps1') -EnginePath $taskArtifact -GodotArgs @('--headless','--log-file',$taskLog,'--',"--smoke=$taskSmoke") *>&1 | Out-File -LiteralPath ($taskLog+'.stdout') -Encoding utf8
  if($LASTEXITCODE -or (Select-String -LiteralPath @($taskLog,($taskLog+'.stdout')) -Pattern 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' -Quiet) -or !(Select-String -LiteralPath $taskLog -Pattern '"passed":true' -Quiet)){throw 'Exported smoke failed'}
 }
 $taskLog=Join-Path $taskBuild 'smoke-gpu.log'
 $taskCapture=Join-Path $taskOutput 'smoke-gpu.png'
 $taskGpuArgs=@('--log-file',$taskLog,'--','--autostart=180','--autopilot','--benchmark-background','--nonpersistent',"--capture=$taskCapture",'--capture-after=12')
 if($NativeLocomotionMM){$taskGpuArgs+='--native-locomotion-mm'}
 & (Join-Path $PSScriptRoot 'run_godot.ps1') -EnginePath $taskArtifact -GodotArgs $taskGpuArgs *>&1 | Out-File -LiteralPath ($taskLog+'.stdout') -Encoding utf8
 if($LASTEXITCODE -or (Select-String -LiteralPath @($taskLog,($taskLog+'.stdout')) -Pattern 'SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:' -Quiet) -or !(Test-Path -LiteralPath $taskCapture)){throw 'Exported GPU run failed'}
 $taskGpu=Get-Content -LiteralPath (Join-Path $taskOutput 'smoke-gpu.json') -Raw | ConvertFrom-Json
 if($taskGpu.state -ne 'playing' -or $taskGpu.actors -ne 8 -or $taskGpu.screenshot_error -ne 0 -or $taskGpu.playing_seconds -lt 6 -or $taskGpu.focus_paused){throw 'Exported GPU match did not reach expected state'}
 if($NativeLocomotionMM -and $taskGpu.native_locomotion.active_actors -ne 8){throw 'Exported GPU match did not activate all eight native lower-body matchers'}
 if($NativeLocomotionMM){[IO.File]::WriteAllText((Join-Path $taskOutput 'Splatink-NativeMM.cmd'),"@echo off`r`n`"%~dp0Splatink.exe`" -- --native-locomotion-mm`r`n",[Text.UTF8Encoding]::new($false))}
}
$taskFiles=Get-ChildItem -LiteralPath $taskOutput -File | ForEach-Object {@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}}
$taskRecordName=if($Platform -eq 'Windows'){'build_record.json'}else{'export_record.json'}
@{stamp=$taskStamp;files=@($taskFiles);export='passed';smoke=$(if($Platform -eq 'Windows'){'boot, match and actual GPU run passed'}else{'device verification pending'})} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $taskOutput $taskRecordName) -Encoding UTF8
Write-Output "SPLATINK_BUILD $taskOutput"
