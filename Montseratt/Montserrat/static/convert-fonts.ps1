param(
    [string]$InputDir = ".",
    [string]$OutDir = ".\webfonts",
    [switch]$EmitCss  # add -EmitCss to also generate fonts.css
)

# --- prerequisites -----------------------------------------------------------
function Require-Cmd($name) {
    $null = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $?) {
        Write-Error "Missing $name. Please install Node.js (includes npx) from https://nodejs.org/"
        exit 1
    }
}
Require-Cmd "npx"

# Ensure output directory exists
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path 2>$null
if (-not $OutDir) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
    $OutDir = (Resolve-Path ".\webfonts").Path
}

$InputDir = (Resolve-Path -LiteralPath $InputDir).Path
$ttfs = Get-ChildItem -LiteralPath $InputDir -Filter *.ttf -File -Recurse
if ($ttfs.Count -eq 0) {
    Write-Host "No .ttf files found in $InputDir"
    exit 0
}

# --- helpers -----------------------------------------------------------------
function Guess-FontWeight($name) {
    $n = $name.ToLower()
    switch -Regex ($n) {
        'thin' { return 100 }
        'extralight|ultralight' { return 200 }
        'light' { return 300 }
        'regular|book|normal' { return 400 }
        'medium' { return 500 }
        'semibold|demibold' { return 600 }
        'bold' { return 700 }
        'extrabold|ultrabold|heavy' { return 800 }
        'black|heavy' { return 900 }
        default { return 400 }
    }
}
function Guess-FontStyle($name) {
    return ($name -match '(?i)italic') ? 'italic' : 'normal'
}
function Guess-FontFamily($fileName) {
    # Strip common style tokens to get a decent family name guess
    $base = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $clean = $base -replace '(?i)-(thin|extra(light|bold)|ultra(light|bold)|semi|demi|medium|bold|black|heavy|regular|book|italic)+', ''
    $clean = $clean -replace '[_\-]+$', ''
    return $clean
}

# --- convert -----------------------------------------------------------------
$converted = @()
foreach ($f in $ttfs) {
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $woff2 = Join-Path $OutDir "$base.woff2"
    $woff = Join-Path $OutDir "$base.woff"

    if (-not (Test-Path $woff2)) {
        Write-Host "→ woff2: $base"
        npx --yes ttf2woff2 "$($f.FullName)" -o "$woff2" 2>$null
    }
    else {
        Write-Host "✓ woff2 exists: $base"
    }

    if (-not (Test-Path $woff)) {
        Write-Host "→ woff : $base"
        # ttf2woff CLI takes input + output as positional args
        npx --yes ttf2woff "$($f.FullName)" "$woff" 2>$null
    }
    else {
        Write-Host "✓ woff exists : $base"
    }

    $converted += [PSCustomObject]@{
        File        = $f.FullName
        WOFF2       = $woff2
        WOFF        = $woff
        FamilyGuess = (Guess-FontFamily $f.Name)
        Weight      = (Guess-FontWeight $f.Name)
        Style       = (Guess-FontStyle $f.Name)
    }
}

# --- optional CSS emission ---------------------------------------------------
if ($EmitCss) {
    $cssPath = Join-Path $OutDir "fonts.css"
    $sb = New-Object System.Text.StringBuilder

    foreach ($c in $converted) {
        # Family guess can vary per file; you can edit later to your canonical family (e.g., "Montserrat")
        $family = $c.FamilyGuess
        $woffRel = [IO.Path]::GetFileName($c.WOFF)
        $woff2Rel = [IO.Path]::GetFileName($c.WOFF2)
        $ttfRel = [IO.Path]::GetFileName($c.File)

        $null = $sb.AppendLine("@font-face {")
        $null = $sb.AppendLine("  font-family: '$family';")
        $null = $sb.AppendLine("  src: url('./$woff2Rel') format('woff2'),")
        $null = $sb.AppendLine("       url('./$woffRel')  format('woff'),")
        $null = $sb.AppendLine("       url('../$(Split-Path -Leaf $InputDir)/$ttfRel') format('truetype');")
        $null = $sb.AppendLine("  font-weight: $($c.Weight);")
        $null = $sb.AppendLine("  font-style: $($c.Style);")
        $null = $sb.AppendLine("  font-display: swap;")
        $null = $sb.AppendLine("}")
        $null = $sb.AppendLine()
    }
    Set-Content -LiteralPath $cssPath -Value $sb.ToString() -Encoding UTF8
    Write-Host "📝 CSS written to $cssPath"
}

Write-Host "`nDone. Converted $($converted.Count) font(s) to $OutDir."
