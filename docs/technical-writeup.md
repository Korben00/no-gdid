# Writeup technique — GDID Windows

Ce document reprend la chaîne de provisioning/reporting du GDID en conservant les
**niveaux de confiance** de la source primaire ([`SmtimesIWndr/gdid-reversal`](https://github.com/SmtimesIWndr/gdid-reversal)).
Tant qu'une ligne n'est pas marquée `[NO-GDID VÉRIFIÉ]`, elle n'a **pas** encore été
reproduite sur notre VM.

Légende :
- `[COURT]` — plainte fédérale *United States v. Peter Stokes* (N.D. Ill., 2026-07)
- `[OBSERVED]` — reproduit live par le chercheur (Windows 11 build 26200, capture ETW)
- `[STATIC]` — extrait des binaires/PDB Windows (`cdp.pdb`, `wlidsvc.pdb`)
- `[ASSESSED]` — déduction du chercheur
- `[NO-GDID VÉRIFIÉ]` — reproduit par nous sur la VM (à remplir)

## 1. Nature du GDID

- `[STATIC]` Le GDID est un **PUID 64 bits** (Passport Unique ID), pas un hash matériel.
- `[STATIC]` `wlidsvc` dialogue avec `login.live.com` en SOAP ; le serveur renvoie le
  Device PUID dans `HWPUIDFlipped` (XPath : `/S:Envelope/S:Body/ps:DeviceUpdatePropertiesResponse/HWPUIDFlipped`).

## 2. Stockage local

- `[OBSERVED]` `HKCU\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties` → `LID` (hex 16).
- `[OBSERVED]` Fallback : `HKCU\SOFTWARE\Microsoft\IdentityCRL\Immersive\production\Token\{...}` → `DeviceId`.
- `[OBSERVED]` Cache serveur (SYSTEM) : `HKLM\SOFTWARE\Microsoft\IdentityCRL\NegativeCache\<PUID>_<userSID>`
  (jetons ; scopes `dds.microsoft.com`, `activity.windows.com`).
- `[STATIC]` `HKLM\SOFTWARE\Microsoft\IdentityStore` → `DeviceId`.

## 3. Services

| Service | Binaire | Rôle |
|---|---|---|
| `wlidsvc` | `wlidsvc.dll` | Mint — provisionne le PUID |
| `CDPSvc` | `cdp.dll` | Register — enregistre auprès du DDS |
| `CDPUserSvc` | `cdp.dll` | Variante utilisateur |
| `DoSvc` | `dosvc.dll` | Report — `UCDOStatus.GlobalDeviceId` |
| `DiagTrack` | — | Télémétrie générale |

## 4. Endpoints DDS/CDP

```
dds.microsoft.com
fd.dds.microsoft.com
aad.cs.dds.microsoft.com
cdpcs.access.microsoft.com
```

## 5. Ce qui NE marche pas (démystification)

- `[COURT]` Réinstaller Windows → **nouveau** GDID, mais l'IP et l'historique déjà liés
  restent côté DDS (serveurs Microsoft).
- `[ASSESSED]` **Compte local ≠ protection** : CDP dispose d'un chemin anonyme si aucun
  MSA n'est connecté ; l'appareil est quand même enregistré.
- `[OBSERVED]` Supprimer la clé registre / `%LOCALAPPDATA%\ConnectedDevicesPlatform` →
  le PUID revient au prochain login `wlidsvc` / redémarrage `CDPSvc`.

## 6. Hypothèses à tester sur la VM

- [ ] H1 — Bloquer les endpoints DDS/CDP (pare-feu) empêche l'enregistrement sans casser le login.
- [ ] H2 — `Stop-Service`/désactivation de `CDPSvc`+`DoSvc` stoppe la remontée `GlobalDeviceId`.
- [ ] H3 — Édition (Home/Pro vs Enterprise/LTSC) change ce qui est neutralisable.
- [ ] H4 — Après revert, la valeur `g:<décimal>` est-elle identique (persistance PUID) ?
