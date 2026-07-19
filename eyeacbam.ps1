Clear-Host

# ====================== BANNER ======================
Write-Host "";
Write-Host "";
Write-Host -ForegroundColor White "   ███████╗██╗   ██╗███████╗    █████╗  ██████╗";
Write-Host -ForegroundColor White "   ██╔════╝╚██╗ ██╔╝██╔════╝   ██╔══██╗██╔════╝";
Write-Host -ForegroundColor White "   █████╗   ╚████╔╝ █████╗     ███████║██║     ";
Write-Host -ForegroundColor White "   ██╔══╝    ╚██╔╝  ██╔══╝     ██╔══██║██║     ";
Write-Host -ForegroundColor White "   ███████╗   ██║   ███████╗██╗██║  ██║╚██████╗";
Write-Host -ForegroundColor White "   ╚══════╝   ╚═╝   ╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝";
Write-Host "";
Write-Host -ForegroundColor Gray "   Made By eye.AC " -NoNewLine
Write-Host -ForegroundColor White " • " -NoNewLine
Write-Host -ForegroundColor Gray "discord.gg/eyeac";
Write-Host "";
# ===================================================

$ErrorActionPreference = "SilentlyContinue"

function Get-Signature {
    param ([string]$FilePath)
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        return "File Was Not Found"
    }
    $sig = (Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue).Status
    switch ($sig) {
        "Valid"          { return "Valid Signature" }
        "NotSigned"      { return "Invalid Signature (NotSigned)" }
        "HashMismatch"   { return "Invalid Signature (HashMismatch)" }
        "NotTrusted"     { return "Invalid Signature (NotTrusted)" }
        default          { return "Invalid Signature (UnknownError)" }
    }
}

# Check Admin
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Warning "Please Run This Script as Administrator."
    Start-Sleep 5
    Exit
}

$sw = [Diagnostics.Stopwatch]::StartNew()

Write-Host "[+] Mounting Registry..." -ForegroundColor Gray

# Mount HKLM if needed
if (-not (Get-PSDrive -Name HKLM -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKLM -PSProvider Registry -Root HKEY_LOCAL_MACHINE | Out-Null
}

# BAM Paths
$BasePaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings",
    "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings"
)

$Users = @()
foreach ($path in $BasePaths) {
    if (Test-Path $path) {
        $Users += Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName
    }
}

$Users = $Users | Sort-Object -Unique

if ($Users.Count -eq 0) {
    Write-Warning "No BAM UserSettings found. This Windows version may not be supported or key is empty."
    Exit
}

$BamEntries = @()

Write-Host "[+] Extracting BAM entries..." -ForegroundColor White

foreach ($Sid in $Users) {
    $objSID = New-Object System.Security.Principal.SecurityIdentifier($Sid)
    try { $Username = $objSID.Translate([System.Security.Principal.NTAccount]).Value }
    catch { $Username = $Sid }

    foreach ($BasePath in $BasePaths) {
        $FullPath = "$BasePath\$Sid"
        if (-not (Test-Path $FullPath)) { continue }

        $Properties = Get-Item -Path $FullPath | Select-Object -ExpandProperty Property

        foreach ($Prop in $Properties) {
            $Value = (Get-ItemProperty -Path $FullPath -Name $Prop).$Prop

            if ($Value.Length -eq 24) {
                try {
                    $Hex = [System.BitConverter]::ToString($Value[7..0]) -replace "-", ""
                    $FileTime = [Convert]::ToInt64($Hex, 16)
                    $LastExecUTC = [DateTime]::FromFileTimeUtc($FileTime)
                    $LastExecLocal = $LastExecUTC.ToLocalTime()

                    $Path = if ($Prop.StartsWith("\Device\HarddiskVolume")) {
                        "C:" + $Prop.Substring($Prop.IndexOf("\", 20))
                    } else { $Prop }

                    $Signature = Get-Signature -FilePath $Path

                    $BamEntries += [PSCustomObject]@{
                        'User'                    = $Username
                        'SID'                     = $Sid
                        'Last Execution (Local)'  = $LastExecLocal
                        'Last Execution (UTC)'    = $LastExecUTC
                        'Application'             = Split-Path $Path -Leaf
                        'Full Path'               = $Path
                        'Signature'               = $Signature
                        'Registry Path'           = $FullPath
                    }
                }
                catch { }
            }
        }
    }
}

if ($BamEntries.Count -gt 0) {
    $BamEntries | Out-GridView -Title "BAM Entries - $($BamEntries.Count) executions found" -PassThru
} else {
    Write-Host "No BAM entries found." -ForegroundColor Yellow
}

$sw.Stop()
Write-Host ""
Write-Host "Completed in $($sw.Elapsed.TotalMinutes.ToString("0.00")) minutes" -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")