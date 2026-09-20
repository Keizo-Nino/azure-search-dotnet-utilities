#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $env:USERPROFILE 'Desktop\SearchBackup'),
    [string]$SasUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$exitCode = 1
$stage = 'source validation'
$secureSasUrl = $null
$process = $null

function ConvertTo-NativeArgument([string]$Value) {
    # Quote Windows process arguments, including spaces and trailing backslashes.
    '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

try {
    $source = Get-Item -LiteralPath $SourcePath
    if (!$source.PSIsContainer -or $source.PSProvider.Name -ne 'FileSystem') {
        throw 'SourcePath must be a filesystem directory.'
    }
    $resolvedSource = $source.FullName
    Write-Host "Source directory: $resolvedSource"

    $stage = 'AzCopy setup'
    $azcopyDirectory = Join-Path $PSScriptRoot '.tools\azcopy'
    $azcopyPath = Join-Path $azcopyDirectory 'azcopy.exe'
    if (!(Test-Path -LiteralPath $azcopyPath -PathType Leaf)) {
        New-Item -ItemType Directory -Path $azcopyDirectory -Force | Out-Null
        $archivePath = Join-Path $azcopyDirectory 'azcopy.zip'
        $extractPath = Join-Path $azcopyDirectory 'extracted'
        Write-Host 'Downloading AzCopy...'
        $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile $archivePath -UseBasicParsing
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
            $downloadedAzCopy = Get-ChildItem -LiteralPath $extractPath -Filter 'azcopy.exe' -File -Recurse |
                Select-Object -First 1
            if ($null -eq $downloadedAzCopy) {
                throw 'The downloaded archive does not contain azcopy.exe.'
            }
            Copy-Item -LiteralPath $downloadedAzCopy.FullName -Destination $azcopyPath
        }
        finally {
            [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
            if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
                Remove-Item -LiteralPath $archivePath -Force
            }
        }
    }
    Write-Host "AzCopy: $azcopyPath"

    $stage = 'SAS URL input'
    if ([string]::IsNullOrWhiteSpace($SasUrl)) {
        $secureSasUrl = Read-Host 'Container SAS URL (input hidden)' -AsSecureString
        $sasPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSasUrl)
        try {
            $SasUrl = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($sasPointer)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($sasPointer)
        }
    }
    $sasUri = $null
    if (![Uri]::TryCreate($SasUrl, [UriKind]::Absolute, [ref]$sasUri) -or
        $sasUri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($sasUri.Host) -or
        $sasUri.AbsolutePath.Trim('/').Split('/').Count -ne 1 -or $sasUri.AbsolutePath.Trim('/') -eq '' -or
        $sasUri.Query -notmatch '(?:\?|&)sig=[^&]+' -or $sasUri.Fragment -ne '' -or $sasUri.UserInfo -ne '') {
        throw 'Enter an HTTPS container SAS URL.'
    }

    $stage = 'AzCopy execution'
    Write-Host 'Upload started.'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $azcopyPath
    $arguments = @('copy', $resolvedSource, $SasUrl, '--recursive=true', '--output-level=quiet', '--log-level=NONE')
    $startInfo.Arguments = ($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    # Do not echo native errors: they may contain the destination URL.
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
    $stderrTask = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
    $process.WaitForExit()
    $stdoutTask.GetAwaiter().GetResult()
    $stderrTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    if ($exitCode -eq 0) {
        Write-Host 'Upload succeeded.'
    }
    else {
        Write-Host "Upload failed. AzCopy exit code: $exitCode"
    }
}
catch {
    # Never print exception details, command arguments, or the SAS URL.
    Write-Host "Upload failed during $stage. Check the source path, network, and SAS URL/permissions."
    $exitCode = 1
}
finally {
    $SasUrl = $null
    if ($null -ne $secureSasUrl) { $secureSasUrl.Dispose() }
    if ($null -ne $process) { $process.Dispose() }
}

exit $exitCode
