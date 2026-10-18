$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
$Source = Join-Path $Root 'quillpad-source'
$Translation = Join-Path $Root 'translation\app\src\main\res\values-he\strings.xml'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $Root 'release-signing.ps1')
$Output = Join-Path (Get-DownloadsDirectory) 'Quillpad-Hebrew-release.apk'

function Save-Utf8File([string]$FilePath, [string]$Value) {
  [System.IO.File]::WriteAllText($FilePath, $Value, $Utf8)
}

function Use-Jdk([string]$Location) {
  if ([string]::IsNullOrWhiteSpace($Location)) { return $false }
  $Location = $Location.Trim('"')
  $Exe = Join-Path $Location 'bin\java.exe'
  $Compiler = Join-Path $Location 'bin\javac.exe'
  if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }
  if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) { return $false }
  $env:JAVA_HOME = $Location
  $env:Path = (Join-Path $Location 'bin') + ';' + $env:Path
  Write-Host ('Using JDK: ' + $Location)
  return $true
}

function Find-LocalJdk {
  $Candidates = New-Object System.Collections.Generic.List[string]
  foreach ($Name in @('JAVA_HOME','JDK_HOME','GRADLE_JAVA_HOME','STUDIO_JDK','JDK17_HOME','JDK21_HOME')) {
    $Value = [Environment]::GetEnvironmentVariable($Name)
    if ($Value) { $Candidates.Add($Value) }
  }

  $OnPath = Get-Command java.exe -CommandType Application -ErrorAction SilentlyContinue
  if ($OnPath -and $OnPath.Source) {
    $Candidates.Add((Split-Path -Parent (Split-Path -Parent $OnPath.Source)))
  }

  foreach ($GradleProperties in @((Join-Path $env:USERPROFILE '.gradle\gradle.properties'),(Join-Path $Source 'gradle.properties'))) {
    if (-not (Test-Path -LiteralPath $GradleProperties -PathType Leaf)) { continue }
    $Match = Select-String -LiteralPath $GradleProperties -Pattern '^\s*org\.gradle\.java\.home\s*=\s*(.+)\s*$' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Match) {
      $Value = $Match.Matches[0].Groups[1].Value.Trim().Replace('\:',':').Replace('\\','\')
      $Candidates.Add($Value)
    }
  }

  $ProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  $Bases = @($env:ProgramFiles,$ProgramFilesX86,$env:LOCALAPPDATA,$env:USERPROFILE,$env:ProgramW6432)
  $IdeFolders = @(
    'Android\Android Studio\jbr', 'Android\Android Studio\jre',
    'Android Studio\jbr', 'Programs\Android Studio\jbr',
    'JetBrains\Android Studio\jbr', 'JetBrains\IntelliJ IDEA Community Edition\jbr',
    'JetBrains\IntelliJ IDEA Ultimate\jbr',
    '.jdks', '.gradle\jdks', '.gradle\jdks\jdk-17',
    'scoop\apps\temurin17-jdk\current','scoop\apps\openjdk17\current',
    'Programs\Android Studio\jbr'
  )
  foreach ($Base in $Bases) {
    if (-not $Base) { continue }
    foreach ($Rel in $IdeFolders) { $Candidates.Add((Join-Path $Base $Rel)) }
  }

  foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
    if (Use-Jdk $Candidate) { return $true }
  }

  # Look only inside typical IDE and JDK installation directories.
  # Avoid a costly recursive scan of the whole computer.
  $SearchRoots = New-Object System.Collections.Generic.List[string]
  foreach ($Base in @($env:ProgramFiles,$ProgramFilesX86,$env:LOCALAPPDATA)) {
    if (-not $Base) { continue }
    foreach ($Rel in @('Android','Android Studio','Java','Eclipse Adoptium','Microsoft','JetBrains','BellSoft','Zulu','Programs\Android Studio','Programs\Java','Programs\Eclipse Adoptium','JetBrains\Toolbox\apps\AndroidStudio')) {
      $SearchRoots.Add((Join-Path $Base $Rel))
    }
  }
  foreach ($Rel in @('.jdks','.gradle\jdks','scoop\apps')) {
    $SearchRoots.Add((Join-Path $env:USERPROFILE $Rel))
  }

  foreach ($Dir in ($SearchRoots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { continue }
    foreach ($File in (Get-ChildItem -LiteralPath $Dir -Filter 'java.exe' -File -Recurse -ErrorAction SilentlyContinue)) {
      if ($File.Directory.Name -ne 'bin') { continue }
      if (Use-Jdk $File.Directory.Parent.FullName) { return $true }
    }
  }

  return $false
}

