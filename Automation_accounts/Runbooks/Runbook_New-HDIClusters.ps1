
$SubscriptionId = "5f82da32-5cad-49a4-aec5-5ba8806e6d9c"
 
try
{
	# Get the connection "AzureRunAsConnection "
	############################################
	$connectionName = "AzureRunAsConnection"
	$servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

	"Logging in to Azure..."
	Add-AzureRmAccount `
	-ServicePrincipal `
	-TenantId $servicePrincipalConnection.TenantId `
	-ApplicationId $servicePrincipalConnection.ApplicationId `
	-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
	if (!$servicePrincipalConnection)
	{
		$ErrorMessage = "Connection $connectionName not found."
		throw $ErrorMessage
	} else{
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

#Select Souscription
#####################
$CertSPHDI = (Get-AutomationVariable -Name "DLSservicePrincipaCertName" -ErrorAction Stop)
Select-AzureRmSubscription -SubscriptionId $SubscriptionId
		
#Whoami
#######
$servicePrincipalcreds = (Get-AutomationPSCredential -Name "DLSservicePrincipalcreds" -ErrorAction Stop)
$servicePrincipalCertificatePassword = $servicePrincipalcreds.GetNetworkCredential().Password
		
#GetCert
########
$cert = Get-AutomationCertificate -Name $CertSPHDI
$bytes = $cert.Export("Pfx", $servicePrincipalCertificatePassword)
[System.IO.File]::WriteAllBytes("c:\mycert.pfx", $bytes)
$certbase64 = [System.Convert]::ToBase64String((Get-Content "c:\mycert.pfx" -Encoding Byte))

#Get Template Parameters
########################
$ResourceGroupName = (Get-AutomationVariable -Name "ResourceGroupName" -ErrorAction Stop)

#Get DeployName
###############
$DeployDate = Get-Date
$DeployDateHour = $DeployDate.Hour
$DeployDateMinute = $DeployDate.Minute
$DeployDateSecond = $DeployDate.Second
$DeployName = "HDI_" + "$ResourceGroupName" + "_" + "$DeployDateHour" + "_" + "$DeployDateMinute" + "_" + "$DeployDateSecond"

#Get StorageAccount & Context
##############################
$StorageAccountName = (Get-AutomationVariable -Name "StorageAccountBuildName" -ErrorAction Stop)
$StorageAccountName = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})
$BlobContainerTemplate = Get-AutomationVariable -Name "BlobContainerTemplate" -ErrorAction Stop

# Generate SAS token for the artifacts location
###############################################
$saskey = New-AzureStorageContainerSASToken -Container $BlobContainerTemplate -Context $storageaccountname.Context -Permission r -ExpiryTime (Get-Date).AddHours(4)

#Get ANother Template parameters
################################
$StorageAccountBuildName = (Get-AutomationVariable -Name "StorageAccountBuildName" -ErrorAction Stop)
$TemplateHDI = (Get-AutomationVariable -Name "TemplateHDI" -ErrorAction Stop)
$TemplateParametersHDI = (Get-AutomationVariable -Name "TemplateParametersHDI" -ErrorAction Stop)
[string]$templateuris = "https://"+ "$StorageAccountBuildName" + ".blob.core.windows.net/" + "$BlobContainerTemplate" + "/" +"$TemplateHDI" + "$saskey"
[string]$templateparametersuris = "https://"+ "$StorageAccountBuildName" + ".blob.core.windows.net/" + "$BlobContainerTemplate" + "/" +"$TemplateParametersHDI" + "$saskey"

#Downloadpackage
$DownloadPackageName = (Get-AutomationVariable -Name "DownloadPackageNameJson" -ErrorAction Stop)
[string]$DownloadPackageName = "https://"+ "$StorageAccountBuildName" + ".blob.core.windows.net/" + "$BlobContainerTemplate"  + "/" + "$DownloadPackageName" + "$saskey"
Write-Output "DownloadPackageName $DownloadPackageName"

$ArtifactContentName = Invoke-WebRequest -Uri "$DownloadPackageName" -UseBasicParsing | ConvertFrom-Json -ErrorAction Stop
write-output $ArtifactContentName.download_package
foreach( $package in $ArtifactContentName.download_package ) {
		$ArtifactName = $package.nom_livrable + "-" + $package.version + ".zip" + "|" + $package.checksum + "#" + $package.nom_initScript + "/" + $package.param_initScript + "?" + $ArtifactName
		[string]$ArtifactName = $ArtifactName.replace('/?','/argnull?').replace('#/','#initnull/').replace('; ',';').replace('{','').replace('}','')
}
$ReverseString = $ArtifactName.split('?')
[array]::Reverse($ReverseString)
$ArtifactName = $ReverseString -join "?"
Write-Output "ArtifactName $ArtifactName"



#Get Optionnal Parameters
#########################
$OptionalParameters = New-Object -TypeName Hashtable

