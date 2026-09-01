param(
  [string]$CodexHome = $null,
  [string]$InstallDir = $PSScriptRoot,
  [switch]$DiagnosticOnly,
  [string]$Profile = 'JEL'
)

$ErrorActionPreference = 'Stop'

if (-not $DiagnosticOnly) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
}

$safeProfile = ($Profile -replace '[^A-Za-z0-9_.-]', '_')
$script:RuntimeDir = Join-Path $env:LOCALAPPDATA (Join-Path 'JerEx' $safeProfile)
$script:LogDir = Join-Path $script:RuntimeDir 'logs'
$script:LogFile = Join-Path $script:LogDir 'JEL.log'
$script:Ui = $null

function Initialize-Runtime {
  New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
  if ((Test-Path $script:LogFile) -and (Get-Item $script:LogFile).Length -gt 1MB) {
    $archive = Join-Path $script:LogDir ('JEL-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    Move-Item -LiteralPath $script:LogFile -Destination $archive -Force
  }
}

function Write-Log {
  param([Parameter(Mandatory = $true)][string]$Message)
  $safeMessage = $Message -replace '(?i)(token|key|password|secret)=\S+', '$1=[redacted]'
  Add-Content -LiteralPath $script:LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $safeMessage) -Encoding UTF8
}

function Get-LauncherConfig {
  $defaults = [ordered]@{
    schemaVersion    = 1
    appName          = 'JerEx Launcher'
    displayName      = 'JEL'
    windowTitle      = 'JerEx Launcher'
    version          = '3.4.4'
    testUri          = 'https://www.example.com/'
    openAiTestUri    = 'https://api.openai.com/v1/models'
    chatGptTestUri   = 'https://chatgpt.com/'
    launchDelayMs    = 300
    checkingDelayMs  = 80
    statusTimeoutMs  = 900
    verifyTimeoutSec = 15
    portCandidates   = @(7897, 7892, 7890, 7891, 7898, 8080, 8888, 1080, 3128, 8081, 9090, 10808, 10809, 10810)
    proxyProtocols   = @('http', 'socks5h')
  }

  $configPath = Join-Path $InstallDir 'config.json'
  if (-not (Test-Path -LiteralPath $configPath)) {
    return [pscustomobject]$defaults
  }

  try {
    $loaded = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    foreach ($name in @($defaults.Keys)) {
      if ($null -ne $loaded.$name) {
        $defaults[$name] = $loaded.$name
      }
    }
  } catch {
    Write-Log "Config read failed; defaults used. $($_.Exception.Message)"
  }

  [pscustomobject]$defaults
}

function Resolve-CodexHome {
  param([string]$RequestedHome)
  $candidate = if ($RequestedHome) {
    $RequestedHome
  } elseif ($env:CODEX_HOME) {
    $env:CODEX_HOME
  } else {
    Join-Path $env:USERPROFILE '.codex'
  }

  $resolved = [System.IO.Path]::GetFullPath($candidate)
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "ChatGPT 配置目录不存在：$resolved"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $resolved 'config.toml'))) {
    throw "ChatGPT 配置目录中未找到 config.toml：$resolved"
  }
  $resolved
}

function Get-CodexAppInfo {
  $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $package) {
    throw '未检测到 ChatGPT Windows 应用。'
  }

  $applicationId = 'App'
  try {
    $manifest = Get-AppxPackageManifest -Package $package.PackageFullName
    $application = @($manifest.Package.Applications.Application) | Select-Object -First 1
    if ($application -and $application.Id) {
      $applicationId = [string]$application.Id
    }
  } catch {
    Write-Log "App manifest read failed; fallback application id used. $($_.Exception.Message)"
  }

  [pscustomobject]@{
    Version          = [string]$package.Version
    InstallLocation  = [string]$package.InstallLocation
    PackageFamilyName = [string]$package.PackageFamilyName
    AppUserModelId   = '{0}!{1}' -f $package.PackageFamilyName, $applicationId
  }
}

