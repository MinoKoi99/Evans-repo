# verify-install.ps1
#
# 验证 dsh-purge 安装后的插件入口是否就位。
# 供 CI 的 ps51-compat job 调用，也可手动执行。
#
# 用法:
#   powershell -NoProfile -File scripts\verify-install.ps1
#   powershell -NoProfile -File scripts\verify-install.ps1 -DshHome "C:\Users\x\.dsh"
#
# 退出码: 0 = 全部通过, 1 = 有检查项失败
#
# 注意: 本文件必须保存为 UTF-8 with BOM。
#       纯英文内容（不用中文），避免任何编码歧义。

param(
    [string]$DshHome = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($DshHome)) {
    if ($env:DSH_HOME) {
        $DshHome = $env:DSH_HOME
    } else {
        $DshHome = Join-Path $env:USERPROFILE ".dsh"
    }
}

$profileDir = Join-Path $DshHome "profiles\web"
$fail = 0
$pass = 0

function Check-Ok([string]$msg) {
    Write-Host "  [OK]   $msg"
    $script:pass++
}

function Check-Fail([string]$msg) {
    Write-Host "  [FAIL] $msg"
    $script:fail++
}

Write-Host ""
Write-Host "dsh-purge install verification"
Write-Host "  DSH_HOME: $DshHome"
Write-Host "  PSVersion: $($PSVersionTable.PSVersion)"
Write-Host ""

# ---- Check 1: package present and correct version ----
Write-Host "[1] package version"
$pkg = Join-Path $profileDir "node_modules\dsh-purge\package.json"
if (Test-Path $pkg) {
    try {
        $d = Get-Content $pkg -Raw -ErrorAction Stop | ConvertFrom-Json
        $v = $d.version
        Write-Host "      version: $v"
        if ($v -eq "1.1.71-rc2.1") {
            Check-Ok "version is 1.1.71-rc2.1"
        } else {
            Check-Fail "version mismatch, expected 1.1.71-rc2.1, got $v"
        }
    } catch {
        Check-Fail "package.json parse error: $($_.Exception.Message)"
    }
} else {
    Check-Fail "package not found: $pkg"
}

# ---- Check 2: bundles registration ----
Write-Host "[2] profile bundles"
$pj = Join-Path $profileDir "package.json"
if (Test-Path $pj) {
    try {
        $d = Get-Content $pj -Raw -ErrorAction Stop | ConvertFrom-Json
        $b = @()
        if ($d.dsh -and $d.dsh.profile -and $d.dsh.profile.bundles) {
            $b = @($d.dsh.profile.bundles)
        }
        Write-Host "      bundles: $($b -join ',')"
        if ($b -contains "dsh-purge") {
            Check-Ok "dsh-purge registered in bundles"
        } else {
            Check-Fail "dsh-purge NOT in bundles"
        }
        if ($b -contains "@deepseek-ai/dsh-base") {
            Check-Ok "dsh-base present"
        } else {
            Check-Fail "dsh-base missing"
        }
        if ($b -contains "@deepseek-ai/dsh-web-app") {
            Check-Ok "dsh-web-app present"
        } else {
            Check-Fail "dsh-web-app missing"
        }
    } catch {
        Check-Fail "profile package.json parse error: $($_.Exception.Message)"
    }
} else {
    Check-Fail "profile package.json not found: $pj"
}

# ---- Check 3: cordis.patch.yml registration ----
Write-Host "[3] cordis.patch.yml"
$py = Join-Path $profileDir "cordis.patch.yml"
if (Test-Path $py) {
    try {
        $hit = @(Select-String -Path $py -Pattern "dsh-purge" -SimpleMatch -ErrorAction Stop).Count
        Write-Host "      mentions: $hit"
        if ($hit -ge 1) {
            Check-Ok "dsh-purge referenced in patch.yml"
        } else {
            Check-Fail "dsh-purge NOT referenced in patch.yml"
        }
    } catch {
        Check-Fail "patch.yml read error: $($_.Exception.Message)"
    }
} else {
    Check-Fail "cordis.patch.yml not found: $py"
}

# ---- Summary ----
Write-Host ""
Write-Host "result: pass=$pass fail=$fail"
if ($fail -gt 0) {
    Write-Host "FAILED - user will not see the plugin entry after install"
    exit 1
}
Write-Host "ALL PASSED"
exit 0