$OptionalParameters['InputRootDir'] = (Get-AutomationVariable -Name "InputRootDir" -ErrorAction Stop)
$OptionalParameters['RootDir'] = (Get-AutomationVariable -Name "RootDir" -ErrorAction Stop)
[string]$OptionalParameters['ArtifactsName'] = $ArtifactName 
$OptionalParameters['StorageAccountDataName'] = (Get-AutomationVariable -Name "StorageAccountDataName" -ErrorAction Stop)
$OptionalParameters['StorageAccountBuildName'] = (Get-AutomationVariable -Name "StorageAccountBuildName" -ErrorAction Stop)
$OptionalParameters['clusterName'] = (Get-AutomationVariable -Name "clusterName" -ErrorAction Stop)
$OptionalParameters['BlobContainerHDI'] = (Get-AutomationVariable -Name "BlobContainerHDI" -ErrorAction Stop)
[string]$OptionalParameters['VnetResourceGroupName'] = (Get-AutomationVariable -Name "VnetResourceGroupName" -ErrorAction Stop)
[string]$OptionalParameters['SubnetName'] = (Get-AutomationVariable -Name "SubnetName" -ErrorAction Stop)
[string]$OptionalParameters['VirtualNetworkName'] = (Get-AutomationVariable -Name "VirtualNetworkName" -ErrorAction Stop)

$OptionalParameters['servicePrincipalCertificateContents'] = "$certbase64"
$OptionalParameters['aadTenantId'] = $servicePrincipalConnection.TenantId
$DLSservicePrincipalcreds = (Get-AutomationPSCredential -Name "DLSservicePrincipalcreds" -ErrorAction Stop)
$OptionalParameters['servicePrincipalApplicationId'] = $DLSservicePrincipalcreds.GetNetworkCredential().username
$servicePrincipalCertificatePassword = ConvertTo-SecureString $servicePrincipalCertificatePassword -AsPlainText -Force
$OptionalParameters['DLSservicePrincipalCertificatePassword'] = $servicePrincipalCertificatePassword

$ClusterUsercreds = (Get-AutomationPSCredential -Name "clusterAccount" -ErrorAction Stop)
$OptionalParameters['clusterLoginUserName'] = $ClusterUsercreds.GetNetworkCredential().username
$clusterLoginPassword = $ClusterUsercreds.GetNetworkCredential().Password
$OptionalParameters['clusterLoginPassword'] = ConvertTo-SecureString -String $clusterLoginPassword -AsPlainText -Force
$sshUserCreds = (Get-AutomationPSCredential -Name "sshAccount" -ErrorAction Stop)
$OptionalParameters['sshUserName'] = $sshUserCreds.GetNetworkCredential().username
$sshPassword = $sshUserCreds.GetNetworkCredential().Password
$OptionalParameters['sshPassword'] = ConvertTo-SecureString -String $sshPassword -AsPlainText -Force
$hiveUserCreds = (Get-AutomationPSCredential -Name "hiveAccount" -ErrorAction Stop)
$OptionalParameters['hiveUserName'] = $hiveUserCreds.GetNetworkCredential().username
$hivePassword = $hiveUserCreds.GetNetworkCredential().Password
$OptionalParameters['hivePassword'] = ConvertTo-SecureString -String $hivePassword -AsPlainText -Force
$oozieUserCreds = (Get-AutomationPSCredential -Name "oozieAccount" -ErrorAction Stop)
$OptionalParameters['oozieUserName'] = $oozieUserCreds.GetNetworkCredential().username
$ooziePassword = $oozieUserCreds.GetNetworkCredential().Password
$OptionalParameters['ooziePassword'] = ConvertTo-SecureString -String $ooziePassword -AsPlainText -Force

$ambariUserCreds = (Get-AutomationPSCredential -Name "AmbariUser" -ErrorAction Stop)
$ambariUserName = $ambariUserCreds.GetNetworkCredential().username
$ambariPassword = $ambariUserCreds.GetNetworkCredential().Password

[string]$OptionalParameters['SasKey']= $saskey
[string]$OptionalParameters['ADLStoreName'] = (Get-AutomationVariable -Name "ADLStoreName" -ErrorAction Stop)
[string]$OptionalParameters['BlobContainerTemplate'] = (Get-AutomationVariable -Name "BlobContainerTemplate" -ErrorAction Stop)


		#####Optional parameters ActionScript Log4J

$AppInsightCreds = (Get-AutomationPSCredential -Name "AppInsightKey" -ErrorAction Stop)
$AppInsightKey = $AppInsightCreds.GetNetworkCredential().Password
$OptionalParameters['AppInsightKey'] = ConvertTo-SecureString $AppInsightKey -AsPlainText -Force

$parametersfile = "C:\parameters.json"
try {
	Invoke-WebRequest -Uri $templateparametersuris -OutFile "$parametersfile"
}catch {
	Write-Output "StatusCode:" $_.Exception.Response.StatusCode.value__ 
	Write-Output "StatusDescription:" $_.Exception.Response.StatusDescription
}
write-output $OptionalParameters
###
Write-Output "Deploy HDI ..."
###
New-AzureRmResourceGroupDeployment -Name $DeployName -ResourceGroupName $resourcegroupname -TemplateUri $templateuris -TemplateParameterFile $parametersfile @OptionalParameters -Force -Verbose -ErrorVariable ErrorMessages

if ($ErrorMessages) {
	Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
}


#####Create ambari user with action script
$UriScriptAction = "https://"+ "$StorageAccountBuildName" + ".blob.core.windows.net/" + "$BlobContainerTemplate" + "/" +"addCustomUser.sh" + "$saskey"
Submit-AzureRmHDInsightScriptAction -ResourceGroupName $ResourceGroupName -ClusterName $OptionalParameters['clusterName'] -Name addUserAmbari -Uri $UriScriptAction -NodeTypes headnode -Parameters "$OptionalParameters['StorageAccountBuildName'] $ambariUserName $ambariPassword"
