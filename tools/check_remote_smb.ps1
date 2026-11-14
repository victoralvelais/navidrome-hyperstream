# Disposable Windows-runner verification only. Never creates shares on a user's PC.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or !$env:RUNNER_TEMP) {
    throw 'This check is restricted to the disposable GitHub Actions runner.'
}
$testRoot = [IO.Path]::GetFullPath((Join-Path $env:RUNNER_TEMP 'HyperstreamSmbTest'))
$runnerRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
if (!$testRoot.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Test folder must stay inside the runner temporary directory.'
}
if (Test-Path -LiteralPath $testRoot) { throw 'Test folder already exists.' }
$testName = 'HyperstreamSmbTest'
$testUser = 'hs_smb_test'
$createdUser = $false
$createdShare = $false
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $testPassword = 'Hs!9' + [Guid]::NewGuid().ToString('N')
    New-LocalUser -Name $testUser -Password (ConvertTo-SecureString $testPassword -AsPlainText -Force) -AccountNeverExpires | Out-Null
    $createdUser = $true
    $identity = "$env:COMPUTERNAME\$testUser"
    $acl = Get-Acl -LiteralPath $testRoot
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $testRoot -AclObject $acl
    New-SmbShare -Name $testName -Path $testRoot -ChangeAccess $identity -EncryptData $true | Out-Null
    $createdShare = $true
    $env:HYPERSTREAM_SMB_TEST_ADDRESS = "smb://127.0.0.1/$testName"
    $env:HYPERSTREAM_SMB_TEST_USER = $identity
    $env:HYPERSTREAM_SMB_TEST_PASSWORD = $testPassword
    flutter test --no-pub test/remote_smb_live_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Native SMB verification failed.' }
} finally {
    Remove-Item Env:HYPERSTREAM_SMB_TEST_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:HYPERSTREAM_SMB_TEST_USER -ErrorAction SilentlyContinue
    Remove-Item Env:HYPERSTREAM_SMB_TEST_ADDRESS -ErrorAction SilentlyContinue
    if ($createdShare) { Remove-SmbShare -Name $testName -Force }
    if ($createdUser) { Remove-LocalUser -Name $testUser }
    # Recheck the resolved target immediately before recursive cleanup.
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        if (!$resolved.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup outside the runner temporary directory.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
