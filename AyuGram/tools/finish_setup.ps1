<#
.SYNOPSIS
    Finishes the AyuGram iOS GitHub setup: remote, secrets, default branch,
    push and a device build. Run from anywhere.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File AyuGram\tools\finish_setup.ps1 `
        -ApiId 12345678 -ApiHash 0123456789abcdef0123456789abcdef

.NOTES
    Requires `gh auth login -h github.com` to have been done once (the CLI is
    already installed). api_id / api_hash are read from the parameters or from
    the TELEGRAM_API_ID / TELEGRAM_API_HASH environment variables. They cannot
    be invented: get them at https://my.telegram.org/apps with your own account.
#>
param(
    [string]$ApiId = $env:TELEGRAM_API_ID,
    [string]$ApiHash = $env:TELEGRAM_API_HASH,
    [string]$Repo = 'nekoasase/Ayugram-iOS',
    [string]$Branch = 'ayugram-ios',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$git = 'D:\augram\ayugram-toolchain\PortableGit\cmd\git.exe'
$checkout = 'D:\augram\ayugram-src\Telegram-iOS'
$remoteUrl = "https://github.com/$Repo.git"

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
# Native tools write warnings to stderr; with ErrorActionPreference=Stop PowerShell
# would turn those into terminating errors. Silence stderr only for those calls.
function Invoke-Native([string[]]$argv) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $argv[0] @($argv[1..($argv.Length - 1)]) 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    return $code
}

# 1. Authentication -----------------------------------------------------------
Say 'Checking GitHub CLI authentication'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$auth = (& gh auth status 2>&1 | Out-String)
$authCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($authCode -ne 0 -or $auth -match 'invalid' -or $auth -match 'Failed to log in') {
    Fail @"
GitHub CLI is not authenticated. Run once (opens a browser):

    gh auth login -h github.com --git-protocol https --web

Then re-run this script.
"@
}

# 2. Secrets ------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ApiId) -or [string]::IsNullOrWhiteSpace($ApiHash)) {
    Fail @"
api_id / api_hash are missing. They are personal to your Telegram account and
cannot be generated here. Create an app at https://my.telegram.org/apps (Platform: iOS),
then re-run with:

    powershell -ExecutionPolicy Bypass -File AyuGram\tools\finish_setup.ps1 -ApiId <digits> -ApiHash <32 hex chars>
"@
}

Say 'Setting repository secrets'
gh secret set TELEGRAM_API_ID --body $ApiId --repo $Repo 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'gh secret set TELEGRAM_API_ID failed' }
gh secret set TELEGRAM_API_HASH --body $ApiHash --repo $Repo 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'gh secret set TELEGRAM_API_HASH failed' }

# 3. Default branch -----------------------------------------------------------
Say "Setting default branch to $Branch"
gh api -X PATCH "repos/$Repo" -f default_branch=$Branch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'could not change the default branch' }

# 4. Push ---------------------------------------------------------------------
Say 'Configuring remote and pushing'
Invoke-Native @($git, '-C', $checkout, 'remote', 'remove', 'ayu') | Out-Null
Invoke-Native @($git, '-C', $checkout, 'remote', 'add', 'ayu', $remoteUrl) | Out-Null
& $git -C $checkout push -u ayu $Branch
if ($LASTEXITCODE -ne 0) { Fail 'git push failed' }

# 5. Device build -------------------------------------------------------------
if (-not $SkipBuild) {
    Say 'Triggering release_arm64 device build'
    gh workflow run build-ios.yml --repo $Repo --ref $Branch `
        -f runner=macos-26 -f configuration=release_arm64 -f credentials=required
    if ($LASTEXITCODE -ne 0) { Fail 'could not trigger the workflow' }

    Start-Sleep -Seconds 5
    $run = gh run list --repo $Repo --workflow build-ios.yml --limit 1 --json databaseId,url,status 2>&1
    Say "Latest run: $run"
}

Say 'Done. Watch https://github.com/' + $Repo + '/actions'
