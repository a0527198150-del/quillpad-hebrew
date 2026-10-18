$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
$Source = Join-Path $Root 'quillpad-source'
$Translation = Join-Path $Root 'translation\app\src\main\res\values-he\strings.xml'
$Output = Join-Path $Root 'Quillpad-Hebrew-debug.apk'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function SaveUtf8($path, $text) { [System.IO.File]::WriteAllText($path,$text,$Utf8) }
try {
  if (-not (Test-Path (Join-Path $Source 'gradlew.bat'))) {
    if (Test-Path $Source) { throw 'quillpad-source exists but is not a full Gradle project.' }
    Write-Host '[1/4] Cloning Quillpad v1.5.15...'
    & git clone --depth 1 --branch v1.5.15 --single-branch https://github.com/quillpad/quillpad.git $Source
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed. Verify GitHub access.' }
  }
  Write-Host '[2/4] Applying Hebrew translation...'
  $Dest = Join-Path $Source 'app\src\main\res\values-he'
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Copy-Item -LiteralPath $Translation -Destination (Join-Path $Dest 'strings.xml') -Force
  $Gradle = Join-Path $Source 'app\build.gradle.kts'
  $Body = [System.IO.File]::ReadAllText($Gradle)
  if ($Body -notmatch '"he",') {
    if (-not $Body.Contains('"fr",')) { throw 'Locale list not found in app/build.gradle.kts' }
    SaveUtf8 $Gradle ($Body.Replace('"fr",','"fr",' + "`n" + '                "he",'))
  }
  $Loc = Join-Path $Source 'app\src\main\res\xml\locales_config.xml'
  $Body = [System.IO.File]::ReadAllText($Loc)
  if ($Body -notmatch 'android:name="he"') {
    if (-not $Body.Contains('<locale android:name="fr"/>')) { throw 'Locales config not found' }
    SaveUtf8 $Loc ($Body.Replace('<locale android:name="fr"/>','<locale android:name="fr"/>' + "`n" + '    <locale android:name="he"/>'))
  }
  $Sdk = @($env:ANDROID_SDK_ROOT,$env:ANDROID_HOME,(Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'platforms')) } | Select-Object -First 1
  if ($Sdk) { SaveUtf8 (Join-Path $Source 'local.properties') ('sdk.dir=' + $Sdk.Replace('\','/') + "`n") }
  # Android Studio includes a bundled JDK (jbr), which is not always on PATH.
  # Locate a local Java installation automatically before running Gradle.
  Write-Host '[3/4] Locating Java and building APK...'
  $JavaHomes = New-Object System.Collections.Generic.List[string]
  if ($env:JAVA_HOME) { $JavaHomes.Add($env:JAVA_HOME) }
  $ProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  foreach ($Base in @($env:ProgramFiles, $ProgramFilesX86, $env:LOCALAPPDATA)) {
    if (-not $Base) { continue }
    foreach ($Rel in @('Android\Android Studio\jbr', 'Android\Android Studio\jre', 'Programs\Android Studio\jbr', 'Programs\Android Studio\jre')) {
      $JavaHomes.Add((Join-Path $Base $Rel))
    }
    foreach ($Rel in @('Java', 'Eclipse Adoptium', 'Microsoft', 'Amazon Corretto', 'BellSoft', 'Zulu', 'Programs\Java', 'Programs\Eclipse Adoptium')) {
      $Parent = Join-Path $Base $Rel
      if (Test-Path -LiteralPath $Parent -PathType Container) {
        foreach ($Dir in (Get-ChildItem -LiteralPath $Parent -Directory -ErrorAction SilentlyContinue)) {
          $JavaHomes.Add($Dir.FullName)
          $JavaHomes.Add((Join-Path $Dir.FullName 'jbr'))
        }
      }
    }
  }
  $ExistingJava = Get-Command 'java.exe' -ErrorAction SilentlyContinue
  if ($ExistingJava -and $ExistingJava.Source) {
    $JavaHomes.Add((Split-Path -Parent (Split-Path -Parent $ExistingJava.Source)))
  }
  $FoundJava = $false
  foreach ($JavaHomeCandidate in ($JavaHomes | Select-Object -Unique)) {
    if ($JavaHomeCandidate -and (Test-Path -LiteralPath (Join-Path $JavaHomeCandidate 'bin\java.exe') -PathType Leaf)) {
      $env:JAVA_HOME = $JavaHomeCandidate
      $env:Path = (Join-Path $JavaHomeCandidate 'bin') + ';' + $env:Path
      $FoundJava = $true
      break
    }
  }
  if (-not $FoundJava) {
    $Toolbox = Join-Path $env:LOCALAPPDATA 'JetBrains\Toolbox\apps\AndroidStudio'
    if (Test-Path -LiteralPath $Toolbox -PathType Container) {
      foreach ($JavaFile in (Get-ChildItem -LiteralPath $Toolbox -Filter java.exe -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($JavaFile.Directory.Name -eq 'bin') {
          $env:JAVA_HOME = $JavaFile.Directory.Parent.FullName
          $env:Path = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:Path
          $FoundJava = $true
          break
        }
      }
    }
  }
  if (-not $FoundJava) {
    throw 'Java not found. Verify that Android Studio JBR or JDK 17+ is installed. Typical path: C:\Program Files\Android\Android Studio\jbr.'
  }
  Write-Host ('Using Java from: ' + $env:JAVA_HOME)

  Push-Location $Source
  try {
    & (Join-Path $Source 'gradlew.bat') ':app:assembleDebug' '--no-daemon'
    $ExitCode = $LASTEXITCODE
  } finally { Pop-Location }
  if ($ExitCode -ne 0) { throw "Gradle failed with exit code $ExitCode" }
  $Apk = Join-Path $Source 'app\build\outputs\apk\debug\app-debug.apk'
  if (-not (Test-Path $Apk)) { throw 'Gradle ended without an APK.' }
  Copy-Item $Apk $Output -Force
  Write-Host '[4/4] Build successful:' $Output -ForegroundColor Green
  exit 0
} catch {
  Write-Host 'BUILD FAILED:' $_.Exception.Message -ForegroundColor Red
  exit 1
}
