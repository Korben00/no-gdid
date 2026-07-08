# FAQ

### Does this make me anonymous to Microsoft?
No. Your GDID already exists on Microsoft's servers the moment you sign into a Microsoft
Account. `no-gdid` stops your machine from re-registering and reporting the device into
the correlation graph. It reduces *future* linkage; it does not retract the past and does
not hide you.

### Can't I just delete the GDID from the registry?
You can delete the `LID` value, but it's cosmetic. Restart `wlidsvc` or open any Microsoft
app and the exact same `g:<decimal>` comes back from the server. It's anchored to your
account, not to the local install. We verified this.

### I turned off Windows telemetry. Am I safe?
No. This is the biggest misconception. The GDID is reported through the Connected Devices
Platform (`CDPSvc`) and Delivery Optimization (`DoSvc`), not through the classic telemetry
service (`DiagTrack`). On our test machine DiagTrack was already stopped and the GDID was
fully present and reporting.

### Does using a local account instead of a Microsoft Account fix it?
It removes the MSA device PUID path we target here. But per the primary research, CDP also
has an anonymous device path when no account is signed in, so a separate identifier may
still be created. We haven't reproduced that case yet — treat "local account = fully clean"
as unproven.

### Will this break my PC?
It disables three services, so you lose Delivery Optimization peer caching, Phone Link /
"Continue on PC", and nearby sharing. Sign-in, apps, and updates keep working. Everything
is reversible with `Revert-GDID.ps1`, and on a VM a snapshot is the guaranteed rollback.

### Why does DoSvc need a registry edit instead of Set-Service?
`DoSvc` is protected at the Service Control Manager level: `Set-Service` returns "Access
denied" even in an elevated admin console. Writing `HKLM\SYSTEM\CurrentControlSet\Services\DoSvc\Start=4`
directly works, because the registry key's ACL allows admins where the SCM does not.

### Does reinstalling Windows give me a new GDID?
Yes, a fresh install mints a new PUID — but only if you don't sign back into the same
Microsoft Account, and the old device and its linked activity remain on Microsoft's side.
Rotation, not erasure.

### Is this legal / safe to run?
It's a defensive privacy tool for machines you own. It makes no network calls of its own,
sends nothing anywhere, and every change is reversible. Read the scripts — they're short.

### What actually protects sensitive activity, then?
Not depending on Windows for it: a live Linux system (or Tails) and full control of your
outbound traffic. `no-gdid` is harm reduction on Windows, not an anonymity cloak.
