def generate_user_data_script(image, prisma_base_url, path_to_console, token):
    response = create_secret('prisma-token', token)
    print("response", response)
    if image['os_type'] == 'Windows':
        script = f"""
<powershell>
$bearer = (gcloud secrets versions access latest --secret=prisma-token --project={project_id})
$parameters = @{
    Uri = '{path_to_console}/api/v1/scripts/defender.ps1';
    Method = "Get";
    Headers = @{{ "Authorization" = "Bearer $bearer" }};
    OutFile = "defender.ps1";
};
# Handle SSL certificate validation for the console endpoint
if ($PSEdition -eq 'Desktop') {{
    Add-Type -TypeDefinition @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {{
        public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {{
            return true;
        }}
    }}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy;
}} else {{
    $parameters.SkipCertificateCheck = $true;
}}
# Configure TLS settings
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
# Download and execute the Prisma Defender script
Invoke-WebRequest @parameters
.\defender.ps1 -type serverWindows -consoleCN {prisma_base_url} -install -u
</powershell>
"""
