$connectionName = "AzureRunAsConnection"
$SubscriptionId = "5f82da32-5cad-49a4-aec5-5ba8806e6d9c"

try
{
    # Get the connection "AzureRunAsConnection "
    ############################################
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
#Save-Module -Name AzureRM.HDInsight -Path . -RequiredVersion 1.0.3

#Select Souscription
#####################
Select-AzureRmSubscription -SubscriptionId $SubscriptionId

#Get Template Parameters for clusterName
########################################
$ResourceGroupName = (Get-AutomationVariable -Name "ResourceGroupName" -ErrorAction Stop)
$clusterName = (Get-AutomationVariable -Name "clusterName" -ErrorAction Stop)

write-output "Remove-AzureRmResource -ResourceId -ClusterName $clusterName"
Remove-AzureRmResource -ResourceId "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HDInsight/clusters/$clusterName" -Force