function Get-CodexAppProcesses {
  param([Parameter(Mandatory = $true)]$AppInfo)
  $installRoot = $AppInfo.InstallLocation.TrimEnd('\')
  @(Get-CimInstance Win32_Process -Filter "Name='codex.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)
  })
}

function New-Ui {
  param([Parameter(Mandatory = $true)]$Config)
  $form = New-Object System.Windows.Forms.Form
  $form.Text = $Config.windowTitle
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false
  $form.TopMost = $true
  $form.Width = 440
  $form.Height = 230
  $form.ShowInTaskbar = $false
  $form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)

  $iconPath = Join-Path (Join-Path $InstallDir 'assets') 'JerEx.ico'
  if (Test-Path -LiteralPath $iconPath) {
    try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch { }
  }

  $strip = New-Object System.Windows.Forms.Panel
  $strip.Dock = 'Top'
  $strip.Height = 18
  $strip.BackColor = [System.Drawing.Color]::FromArgb(20, 184, 166)
  $form.Controls.Add($strip)

  $header = New-Object System.Windows.Forms.Label
  $header.Location = New-Object System.Drawing.Point(24, 36)
  $header.Size = New-Object System.Drawing.Size(390, 32)
  $header.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
  $header.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
  $header.Text = '{0}  v{1}' -f $Config.displayName, $Config.version
  $form.Controls.Add($header)

  $detail = New-Object System.Windows.Forms.Label
  $detail.Location = New-Object System.Drawing.Point(24, 78)
  $detail.Size = New-Object System.Drawing.Size(390, 112)
  $detail.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
  $detail.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
  $detail.Text = '正在检查运行环境...'
  $form.Controls.Add($detail)

  [pscustomobject]@{ Form = $form; Detail = $detail; Strip = $strip }
}

