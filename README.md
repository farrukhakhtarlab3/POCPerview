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




Hi, cert is generated — public key attached.

Thumbprint: <paste it here>

CSP provider, not CNG, so it should work with Connect-ExchangeOnline. Private key stays in my user cert store on the VDI and doesn't leave it.

Three other things when you get a chance:

Could you delete that client secret from the app registration? It went through Teams so best treated as exposed, and it's unusable for Exchange PowerShell anyway.

Which cmdlets ended up in the custom role? I'd asked for Get-QuarantineMessageHeader, Preview-QuarantineMessage and Export-QuarantineMessage alongside Get and Release — the triage logic needs to see inside the message to tell a payslip on its own from a payslip with an extra document attached.

What's the .onmicrosoft.com domain for the tenant? Connect-ExchangeOnline needs that for -Organization rather than woodside.com.

Thanks


$cert.Thumbprint