try {
  if (-not (Test-Path -LiteralPath (Join-Path $Source 'gradlew.bat') -PathType Leaf)) {
    if (Test-Path -LiteralPath $Source) { throw 'quillpad-source is not a valid Gradle project.' }
    Write-Host '[1/4] Cloning Quillpad v1.5.15...'
    & git clone --depth 1 --branch v1.5.15 --single-branch https://github.com/quillpad/quillpad.git $Source
    if ($LASTEXITCODE -ne 0) { throw 'Git clone failed.' }
  }

  Write-Host '[2/4] Applying Hebrew translation...'
  $Dest = Join-Path $Source 'app\src\main\res\values-he'
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Copy-Item -LiteralPath $Translation -Destination (Join-Path $Dest 'strings.xml') -Force

  $GradleFile = Join-Path $Source 'app\build.gradle.kts'
  $GradleText = [System.IO.File]::ReadAllText($GradleFile)
  if (-not $GradleText.Contains('"he",')) {
    if (-not $GradleText.Contains('"fr",')) { throw 'Cannot find language list in app/build.gradle.kts.' }
    Save-Utf8File $GradleFile ($GradleText.Replace('"fr",', '"fr",' + [Environment]::NewLine + '                "he",'))
  }

  $LocaleFile = Join-Path $Source 'app\src\main\res\xml\locales_config.xml'
  $LocaleText = [System.IO.File]::ReadAllText($LocaleFile)
  if (-not $LocaleText.Contains('android:name="he"')) {
    if (-not $LocaleText.Contains('<locale android:name="fr"/>')) { throw 'Cannot find locale list.' }
    Save-Utf8File $LocaleFile ($LocaleText.Replace('<locale android:name="fr"/>','<locale android:name="fr"/>' + [Environment]::NewLine + '    <locale android:name="he"/>'))
  }

  if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set.' }
  $SdkCandidates = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))
  $Sdk = $SdkCandidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'platforms') -PathType Container) } | Select-Object -First 1
  if ($Sdk) {
    Save-Utf8File (Join-Path $Source 'local.properties') ('sdk.dir=' + $Sdk.Replace('\','/') + [Environment]::NewLine)
  }

  Write-Host '[3/4] Locating installed JDK...'
  if (-not (Find-LocalJdk)) {
    throw 'No JDK was found. Java may be installed in a custom folder. Run: where /R C:\ java.exe  (and repeat for D: if needed), then send the path of bin\java.exe. Nothing needs to be installed yet.'
  }

  # NetFree HTTPS interception requires a trusted CA in Java.
  # Keep the original JDK truststore untouched by using a private temporary copy.
  $NetFreeCertificate = Join-Path $env:ProgramData 'NetFree\CA\netfree-ca-last.crt'
  if (Test-Path -LiteralPath $NetFreeCertificate -PathType Leaf) {
    Write-Host '[3/4] Configuring NetFree CA for this build...'
    $JdkTrustStore = Join-Path $env:JAVA_HOME 'lib\security\cacerts'
    $KeytoolExe = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    if (-not (Test-Path -LiteralPath $JdkTrustStore -PathType Leaf)) {
      throw 'JDK truststore (lib\security\cacerts) could not be located.'
    }
    if (-not (Test-Path -LiteralPath $KeytoolExe -PathType Leaf)) {
      throw 'JDK keytool.exe could not be located.'
    }
    $TlsDir = Join-Path $Root '.build-cache'
    New-Item -ItemType Directory -Path $TlsDir -Force | Out-Null
    $PrivateTrustStore = Join-Path $TlsDir 'cacerts'
    Copy-Item -LiteralPath $JdkTrustStore -Destination $PrivateTrustStore -Force
    & $KeytoolExe '-importcert' '-noprompt' '-trustcacerts' '-alias' 'netfree-ca' '-file' $NetFreeCertificate '-keystore' $PrivateTrustStore '-storepass' 'changeit'
    if ($LASTEXITCODE -ne 0) {
      throw 'Importing the NetFree certificate into the private JDK truststore failed.'
    }
    $TlsOptions = '-Djavax.net.ssl.trustStore="' + $PrivateTrustStore + '" -Djavax.net.ssl.trustStorePassword=changeit'
    $env:JAVA_TOOL_OPTIONS = (@($env:JAVA_TOOL_OPTIONS, $TlsOptions) | Where-Object { $_ }) -join ' '
  } else {
    # Java can use the same trusted Windows roots as the browser.
    # This does NOT disable TLS certificate verification.
    Write-Host '[3/4] NetFree CA file not found; using Windows trusted root certificates...'
    $TlsOptions = '-Djavax.net.ssl.trustStoreType=Windows-ROOT -Djavax.net.ssl.trustStore=NONE'
    $env:JAVA_TOOL_OPTIONS = (@($env:JAVA_TOOL_OPTIONS, $TlsOptions) | Where-Object { $_ }) -join ' '
  }

  Initialize-ReleaseSigning -JdkRoot $env:JAVA_HOME
  Write-Host '[3/4] Building signed Release APK...'
  Push-Location -LiteralPath $Source
  try {
    & (Join-Path $Source 'gradlew.bat') ':app:assembleRelease' '--no-daemon'
    $BuildExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  if ($BuildExit -ne 0) { throw ('Gradle build failed, exit code ' + $BuildExit) }

  $Apk = Join-Path $Source 'app\build\outputs\apk\release\app-release.apk'
  if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) { throw 'Gradle completed but APK was not found.' }
  Copy-Item -LiteralPath $Apk -Destination $Output -Force
  Write-Host ('[4/4] APK created: ' + $Output) -ForegroundColor Green
  exit 0
} catch {
  Write-Host ('BUILD FAILED: ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