function Set-UiState {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [ValidateSet('normal', 'warning', 'error')][string]$State = 'normal'
  )
  if (-not $script:Ui) { return }
  $script:Ui.Detail.Text = $Text
  $script:Ui.Strip.BackColor = switch ($State) {
    'warning' { [System.Drawing.Color]::FromArgb(245, 158, 11) }
    'error'   { [System.Drawing.Color]::FromArgb(239, 68, 68) }
    default   { [System.Drawing.Color]::FromArgb(20, 184, 166) }
  }
  [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-CurlProbe {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [string]$ProxyUrl,
    [switch]$NoProxy
  )
  $tempBody = Join-Path $env:TEMP ('jel-probe-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
  try {
    $args = @('-sS', '--connect-timeout', '3', '--max-time', '7', '-o', $tempBody, '-w', '%{http_code}')
    if ($NoProxy) { $args = @('--noproxy', '*') + $args }
    if ($ProxyUrl) { $args = @('--proxy', $ProxyUrl) + $args }
    $output = & curl.exe @args $Uri 2>&1
    $exitCode = $LASTEXITCODE
    $text = (($output | Out-String).Trim())
    $httpCode = if ($text -match '(\d{3})\s*$') { [int]$Matches[1] } else { 0 }
    [pscustomobject]@{
      Uri       = $Uri
      ProxyUrl  = $ProxyUrl
      ExitCode  = $exitCode
      HttpCode  = $httpCode
      Transport = ($exitCode -eq 0 -and $httpCode -gt 0)
      ErrorText = if ($exitCode -eq 0) { '' } else { $text }
    }
  } catch {
    [pscustomobject]@{ Uri = $Uri; ProxyUrl = $ProxyUrl; ExitCode = -1; HttpCode = 0; Transport = $false; ErrorText = $_.Exception.Message }
  } finally {
    Remove-Item -LiteralPath $tempBody -Force -ErrorAction SilentlyContinue
  }
}

function Test-ServiceResponse {
  param([Parameter(Mandatory = $true)]$Probe)
  $Probe.Transport -and ($Probe.HttpCode -in @(200, 204, 301, 302, 307, 308, 401, 403, 429))
}

function Get-CachedProxy {
  param([Parameter(Mandatory = $true)][string]$EnvFile)
  if (-not (Test-Path -LiteralPath $EnvFile)) { return $null }
  $content = Get-Content -Raw -LiteralPath $EnvFile
  if ($content -match '(?im)^\s*HTTPS?_PROXY\s*=\s*(https?|socks5h?)://127\.0\.0\.1:(\d+)\s*$') {
    return [pscustomobject]@{ Protocol = $Matches[1].ToLowerInvariant(); Port = [int]$Matches[2] }
  }
  $null
}

function Find-WorkingProxy {
  param(
    [Parameter(Mandatory = $true)]$Config,
    $CachedProxy
  )
  $candidates = New-Object System.Collections.Generic.List[object]
  if ($CachedProxy) { $candidates.Add($CachedProxy) }
  foreach ($port in $Config.portCandidates) {
    foreach ($protocol in $Config.proxyProtocols) {
      if (-not ($CachedProxy -and [int]$port -eq $CachedProxy.Port -and [string]$protocol -eq $CachedProxy.Protocol)) {
        $candidates.Add([pscustomobject]@{ Protocol = [string]$protocol; Port = [int]$port })
      }
    }
  }

  foreach ($candidate in $candidates) {
    $proxyUrl = '{0}://127.0.0.1:{1}' -f $candidate.Protocol, $candidate.Port
    Set-UiState -Text ("正在检查代理 {0}:{1}..." -f $candidate.Protocol, $candidate.Port)
    $generic = Invoke-CurlProbe -Uri $Config.testUri -ProxyUrl $proxyUrl
    Write-Log "Proxy $proxyUrl generic => exit=$($generic.ExitCode) http=$($generic.HttpCode)"
    if (-not $generic.Transport -or $generic.HttpCode -lt 200 -or $generic.HttpCode -ge 400) { continue }

    Set-UiState -Text '代理可用，正在验证 OpenAI 与 ChatGPT...'
    $openAi = Invoke-CurlProbe -Uri $Config.openAiTestUri -ProxyUrl $proxyUrl
    $chatGpt = Invoke-CurlProbe -Uri $Config.chatGptTestUri -ProxyUrl $proxyUrl
    $openAiOk = Test-ServiceResponse -Probe $openAi
    $chatGptOk = Test-ServiceResponse -Probe $chatGpt
    Write-Log "Proxy $proxyUrl OpenAI => exit=$($openAi.ExitCode) http=$($openAi.HttpCode); ChatGPT => exit=$($chatGpt.ExitCode) http=$($chatGpt.HttpCode)"
    if ($openAiOk -and $chatGptOk) {
      return [pscustomobject]@{
        Protocol = $candidate.Protocol
        Port = $candidate.Port
        Url = $proxyUrl
        GenericCode = $generic.HttpCode
        OpenAiCode = $openAi.HttpCode
        ChatGptCode = $chatGpt.HttpCode
      }
    }
  }
  $null
}

function Set-ProxyEnvironmentFile {
  param(
    [Parameter(Mandatory = $true)][string]$CodexHomePath,
    [Parameter(Mandatory = $true)][string]$ProxyUrl
  )
  $envFile = Join-Path $CodexHomePath '.env'
  $original = if (Test-Path -LiteralPath $envFile) { [System.IO.File]::ReadAllText($envFile) } else { '' }
  $lines = if ($original) { $original -split '\r?\n' } else { @() }
  $preserved = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -notmatch '(?i)^\s*HTTPS?_PROXY\s*=') { $preserved.Add([string]$line) }
  }
  while ($preserved.Count -gt 0 -and $preserved[$preserved.Count - 1] -eq '') {
    $preserved.RemoveAt($preserved.Count - 1)
  }
  $newLines = @($preserved.ToArray()) + @("HTTP_PROXY=$ProxyUrl", "HTTPS_PROXY=$ProxyUrl")
  $newContent = ($newLines -join "`r`n") + "`r`n"

  if ($original -eq $newContent) {
    return [pscustomobject]@{ Changed = $false; EnvFile = $envFile; BackupFile = $null }
  }

  $backupDir = Join-Path $CodexHomePath 'jel-backups'
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  $backupFile = $null
  if (Test-Path -LiteralPath $envFile) {
    $backupFile = Join-Path $backupDir ('.env.{0:yyyyMMdd-HHmmss-fff}.bak' -f (Get-Date))
    Copy-Item -LiteralPath $envFile -Destination $backupFile -Force
  }

  $tempFile = Join-Path $CodexHomePath ('.env.jel-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
  try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempFile, $newContent, $utf8)
    Move-Item -LiteralPath $tempFile -Destination $envFile -Force
    $verified = [System.IO.File]::ReadAllText($envFile)
    if ($verified -ne $newContent) { throw 'Environment file verification failed.' }
  } catch {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    if ($backupFile -and (Test-Path -LiteralPath $backupFile)) {
      Copy-Item -LiteralPath $backupFile -Destination $envFile -Force
    }
    throw
  }

  [pscustomobject]@{ Changed = $true; EnvFile = $envFile; BackupFile = $backupFile }
}

