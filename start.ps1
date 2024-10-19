$defaultEntryPoint = 'start.ps1'
foreach ($drive in [char]'A'..[char]'Z')
{
    $drive = [char]$drive
    $path = "${drive}:\$defaultEntryPoint"
    if (Test-Path $path)
    {
        . "${drive}:\pwsh\promote-domain-controller.ps1"
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        shutdown /r /t 0
    }
}