# POCPerview
$cert = New-SelfSignedCertificate `
    -Subject 'CN=QuarantineAgentPOC' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeySpec KeyExchange `
    -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' `
    -NotAfter (Get-Date).AddYears(1)

$cert | Export-Certificate -FilePath "$env:USERPROFILE\Desktop\QuarantineAgentPOC.cer"
$cert.Thumbprint
