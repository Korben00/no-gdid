# no-gdid

**Read, understand, and silence the Windows Global Device Identifier (GDID) — the
hidden per-account device ID that helped the FBI locate a suspect who was using a VPN.**

> ⚠️ **Honest disclaimer up front:** this tool does **not** erase your GDID and does
> **not** make you anonymous. The GDID lives on Microsoft's servers, tied to your
> Microsoft Account, the moment you sign in. `no-gdid` stops your machine from
> *re-registering and reporting* it — it cannot undo what Microsoft already has. For
> real privacy on sensitive work, the only reliable answer is not to depend on Windows.

Every finding here was reproduced on a real Windows 11 Pro VM (build 26200) before it
was written down. Nothing is theoretical. See
[`docs/technical-writeup.md`](docs/technical-writeup.md) for the evidence, tagged by
confidence level — and [How this was built](#how-this-was-built) for what that
verification actually involved.

---

## The story

In 2026 the FBI tracked a Scattered Spider suspect who rotated IPs through a VPN across
three countries. What gave him away was a **GDID** — a device identifier Microsoft ties
to a Windows installation and shares with law enforcement on subpoena. It doesn't change
when you change your IP. This repo takes that identifier apart and shows what you can
actually do about it.

## What the GDID really is

Not a hardware hash — a **64-bit MSA Device PUID** minted by `login.live.com`, cached
locally in the registry, registered into Microsoft's Device Directory Service graph, and
reported through Delivery Optimization.

```
wlidsvc  ── mint ──►  PUID from login.live.com
   │                  cached at HKCU\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties\LID
CDPSvc / CDPUserSvc  ── register ──►  Device Directory Service (dds.microsoft.com)
   │
DoSvc  ── report ──►  UCDOStatus.GlobalDeviceId  (Azure Monitor)
```

The registry LID (hex) maps to the server value `g:<decimal>`. All Windows device PUIDs
sit in the `0x0018…` namespace (verified: our test value and the one from the court
filing share it).

## Quick start

All scripts are PowerShell, ASCII-only, and run under any codepage. Open an **elevated**
PowerShell.

```powershell
# 1. See your own GDID and which parts of the chain are active (read-only, safe)
powershell -ExecutionPolicy Bypass -File .\audit\Get-GDID-Audit.ps1

# 2. Preview what the mitigation would change (no changes yet)
powershell -ExecutionPolicy Bypass -File .\mitigate\Disable-GDID-Services.ps1
powershell -ExecutionPolicy Bypass -File .\mitigate\Block-GDID-Endpoints.ps1

# 3. Apply it: stop the report chain + blackhole its endpoints, keep MSA working
powershell -ExecutionPolicy Bypass -File .\mitigate\Disable-GDID-Services.ps1 -Apply
powershell -ExecutionPolicy Bypass -File .\mitigate\Block-GDID-Endpoints.ps1 -Apply

# Undo everything
powershell -ExecutionPolicy Bypass -File .\mitigate\Revert-GDID.ps1
```

**Test in a VM with a snapshot first.** The mitigation disables system services.

## What each part does

| Path | Purpose | Writes? |
|---|---|---|
| `audit/Get-GDID-Audit.ps1` | Reads your GDID + the state of the 5-service chain | No |
| `audit/Get-GDID-Traffic.ps1` | Maps the chain's real network endpoints | No |
| `mitigate/Block-GDID-Endpoints.ps1` | Blackholes the DDS/DO endpoints in `hosts` (keeps `login.live.com`) | With `-Apply` |
| `mitigate/Disable-GDID-Services.ps1` | Disables `CDPSvc`/`DoSvc`/`CDPUserSvc` (keeps `wlidsvc`) | With `-Apply` |
| `mitigate/Revert-GDID.ps1` | Restores services + cleans `hosts` | Yes |
| `experiments/` | Snapshot-gated probes used to prove the findings | Destructive, gated |
| `docs/` | Sourced technical write-up + FAQ | — |

## What we proved (and what doesn't work)

- **Reading your GDID works.** It's right there in the registry.
- **Deleting it is cosmetic.** Remove the key, restart `wlidsvc`, touch any Microsoft
  app — it comes back *identical* from the server. It's anchored to your account.
- **Turning off "telemetry" (DiagTrack) does nothing.** The GDID rides CDP/Delivery
  Optimization, not classic telemetry. That common advice is wrong.
- **You can silence the reporting without signing out.** Disable the CDP/DO services and
  blackhole their endpoints; the chain goes quiet while your Microsoft Account keeps
  working. Caveat: `DoSvc` refuses `Set-Service` even as admin — it's disabled via the
  registry `Start=4` (see the write-up).
- **The past is gone.** The PUID already exists server-side. Blocking reduces future
  correlation; it doesn't retract what was sent.

## Trade-offs

Disabling these services breaks Delivery Optimization peer caching, Phone Link /
"Continue on PC", and nearby sharing. `wlidsvc` and `login.live.com` are left alone so
Microsoft Account sign-in keeps working.

## Docs

- [`docs/technical-writeup.md`](docs/technical-writeup.md) — the full chain, registry
  paths, endpoints, and every claim tagged by confidence (`[COURT]`, `[OBSERVED]`,
  `[STATIC]`, `[NO-GDID VÉRIFIÉ]`).
- [`docs/FAQ.md`](docs/FAQ.md) — short answers to the obvious questions.

## How this was built

This project was investigated and written with heavy AI assistance (Claude). The commit
history says so, and so does this section — you should not have to dig for it.

What that means in practice, honestly:

- **The AI drove the investigation.** It read the reverse engineering, mapped the
  service chain, proposed the hypotheses to test, and wrote most of the PowerShell and
  the prose you are reading.
- **I ran every test myself, on my own VM.** Windows 11 Pro build 26200 in VMware,
  signed into a real Microsoft Account, snapshot before each destructive step. The GDID
  in the screenshots is that VM's, which is why I am comfortable showing it.
- **The claims that mattered were checked by hand, not accepted.** Deleting the `LID`
  key and restarting `wlidsvc` really does bring back the *same* identifier once any
  Microsoft app asks for it — I watched it happen. `DiagTrack` was already stopped on
  that VM and the GDID was still there, which is what killed the "just turn off
  telemetry" advice. `DoSvc` really does refuse `Set-Service` as admin, which is why the
  script goes through the registry instead. Each of these started as an AI hypothesis
  and several of them were wrong until tested.
- **What isn't mine, I don't claim.** My testing was Windows 11 Pro with a Microsoft
  Account. The local-account case was an open question here until
  [@Berbe](https://github.com/Berbe) contributed the observation on Windows 10 LTSC
  19044.7417 (a `LID`/GDID exists from install even with a local account only). The
  write-up records whose build each finding comes from — if a claim carries no build
  number, treat it as weaker.

If you find a claim here that does not hold on your machine, open an issue with your
build number — that is worth more to this repo than agreement.

## Credits

- Primary reverse engineering: [`SmtimesIWndr/gdid-reversal`](https://github.com/SmtimesIWndr/gdid-reversal).
- Local-account observation on Windows 10 LTSC: [@Berbe](https://github.com/Berbe) (PR #3).
- Case facts: *United States v. Peter Stokes*, N.D. Ill., July 2026.

## License

[MIT](LICENSE). Defensive, privacy-oriented tooling. Use it on machines you own.
