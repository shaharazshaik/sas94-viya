param (
	[string]$stg_acc_name,
	[string]$stg_key,
	[string]$file_share_name,
	[string]$depot_folder_name,
	[string]$clients_sid,
	[string]$app_name,
	[string]$mid_name,
	[string]$domain_name,
	[string]$artifact_loc
)

Set-PSDebug -Trace 1;
$logdir = "C:\saslog"
$mid_fqdn= "${app_name}${mid_name}.${domain_name}"
New-Item -Path $logdir -ItemType directory
Invoke-WebRequest -Uri ${artifact_loc}properties/clients_install.properties -OutFile ${logdir}\clients_install.properties
Invoke-WebRequest -Uri ${artifact_loc}properties/plan.xml -OutFile ${logdir}\plan.xml
(Get-Content -path ${logdir}\clients_install.properties -Raw) -replace 'client_sid',$clients_sid | Add-Content -Path ${logdir}\clients_install_new.properties
Remove-Item -Path ${logdir}\clients_install.properties
Move-Item -Path ${logdir}\clients_install_new.properties -Destination ${logdir}\clients_install.properties
(Get-Content -path ${logdir}\clients_install.properties -Raw) -replace 'depot_folder',$depot_folder_name | Add-Content -Path ${logdir}\clients_install_new.properties
Remove-Item -Path ${logdir}\clients_install.properties
Move-Item -Path ${logdir}\clients_install_new.properties -Destination ${logdir}\clients_install.properties
(Get-Content -path ${logdir}\clients_install.properties -Raw) -replace 'mid_fqdn',$mid_fqdn | Add-Content -Path ${logdir}\clients_install_new.properties
Remove-Item -Path ${logdir}\clients_install.properties
Move-Item -Path ${logdir}\clients_install_new.properties -Destination ${logdir}\clients_install.properties

$connectTestResult = Test-NetConnection -ComputerName "${stg_acc_name}.file.core.windows.net" -Port 445

if ($connectTestResult.TcpTestSucceeded) {
    # Save the password so the drive will persist on reboot
	Set-PSDebug -Trace 1;
    cmd.exe /C "cmdkey /add:`"${stg_acc_name}.file.core.windows.net`" /user:`"Azure\${stg_acc_name}`" /pass:`"${stg_key}`""
    # Mount the drive
    New-PSDrive -Name Z -PSProvider FileSystem -Root "\\${stg_acc_name}.file.core.windows.net\${file_share_name}" -Persist
} else {
    Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
}


cd "Z:\${depot_folder_name}"
.\setup.exe -lang en -deploy -datalocation C:\saslog -responsefile ${logdir}\clients_install.properties -quiet 
Start-Sleep -Seconds 1200

$latest = Get-ChildItem -Path ${logdir}\deployw* | Sort-Object LastAccessTime -Descending | Select-Object -First 1
$latest.name
cd $logdir
$sort_string = Select-String -Path $latest.name -Pattern "ExitInstance="
$alert = $sort_string | Select-String -pattern "ExitInstance=0" -notMatch
if ($alert) { 
	Install Failed
    throw "Install Is Failed"
    }
else {
    Write-Host "Install Is Sucess"
}

$Path = $env:TEMP; $Installer = "chrome_installer.exe"; Invoke-WebRequest "http://dl.google.com/chrome/install/375.126/chrome_installer.exe" -OutFile $Path\$Installer; Start-Process -FilePath $Path\$Installer -Args "/silent /install" -Verb RunAs -Wait; Remove-Item $Path\$Installer
