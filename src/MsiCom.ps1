# Late-bound access to the WindowsInstaller COM automation interface.
# Windows PowerShell cannot early-bind these objects, so every call goes through InvokeMember.

$ErrorActionPreference = 'Stop'

function Invoke-MsiMethod {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [object[]] $Arguments = @()
    )
    $Object.GetType().InvokeMember(
        $Name,
        [System.Reflection.BindingFlags]::InvokeMethod,
        $null,
        $Object,
        $Arguments)
}

function Get-MsiComProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [object[]] $Arguments = @()
    )
    $Object.GetType().InvokeMember(
        $Name,
        [System.Reflection.BindingFlags]::GetProperty,
        $null,
        $Object,
        $Arguments)
}

function Set-MsiComProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [object[]] $Arguments = @()
    )
    $null = $Object.GetType().InvokeMember(
        $Name,
        [System.Reflection.BindingFlags]::SetProperty,
        $null,
        $Object,
        $Arguments)
}

function Remove-MsiComObject {
    param($Object)
    if ($null -ne $Object -and [System.Runtime.InteropServices.Marshal]::IsComObject($Object)) {
        try { $null = [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object) } catch { }
    }
}

function ConvertTo-MsiIdentifier {
    param([Parameter(Mandatory = $true)][string] $Name)
    '`' + $Name + '`'
}

function New-MsiInstaller {
    New-Object -ComObject WindowsInstaller.Installer
}
