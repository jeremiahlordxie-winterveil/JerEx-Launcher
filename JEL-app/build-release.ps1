param([string]$Version = "0.1.0")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root 'src\JEL.App\JEL.App.csproj'
$publish = Join-Path $root 'publish\win-x64'
$artifacts = Join-Path $root 'artifacts'
Remove-Item $publish -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $artifacts 'package') -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:Version=$Version -o $publish
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "${env:ProgramFiles}\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 was not found. Install it, then rerun this script.' }
& $iscc "/DAppVersion=$Version" (Join-Path $root 'installer\JEL.iss')
$package = Join-Path $artifacts 'package'; New-Item $package -ItemType Directory -Force | Out-Null
$setup = Get-ChildItem (Join-Path $artifacts 'installer') -Filter 'JEL-Setup-*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $setup.FullName $package
Copy-Item (Join-Path $root 'README.txt'),(Join-Path $root 'LICENSE.txt'),(Join-Path $root 'CHANGELOG.txt'),(Join-Path $root 'SECURITY.txt') $package
$setupHash = (Get-FileHash $setup.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
"$setupHash  $($setup.Name)" | Set-Content (Join-Path $package 'SHA256SUMS.txt')
$zip = Join-Path $artifacts "JEL-$Version-win-x64.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip
"$( (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant())  $(Split-Path $zip -Leaf)" | Set-Content ($zip + '.sha256')
Write-Host "Release package: $zip"
