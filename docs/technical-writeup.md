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

## 7. Résultats VM (baseline 2026-07-08 — Windows 11 Pro, build 26200)

- `[NO-GDID VÉRIFIÉ]` **Lecture du GDID reproduite** : `LID=001800149354BDDD` → `g:6755487812206045`.
  La méthode hex→UInt64 de la source primaire fonctionne à l'identique.
- `[NO-GDID VÉRIFIÉ]` **Namespace `0x0018` confirmé** : notre PUID `0x001800149354BDDD`
  et celui de la plainte Stokes `0x0018000FC8CB93CC` partagent les 16 bits de poids fort
  → tous les device-PUID Windows sont dans la plage `g:67554…`.
- `[NO-GDID VÉRIFIÉ]` **DiagTrack n'est PAS dans le chemin du GDID** : DiagTrack était
  `Stopped`, pourtant le GDID est présent et `wlidsvc`/`CDPSvc`/`CDPUserSvc`/`DoSvc`
  tournaient. → Couper la télémétrie ne neutralise pas le mouchard. (Démonte le conseil courant.)
- `[NO-GDID VÉRIFIÉ]` **Pas de `GlobalDeviceId` en local via Delivery Optimization** :
  `Get-DeliveryOptimizationStatus` ne renvoie que des stats de download. La valeur reportée
  vit côté Azure Monitor (`UCDOStatus`), pas sur le disque. Seule copie locale = le registre.
- `[NO-GDID VÉRIFIÉ]` **Session MSA active** : `wlidsvc` maintient des connexions TLS
  établies vers `20.190.160.131/67:443` (IP d'auth compte Microsoft / AADG). C'est le
  minter du PUID. `CDPSvc`/`DoSvc` sans connexion au repos (enregistrement intermittent).
- `[NO-GDID VÉRIFIÉ]` **Carte des endpoints** :
  - `login.live.com` → `40.126.32.133` (mint MSA, via AADG traffic manager).
  - `aad.cs.dds.microsoft.com` → `150.171.109.82` (Azure Front Door `*.tm-azurefd.net`) —
    **seul front DDS publiquement résolvable**.
  - `dds.microsoft.com`, `fd.dds.microsoft.com`, `cdpcs.access.microsoft.com` → **pas
    d'enregistrement public**, MAIS présents dans le cache DNS avec réponse vide → la pile
    CDP les **interroge** réellement. Noms cibles valides pour un blocage par hostname.
  - `geo.prod.do.dsp.mp.microsoft.com` → `72.154.7.108` (Delivery Optimization).
  - `settings-win.data.microsoft.com` (télémétrie settings, hors chemin GDID).
- `[ASSESSED]` **Le PUID existe côté serveur dès le login MSA.** CDP/DDS/DO = couche de
  corrélation/report, pas la génération. Bloquer CDP/DDS/DO réduit la corrélation mais
  n'efface pas le PUID. Seul « pas de PUID » = pas de MSA.
- `[À CONFIRMER]` `NegativeCache` (HKLM) illisible même en admin → nécessite `SYSTEM`
  (PsExec `-s`).
- `[À TESTER]` H4 — suppression LID + restart `wlidsvc` → valeur identique (ancrage compte)
  ou nouvelle ? Script `experiments/Test-GDID-Regeneration.ps1` (gaté, à lancer après snapshot).
