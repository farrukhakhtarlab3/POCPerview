# POCPerview
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force


Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*Quarantine*" } | Remove-Item


$cert = New-SelfSignedCertificate -Subject "CN=QuarantineAgentPOC" -CertStoreLocation "Cert:\CurrentUser\My" -KeySpec KeyExchange -NotAfter (Get-Date).AddYears(1)


$cert.PrivateKey


$desktop = [Environment]::GetFolderPath('Desktop')


$desktop


$cert | Export-Certificate -FilePath "$desktop\QuarantineAgentPOC.cer"


dir "$desktop\QuarantineAgentPOC.cer"

//if not correct
$cert | Export-Certificate -FilePath "$env:USERPROFILE\QuarantineAgentPOC.cer"

$cert.Thumbprint


$cert | Export-Certificate -FilePath "$env:USERPROFILE\Desktop\QuarantineAgentPOC.cer"


$cert.Thumbprint


