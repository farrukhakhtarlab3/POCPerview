# POCPerview
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force


Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*Quarantine*" } | Remove-Item


$cert = New-SelfSignedCertificate -Subject "CN=QuarantineAgentPOC" -CertStoreLocation "Cert:\CurrentUser\My" -KeySpec KeyExchange -NotAfter (Get-Date).AddYears(1)


$cert.PrivateKey


$cert | Export-Certificate -FilePath "$env:USERPROFILE\Desktop\QuarantineAgentPOC.cer"


$cert.Thumbprint