function Restart-CodexIfApproved {
  param(
    [Parameter(Mandatory = $true)]$AppInfo,
    [Parameter(Mandatory = $true)][bool]$ConfigChanged
  )
  $processes = @(Get-CodexAppProcesses -AppInfo $AppInfo)
  if (-not $ConfigChanged -or $processes.Count -eq 0) { return $true }

  $message = "JEL 已更新代理配置，但 ChatGPT 正在运行。`r`n`r`n要让新配置生效，需要结束当前 ChatGPT 后重新打开。正在执行的任务可能中断。`r`n`r`n是否现在重启 ChatGPT？"
  $choice = [System.Windows.Forms.MessageBox]::Show($message, 'JEL - 需要重启 ChatGPT', 'YesNoCancel', 'Warning')
  if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { return $false }
  if ($choice -eq [System.Windows.Forms.DialogResult]::No) {
    Set-UiState -Text "配置已保存。ChatGPT 下次完全退出后再打开时生效。" -State warning
    return $false
  }

  foreach ($process in $processes) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
  }
  $deadline = (Get-Date).AddSeconds(8)
  do {
    Start-Sleep -Milliseconds 250
    $remaining = @(Get-CodexAppProcesses -AppInfo $AppInfo)
  } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)
  if ($remaining.Count -gt 0) { throw 'ChatGPT 未能在预期时间内完全退出。' }
  $true
}

function Start-CodexApp {
  param([Parameter(Mandatory = $true)]$AppInfo)
  Start-Process explorer.exe ("shell:AppsFolder\{0}" -f $AppInfo.AppUserModelId)
}

function Wait-CodexStarted {
  param(
    [Parameter(Mandatory = $true)]$AppInfo,
    [int]$TimeoutSec = 15
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    Start-Sleep -Milliseconds 300
    if (@(Get-CodexAppProcesses -AppInfo $AppInfo).Count -gt 0) { return $true }
  } while ((Get-Date) -lt $deadline)
  $false
}

