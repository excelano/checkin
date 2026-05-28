# If CheckIn asks for administrator approval

After downloading CheckIn from the App Store and trying to sign in with your work Microsoft 365 account, you may see a message that says something like "Need approval from your administrator," "Your administrator hasn't granted access to this app," or refers to an error code such as AADSTS65001 or AADSTS90094.

This is not a problem with CheckIn or with your account. It means your employer has set Microsoft 365 to require an administrator to approve any new third-party app before it can connect to company data. CheckIn is an independent app rather than a Microsoft product, so it has not been pre-approved across every company's tenant. Once an administrator on your IT team approves CheckIn, your next sign-in will work normally and you won't see the message again.

Approval takes most administrators under five minutes. The email below is written for you to copy, paste into a new message, and send to your IT or help desk team. It explains what CheckIn is, what data it reads, what data it does not read, and which specific Microsoft Graph permissions need to be granted. Your administrator can choose to approve CheckIn for just your account or for everyone in your company.

If your IT team has questions or wants to evaluate the app before approving, they can write to support@excelano.com directly.

## Email to send your IT team

**Subject**

```
Request to approve CheckIn for M365 (iOS app) for my Microsoft 365 account
```

**Body**

```
Hi [your IT or help desk team],

I'd like to use a third-party iOS app called CheckIn for M365 to view my Microsoft 365 inbox, calendar, and Teams activity on a single screen. When I try to sign in, the app reports that an administrator needs to approve it before I can access my account, and I'm writing to ask for that approval.

CheckIn for M365 is a status panel app that reads my Outlook inbox, calendar, and Teams chats and shows them together. It also lets me RSVP to meetings, mark email read or unread, send replies, and update my presence. It runs entirely on my iPhone and connects to Microsoft 365 through Microsoft Graph using Microsoft's standard MSAL authentication.

On privacy: CheckIn has no backend server, sends no data to its developer or any third party, and contains no analytics SDK or telemetry. The only network destinations it contacts are Microsoft Graph at graph.microsoft.com and Microsoft identity endpoints at login.microsoftonline.com. The full privacy policy is at https://excelano.com/legal/#checkin.

The Microsoft Graph permissions CheckIn requests fall into four areas. For sign-in, it asks for User.Read (basic name and email). For mail, it asks for Mail.ReadWrite (read inbox, mark read or unread, flag) and Mail.Send (in-app replies). For calendar, it asks for Calendars.ReadWrite (meeting list and RSVP) and MailboxSettings.ReadWrite (Out of Office toggle). For Teams, it asks for Chat.ReadWrite (read and reply to chats) and Presence.ReadWrite (view and set presence).

For your records, the app is registered in Microsoft Entra under the name "checkin" with Client ID (Application ID) 0ce3820d-db53-4b2e-9621-6c4ccc086d5a. The publisher is Excelano LLC.

To approve, you can grant consent in the Microsoft Entra admin center under Enterprise applications, either tenant-wide or scoped to just my account. Alternatively, opening the admin consent URL https://login.microsoftonline.com/organizations/adminconsent?client_id=0ce3820d-db53-4b2e-9621-6c4ccc086d5a while signed in as a Global Administrator will surface the consent dialog directly. Once approval completes, I can sign in to the app and won't see the prompt again.

If you have any questions about the app or want to evaluate it further before approving, the publisher can be reached at support@excelano.com.

Thanks for considering this,
[Your name]
```
