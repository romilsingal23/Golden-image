<powershell>
# Retrieve the token using gcloud
$bearer = (gcloud secrets versions access latest --secret=prisma-token --project=zjmqcnnb-gf42-i38m-a28a-y3gmil).Trim()

# Define parameters for Invoke-WebRequest
$parameters = @{
    Uri     = 'https://us-east1.cloud.twistlock.com/us-1-111573393/api/v1/scripts/defender.ps1'
    Method  = "Post"
    Headers = @{ "Authorization" = "Bearer $bearer" }
    OutFile = "defender.ps1"
}

# Add trust for SSL/TLS certificates (if required)
if ($PSEdition -eq "Desktop") {
    Add-Type -TypeDefinition @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
} else {
    $parameters.SkipCertificateCheck = $true
}

# Set the security protocol to TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Make the web request to download the defender script
Invoke-WebRequest @parameters

# Execute the downloaded script
.\defender.ps1 -type serverWindows -consoleCN us-east1.cloud.twistlock.com -install -u
</powershell>
