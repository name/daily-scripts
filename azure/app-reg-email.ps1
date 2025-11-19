$clientID = "CLIENT_ID"
$clientSecret = "CLIENT_SECRET"
$tenantID = "TENANT_ID"
$mailSender = "SENDER"
$mailRecipient = "RECIPIENT"

$tokenBody = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = $clientID
    Client_Secret = $clientSecret
}
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token" -Method POST -Body $tokenBody

$headers = @{
    "Authorization" = "Bearer $($tokenResponse.access_token)"
    "Content-type"  = "application/json"
}

$URLsend = "https://graph.microsoft.com/v1.0/users/$mailSender/sendMail"
$BodyJsonSend = @"
{
    "message": {
        "subject": "Test email using Microsoft Graph API",
        "body": {
            "contentType": "Text",
            "content": "This is a test email sent using Microsoft Graph API"
        },
        "toRecipients": [
            {
                "emailAddress": {
                    "address": "$mailRecipient"
                }
            }
        ]
    },
    "saveToSentItems": "true"
}
"@

Invoke-RestMethod -Method POST -Uri $URLsend -Headers $headers -Body $BodyJsonSend
