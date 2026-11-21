<#
.SYNOPSIS
  Renders an ATS-clean HTML resume to PDF on Windows via headless Chrome or Edge.

.DESCRIPTION
  Portable Windows PowerShell companion to render_resume_pdf.sh.
  Blocks "[TODO:" and "[USER INPUT NEEDED" placeholders unless --allow-todo / -AllowTodo
  is passed (exit code 2), verifies non-empty PDF output, and supports --strict-1-page /
  -Strict1Page (exit code 5 when page count != 1).

.EXAMPLE
  .\render_resume_pdf.ps1 .\resume_tailored.html .\Candidate_Company_Resume.pdf --strict-1-page
#>

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
  $msg = @"
Usage: render_resume_pdf.ps1 <input.html> <output.pdf> [--allow-todo|-AllowTodo] [--strict-1-page|-Strict1Page]

Exit codes:
  0  Success
  1  Invalid arguments, missing input HTML, or Chrome/Edge not found
  2  Unresolved "[TODO:" or "[USER INPUT NEEDED" placeholder found (without allow-todo)
  3  Headless browser rendering failed
  4  Output PDF missing or empty
  5  Strict 1-page verification failed (page count != 1)
"@
  [Console]::Error.WriteLine($msg)
}

function Resolve-ChromeBinary {
  if (-not [string]::IsNullOrWhiteSpace($env:RESUME_CHROME_BIN)) {
    if (Test-Path -LiteralPath $env:RESUME_CHROME_BIN -PathType Leaf) {
      return (Resolve-Path -LiteralPath $env:RESUME_CHROME_BIN).Path
    }
    $cmdOverride = Get-Command $env:RESUME_CHROME_BIN -ErrorAction SilentlyContinue
    if ($cmdOverride) {
      return $cmdOverride.Source
    }
    [Console]::Error.WriteLine("ERROR: RESUME_CHROME_BIN is set but not found: $($env:RESUME_CHROME_BIN)")
    return $null
  }

  $candidates = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:LOCALAPPDATA 'Chromium\Application\chrome.exe')
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  foreach ($cmdName in @('chrome', 'chrome.exe', 'msedge', 'msedge.exe', 'chromium')) {
    $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd.Source
    }
  }

  [Console]::Error.WriteLine('ERROR: No Chrome, Chromium, or Microsoft Edge executable found.')
  [Console]::Error.WriteLine('Install Google Chrome or set $env:RESUME_CHROME_BIN to the browser executable path.')
  return $null
}

function Get-PdfPageCount {
  param([string]$PdfPath)

  $bytes = [System.IO.File]::ReadAllBytes($PdfPath)
  $latin1 = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)

  $pagesMatches = [regex]::Matches($latin1, '/Type\s*/Pages\b[^<>]*?/Count\s+(\d+)')
  if ($pagesMatches.Count -gt 0) {
    $maxCount = 0
    foreach ($m in $pagesMatches) {
      $val = [int]$m.Groups[1].Value
      if ($val -gt $maxCount) {
        $maxCount = $val
      }
    }
    if ($maxCount -gt 0) {
      return $maxCount
    }
  }

  $leafMatches = [regex]::Matches($latin1, '/Type\s*/Page(?![sA-Za-z])')
  if ($leafMatches.Count -gt 0) {
    return $leafMatches.Count
  }

  return $null
}

$allowTodo = $false
$strict1Page = $false
$positional = New-Object System.Collections.Generic.List[string]

foreach ($arg in $RemainingArgs) {
  switch -Regex ($arg) {
    '^(--allow-todo|-AllowTodo)$' { $allowTodo = $true; continue }
    '^(--strict-1-page|-Strict1Page)$' { $strict1Page = $true; continue }
    '^(-h|--help|-Help)$' { Show-Usage; exit 0 }
    '^-' {
      [Console]::Error.WriteLine("ERROR: Unknown option: $arg")
      Show-Usage
      exit 1
    }
    default { $positional.Add($arg) }
  }
}

if ($positional.Count -ne 2) {
  [Console]::Error.WriteLine('ERROR: Expected <input.html> and <output.pdf>.')
  Show-Usage
  exit 1
}

$inputHtml = $positional[0]
$outputPdf = $positional[1]

