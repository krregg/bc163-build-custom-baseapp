Param(
    [Parameter(Mandatory=$true)]
    [string] $version,
    [Parameter(Mandatory=$true)]
    [pscredential] $credential,
    [Parameter(Mandatory=$false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,
    [Parameter(Mandatory=$false)]
    [string] $buildSymbolsFolder = (Join-Path $buildProjectFolder ".alPackages"),
    [Parameter(Mandatory=$false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,
    [Parameter(Mandatory=$true)]
    [string] $licenceFile,
    [Parameter(Mandatory=$true)]
    [string]$jsonPathMain,
    [Parameter(Mandatory=$true)]
    [string]$workingDirectory,
    [Parameter(Mandatory=$true)]
    [string] $appFolders
)

$module = Get-InstalledModule -Name navcontainerhelper -ErrorAction Ignore
if ($module) {
    $versionStr = $module.Version.ToString()
    Write-Host "NavContainerHelper $VersionStr is installed"
    Write-Host "Determine latest NavContainerHelper version"
    $latestVersion = (Find-Module -Name navcontainerhelper).Version
    $latestVersionStr = $latestVersion.ToString()
    Write-Host "NavContainerHelper $latestVersionStr is the latest version"
    if ($latestVersion -gt $module.Version) {
        Write-Host "Updating NavContainerHelper to $latestVersionStr"
        Update-Module -Name navcontainerhelper -Force -RequiredVersion $latestVersionStr
        Write-Host "NavContainerHelper updated"
    }
} else {
    if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
        Write-Host "Installing NuGet Package Provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
    }
    Write-Host "Installing NavContainerHelper"
    Install-Module -Name navcontainerhelper -Force
    $module = Get-InstalledModule -Name navcontainerhelper -ErrorAction Ignore
    $versionStr = $module.Version.ToString()
    Write-Host "NavContainerHelper $VersionStr installed"
}

$settings = (Get-Content (Join-Path $PSScriptRoot "..\settings.json") | ConvertFrom-Json)
$artefactInfo  = $settings.versions | Where-Object { $_.version -eq $version }
$artefactVersion = $artefactInfo.artefactVersion
$containerName = "$($settings.name)"

$myCoulture = 'sl-SI'
$segments = "$PSScriptRoot".Split('\')
$rootFolder = "$($segments[0])\$($segments[1])"
$additionalParameters = @("--volume ""$($rootFolder):C:\Agent""", "-e locale=""$($myCoulture)""")

$artifactUrl = Get-BCArtifactUrl -version $artefactVersion -country w1 -select Latest

Write-Host "`r`nRead file $jsonPathMain"
$jsonPath = Join-Path -Path $workingDirectory -ChildPath $jsonPathMain
$jsonContent = ([System.IO.File]::ReadAllText($jsonPath)  | ConvertFrom-Json)

$descr = $jsonContent.description
$defdescr = $descr.Split(",")[0] 
If ($defdescr -ne '') {
    $jsonContent.description = "$defdescr, Update: $Env:BUILD_BUILDNUMBER" 
}
elseif ($defdescr -eq '') {
    $jsonContent.description = "Update: $Env:BUILD_BUILDNUMBER"
}
$newdescr = $jsonContent.description

$jsonContent | ConvertTo-Json | Out-File -FilePath $jsonPath -Encoding utf8 -Force


Write-Host "`r`n`r`n#######################################################################################"
Write-Host "# containerName: $containerName"
Write-Host "# artefactVersion: $artefactVersion "
Write-Host "# rootFolder: $rootFolder"
Write-Host "# artifactUrl: $artifactUrl"
Write-Host "# licenceFile: $licenceFile"
Write-Host "# buildProjectFolder: $buildProjectFolder\BaseApp"
Write-Host "# buildArtifactFolder: $buildArtifactFolder\BaseApp"
Write-Host "# Updating app.json $appName file, description section: $newdescr"
Write-Host "#######################################################################################`r`n"

New-BcContainer `
    -accept_eula `
    -containerName $containerName `
    -artifactUrl $artifactUrl `
    -Credential $credential `
    -auth UserPassword `
    -additionalParameters $additionalParameters `
    -updateHosts

Get-NavContainerAppInfo -containerName $containerName | ForEach-Object { 
    if (($_.Name -ne "Base Application") -and ($_.Name -ne "System Application") -and ($_.Name -ne "Application")) {
        UnInstall-NavContainerApp -containerName $containerName -appName $_.Name -appVersion $_.Version -Force
    }
}
Get-NavContainerAppInfo -containerName $containerName | ForEach-Object { 
    if (($_.Name -ne "Base Application") -and ($_.Name -ne "System Application") -and ($_.Name -ne "Application")) {
        UnPublish-NavContainerApp -containerName $containerName -appName $_.Name  
    }
}

UnInstall-NavContainerApp -containerName $containerName -appName "Application"
UnPublish-NavContainerApp -containerName $containerName -appName "Application"
UnInstall-NavContainerApp -containerName $containerName -appName "Base Application"
UnPublish-NavContainerApp -containerName $containerName -appName "Base Application"

Invoke-ScriptInNavContainer -containerName $containerName -ScriptBlock {        
    Get-NAVTenant BC | Sync-NavTenant -Mode Sync -Force 
}
$newfolder = Join-Path $buildArtifactFolder "BaseApp"
try {
    Remove-Item -Path $newfolder -Recurse -ErrorAction SilentlyContinue
    New-Item -Path $newfolder -ItemType Directory
}
catch {
    throw "$_.Exception.Message"
}

$appFile = Compile-AppInNavContainer -containerName $containerName `
                                    -credential $credential `
                                    -appProjectFolder (Join-Path $buildProjectFolder "BaseApp") `
                                    -appOutputFolder (Join-Path $buildArtifactFolder "BaseApp") `
                                    -UpdateSymbols

if ($appFile -and (Test-Path $appFile)) {
    Copy-Item -Path $appFile -Destination $buildSymbolsFolder -Force
}

# debug helper commands
# $buildProjectFolder ="C:\agent\_w\17\s"
# $buildArtifactFolder ="C:\agent\_w\17\a"
# $credential = New-Object pscredential 'sa', (ConvertTo-SecureString -String 'Password%01!' -AsPlainText -Force)
