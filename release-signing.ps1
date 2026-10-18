# Quillpad Hebrew local release signing.
# No signing credentials are uploaded to GitHub.
function Initialize-ReleaseSigning {
  param([Parameter(Mandatory = $true)][string]$JdkRoot)

  $Keytool = Join-Path $JdkRoot 'bin\keytool.exe'
  if (-not (Test-Path -LiteralPath $Keytool -PathType Leaf)) {
    throw 'keytool.exe was not found in the selected JDK.'
  }

  $SigningFolder = Join-Path $env:LOCALAPPDATA 'Quillpad-Hebrew\signing'
  $KeystoreFile = Join-Path $SigningFolder 'quillpad-hebrew-release.p12'
  $PasswordFile = Join-Path $SigningFolder 'password.dpapi'
  $KeyAlias = 'quillpad-hebrew-release'
  $HasKey = Test-Path -LiteralPath $KeystoreFile -PathType Leaf
  $HasPassword = Test-Path -LiteralPath $PasswordFile -PathType Leaf

  if ($HasKey -xor $HasPassword) {
    throw ('Incomplete signing files at ' + $SigningFolder + '. Do not delete an existing signing key. Recover its matching password before retrying.')
  }

  if (-not $HasKey) {
    Write-Host '[3/4] Creating your own release signing key (one time only)...'
    New-Item -ItemType Directory -Path $SigningFolder -Force | Out-Null
    $RandomBytes = New-Object byte[] 32
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
      $Rng.GetBytes($RandomBytes)
    } finally {
      $Rng.Dispose()
    }
    $PlainPassword = [BitConverter]::ToString($RandomBytes).Replace('-', '')
    $env:QUILLPAD_HEBREW_SIGNING_PASSWORD = $PlainPassword
    try {
      & $Keytool '-genkeypair' '-noprompt' '-alias' $KeyAlias '-keyalg' 'RSA' '-keysize' '3072' '-validity' '10000' '-storetype' 'PKCS12' '-keystore' $KeystoreFile '-dname' 'CN=Quillpad Hebrew, O=Community, C=IL' '-storepass:env' 'QUILLPAD_HEBREW_SIGNING_PASSWORD' '-keypass:env' 'QUILLPAD_HEBREW_SIGNING_PASSWORD'
      if ($LASTEXITCODE -ne 0) {
        throw 'keytool could not create the signing key.'
      }
      $SecurePassword = ConvertTo-SecureString -String $PlainPassword -AsPlainText -Force
      $EncryptedPassword = ConvertFrom-SecureString -SecureString $SecurePassword
      Set-Content -LiteralPath $PasswordFile -Value $EncryptedPassword -Encoding ASCII -NoNewline
    } catch {
      # Roll back only the files created in this invocation.
      Remove-Item -LiteralPath $PasswordFile -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $KeystoreFile -Force -ErrorAction SilentlyContinue
      throw
    }
  } else {
    try {
      $EncryptedPassword = Get-Content -LiteralPath $PasswordFile -Raw
      $SecurePassword = ConvertTo-SecureString -String $EncryptedPassword
      $PlainPassword = (New-Object System.Net.NetworkCredential('', $SecurePassword)).Password
    } catch {
      throw 'Cannot decrypt the signing password under this Windows user. Keep the original keystore and restore the matching password.'
    }
  }

  $env:QUILLPAD_HEBREW_SIGNING_PASSWORD = $PlainPassword
  & $Keytool '-list' '-alias' $KeyAlias '-keystore' $KeystoreFile '-storepass:env' 'QUILLPAD_HEBREW_SIGNING_PASSWORD' | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Release signing key could not be verified. The original keystore was not changed.'
  }

  # Gradle's ORG_GRADLE_PROJECT_ prefix supplies project properties without
  # placing the signing password on the Gradle command line or in Git files.
  $env:ORG_GRADLE_PROJECT_keystore = $KeystoreFile
  $env:ORG_GRADLE_PROJECT_storepass = $PlainPassword
  $env:ORG_GRADLE_PROJECT_keyalias = $KeyAlias
  $env:ORG_GRADLE_PROJECT_keypass = $PlainPassword
  Remove-Item Env:\QUILLPAD_HEBREW_SIGNING_PASSWORD -ErrorAction SilentlyContinue

  Write-Host ('Release signing key: ' + $KeystoreFile)
  Write-Host 'Signing password: Windows DPAPI-protected, not stored in GitHub.'
}

function Get-DownloadsDirectory {
  $Folder = $null
  try {
    $RegistryKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $RegistryValue = '{374DE290-123F-4565-9164-39C4925E467B}'
    $Settings = Get-ItemProperty -Path $RegistryKey -ErrorAction Stop
    $Entry = $Settings.PSObject.Properties[$RegistryValue]
    if ($Entry -and $Entry.Value) {
      $Folder = [Environment]::ExpandEnvironmentVariables([string]$Entry.Value)
    }
  } catch {
    # Fall back to the default Downloads directory.
  }
  if ([string]::IsNullOrWhiteSpace($Folder)) {
    $Folder = Join-Path $env:USERPROFILE 'Downloads'
  }
  New-Item -ItemType Directory -Force -Path $Folder | Out-Null
  return $Folder
}