if (-not (Test-Path -LiteralPath $inputHtml -PathType Leaf)) {
  [Console]::Error.WriteLine("ERROR: Input HTML not found: $inputHtml")
  exit 1
}

$htmlContent = Get-Content -LiteralPath $inputHtml -Raw -Encoding UTF8
$placeholderMatches = [regex]::Matches($htmlContent, '\[TODO:|\[USER INPUT NEEDED')
if ($placeholderMatches.Count -gt 0) {
  if (-not $allowTodo) {
    [Console]::Error.WriteLine("ERROR: Unresolved placeholder(s) found in ${inputHtml}:")
    $lines = $htmlContent -split "`r?`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
      if ($lines[$i] -match '\[TODO:|\[USER INPUT NEEDED') {
        [Console]::Error.WriteLine("$($i + 1): $($lines[$i])")
      }
    }
    [Console]::Error.WriteLine('Resolve placeholders before rendering final PDF, or pass --allow-todo / -AllowTodo for drafts.')
    exit 2
  } else {
    Write-Output 'INFO: --allow-todo enabled; rendering draft despite unresolved placeholder(s).'
  }
}

if ($htmlContent -match '\{\{[A-Z0-9_]+\}\}') {
  [Console]::Error.WriteLine("WARNING: Unreplaced {{...}} template token(s) detected in $inputHtml.")
}

$chromeBin = Resolve-ChromeBinary
if (-not $chromeBin) {
  exit 1
}

$inputAbs = (Resolve-Path -LiteralPath $inputHtml).Path
$outputDir = Split-Path -Parent $outputPdf
if ([string]::IsNullOrWhiteSpace($outputDir)) {
  $outputDir = (Get-Location).Path
}
if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$outputDirAbs = (Resolve-Path -LiteralPath $outputDir).Path
$outputAbs = Join-Path $outputDirAbs (Split-Path -Leaf $outputPdf)

$inputUri = ([System.Uri]::new($inputAbs)).AbsoluteUri
$tempProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("chrome-resume-pdf-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempProfile -Force | Out-Null

try {
  $chromeArgs = @(
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--no-pdf-header-footer',
    "--user-data-dir=$tempProfile",
    "--print-to-pdf=$outputAbs",
    $inputUri
  )

  $proc = Start-Process -FilePath $chromeBin -ArgumentList $chromeArgs -NoNewWindow -Wait -PassThru
  if ($proc.ExitCode -ne 0) {
    [Console]::Error.WriteLine("ERROR: Headless browser PDF rendering failed with exit code $($proc.ExitCode).")
    exit 3
  }
} finally {
  if (Test-Path -LiteralPath $tempProfile) {
    Remove-Item -LiteralPath $tempProfile -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path -LiteralPath $outputAbs -PathType Leaf)) {
  [Console]::Error.WriteLine("ERROR: Output PDF is missing: $outputAbs")
  exit 4
}

$fileInfo = Get-Item -LiteralPath $outputAbs
if ($fileInfo.Length -le 0) {
  [Console]::Error.WriteLine("ERROR: Output PDF is empty: $outputAbs")
  exit 4
}

$pageCount = Get-PdfPageCount -PdfPath $outputAbs
Write-Output "Rendered PDF: $outputAbs ($($fileInfo.Length) bytes)"

if ($null -ne $pageCount) {
  Write-Output "Page count: $pageCount"
  if ($pageCount -gt 1) {
    if ($strict1Page) {
      [Console]::Error.WriteLine("ERROR: Rendered resume spans $pageCount pages (> 1 page) with --strict-1-page enabled.")
      exit 5
    }
    [Console]::Error.WriteLine("WARNING: Rendered resume spans $pageCount pages (> 1 page). Tighten wording or CSS spacing.")
  } elseif ($pageCount -eq 0) {
    if ($strict1Page) {
      [Console]::Error.WriteLine('ERROR: Could not verify 1-page count with --strict-1-page enabled.')
      exit 5
    }
    [Console]::Error.WriteLine('WARNING: Could not verify non-zero page count in PDF metadata; inspect via read_file.')
  }
} else {
  if ($strict1Page) {
    [Console]::Error.WriteLine('ERROR: Could not parse PDF page count with --strict-1-page enabled.')
    exit 5
  }
  [Console]::Error.WriteLine("WARNING: Could not parse page count automatically; inspect $outputAbs via read_file.")
}
