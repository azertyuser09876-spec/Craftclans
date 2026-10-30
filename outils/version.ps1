# Calcule et écrit la nouvelle version du jeu. Appelé par publier.bat.
#   -Type patch|mineure|majeure   0.3.2 -> 0.3.3 | 0.4.0 | 1.0.0
#   -Simuler                      affiche la nouvelle version sans rien modifier
param(
    [Parameter(Mandatory = $true)][ValidateSet('patch', 'mineure', 'majeure')][string]$Type,
    [switch]$Simuler
)
$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

$actuelle = ([IO.File]::ReadAllText("$racine\VERSION")).Trim()
$p = $actuelle.Split('.') | ForEach-Object { [int]$_ }
switch ($Type) {
    'patch'   { $p[2]++ }
    'mineure' { $p[1]++; $p[2] = 0 }
    'majeure' { $p[0]++; $p[1] = 0; $p[2] = 0 }
}
$nouvelle = "$($p[0]).$($p[1]).$($p[2])"
if ($Simuler) { Write-Output $nouvelle; exit 0 }

[IO.File]::WriteAllText("$racine\VERSION", "$nouvelle`n", $utf8)

$f = "$racine\project.godot"
$t = [IO.File]::ReadAllText($f)
$t = [regex]::Replace($t, 'config/version="[^"]*"', "config/version=`"$nouvelle`"")
[IO.File]::WriteAllText($f, $t, $utf8)

$f = "$racine\export_presets.cfg"
$t = [IO.File]::ReadAllText($f)
$t = [regex]::Replace($t, 'application/file_version="[^"]*"', "application/file_version=`"$nouvelle.0`"")
$t = [regex]::Replace($t, 'application/product_version="[^"]*"', "application/product_version=`"$nouvelle.0`"")
$t = [regex]::Replace($t, 'version/name="[^"]*"', "version/name=`"$nouvelle`"")
# Le numéro de version Android doit augmenter à chaque release.
$code = [int]([regex]::Match($t, 'version/code=(\d+)').Groups[1].Value) + 1
$t = [regex]::Replace($t, 'version/code=\d+', "version/code=$code")
[IO.File]::WriteAllText($f, $t, $utf8)

Write-Output $nouvelle
