$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$supersetDirectory = Join-Path $repositoryRoot 'superset'
$supersetEnvFile = Join-Path $supersetDirectory '.env'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "El comando '$Command $($Arguments -join ' ')' terminó con código $LASTEXITCODE."
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'No se encontró Docker. Instala Docker Desktop, ábrelo y vuelve a ejecutar este script.'
}

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'No se encontró npx. Instala Node.js (que incluye npm/npx) y vuelve a ejecutar este script.'
}

if (-not (Test-Path $supersetEnvFile)) {
    throw "No existe $supersetEnvFile. Crea superset\.env a partir de superset\.env.example y configura sus valores antes de continuar."
}

Write-Host 'Verificando que Docker Desktop esté activo...'
Invoke-CheckedCommand -Command 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}')

Write-Host "`nIniciando Supabase local..."
Push-Location $repositoryRoot
try {
    Invoke-CheckedCommand -Command 'npx' -Arguments @('supabase', 'start')
}
finally {
    Pop-Location
}

Write-Host "`nIniciando Apache Superset..."
Push-Location $supersetDirectory
try {
    Invoke-CheckedCommand -Command 'docker' -Arguments @('compose', 'up', '-d', '--build')
}
finally {
    Pop-Location
}

Write-Host "`nBackend local iniciado."
Write-Host 'Supabase Studio: http://127.0.0.1:54323'
Write-Host 'Apache Superset: http://localhost:8088'
Write-Host 'Las credenciales de Superset están en el documento privado "claves y contraseñas importantes".'
Write-Host 'Este script no ejecuta db reset ni las pruebas de base de datos.'