$mutex = $null
try {
  Initialize-Runtime
  $createdNew = $false
  $mutexName = 'Local\JerEx-{0}-Launcher' -f $safeProfile
  $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
  if (-not $createdNew) { throw 'JEL is already running.' }

  $config = Get-LauncherConfig
  Write-Log "JEL v$($config.version) profile=$safeProfile started. DiagnosticOnly=$DiagnosticOnly"
  $resolvedHome = Resolve-CodexHome -RequestedHome $CodexHome
  $appInfo = Get-CodexAppInfo
  $envFile = Join-Path $resolvedHome '.env'
  $cachedProxy = Get-CachedProxy -EnvFile $envFile

  if (-not $DiagnosticOnly) {
    $script:Ui = New-Ui -Config $config
    $null = $script:Ui.Form.Show()
    [System.Windows.Forms.Application]::DoEvents()
  }

  Set-UiState -Text '正在检查网络...'
  $directProbe = Invoke-CurlProbe -Uri $config.testUri -NoProxy
  Write-Log "Direct network => exit=$($directProbe.ExitCode) http=$($directProbe.HttpCode)"
  $workingProxy = Find-WorkingProxy -Config $config -CachedProxy $cachedProxy

  $diagnostic = [ordered]@{
    jelVersion       = $config.version
    codexVersion     = $appInfo.Version
    codexHome        = $resolvedHome
    appUserModelId   = $appInfo.AppUserModelId
    directNetwork    = $directProbe.Transport
    selectedProxy    = if ($workingProxy) { $workingProxy.Url } else { $null }
    openAiHttpCode   = if ($workingProxy) { $workingProxy.OpenAiCode } else { 0 }
    chatGptHttpCode  = if ($workingProxy) { $workingProxy.ChatGptCode } else { 0 }
    codexRunning     = (@(Get-CodexAppProcesses -AppInfo $appInfo).Count -gt 0)
  }

  if ($DiagnosticOnly) {
    [pscustomobject]$diagnostic | ConvertTo-Json -Depth 3
    exit $(if ($workingProxy) { 0 } else { 2 })
  }

  if (-not $workingProxy) {
    Set-UiState -Text "未找到可访问 OpenAI 与 ChatGPT 的代理。`r`n请启动或检查本地代理后重试。" -State error
    Write-Log 'No usable OpenAI/ChatGPT proxy was found.'
    [System.Windows.Forms.MessageBox]::Show('未找到可用代理。JEL 没有修改任何配置。', 'JEL', 'OK', 'Error') | Out-Null
    $script:Ui.Form.Close()
    exit 2
  }

  Set-UiState -Text ("代理验证成功：{0}:{1}`r`n正在安全更新配置..." -f $workingProxy.Protocol, $workingProxy.Port)
  $update = Set-ProxyEnvironmentFile -CodexHomePath $resolvedHome -ProxyUrl $workingProxy.Url
  Write-Log "Environment updated => changed=$($update.Changed) proxy=$($workingProxy.Url) backup=$($update.BackupFile)"

  $shouldLaunch = Restart-CodexIfApproved -AppInfo $appInfo -ConfigChanged $update.Changed
  if (-not $shouldLaunch) {
    Start-Sleep -Milliseconds ([int]$config.statusTimeoutMs)
    $script:Ui.Form.Close()
    exit 0
  }

  Set-UiState -Text "✓ 配置有效`r`n✓ 代理可用`r`n✓ OpenAI 与 ChatGPT 可连接`r`n正在打开 ChatGPT..."
  Start-Sleep -Milliseconds ([int]$config.launchDelayMs)
  Start-CodexApp -AppInfo $appInfo
  $started = Wait-CodexStarted -AppInfo $appInfo -TimeoutSec ([int]$config.verifyTimeoutSec)
  if (-not $started) {
    Set-UiState -Text '配置与网络检查通过，但未能确认 ChatGPT 已打开。' -State warning
    Write-Log 'Codex launch could not be verified.'
    Start-Sleep -Milliseconds 1800
    $script:Ui.Form.Close()
    exit 3
  }

  Write-Log "Codex launch verified with proxy $($workingProxy.Url)."
  Set-UiState -Text "✓ 环境检查完成`r`n✓ ChatGPT 已打开"
  Start-Sleep -Milliseconds ([int]$config.statusTimeoutMs)
  $script:Ui.Form.Close()
  exit 0
} catch {
  try { Write-Log ("ERROR: " + $_.Exception.Message) } catch { }
  if ($DiagnosticOnly) {
    Write-Error $_.Exception.Message
  } else {
    try {
      Set-UiState -Text ("JEL 无法继续：`r`n$($_.Exception.Message)") -State error
      [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'JEL', 'OK', 'Error') | Out-Null
      if ($script:Ui) { $script:Ui.Form.Close() }
    } catch { }
  }
  exit 1
} finally {
  if ($mutex) {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
  }
}
