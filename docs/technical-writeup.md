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
- [x] H4 — VÉRIFIÉ : identique. Voir section 7.

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
- `[NO-GDID VÉRIFIÉ]` **H4 — le GDID est ancré au compte, pas à la machine.**
  Suppression de `LID` + restart `wlidsvc` → reste vide (mint on-demand). Après une
  sollicitation MSA (ouverture du Microsoft Store), la valeur revient **IDENTIQUE**
  (`g:6755487812206045`). → La suppression locale est cosmétique : le PUID est
  re-téléchargé depuis les serveurs Microsoft contre le compte.
- `[NO-GDID VÉRIFIÉ]` **Mitigation blocage (compte MSA conservé)** :
  - **hosts blackhole efficace** : `dds.` / `fd.dds.` / `aad.cs.dds.` / `cdpcs.access.` /
    `geo.prod.do.dsp.mp.microsoft.com` → `0.0.0.0`. `login.live.com` résout toujours
    (`20.190.160.64`), `wlidsvc` reste connecté → **session Microsoft intacte**.
  - `CDPSvc` + `CDPUserSvc` (template `Start=4`) désactivés sans souci.
  - **`DoSvc` protégé côté SCM** : `Set-Service DoSvc -StartupType Disabled` → « Accès
    refusé » même admin. **Contournement : écrire `HKLM\SYSTEM\CurrentControlSet\Services\DoSvc\Start=4`
    directement** → `StartType=Disabled`, puis `Stop-Service DoSvc` OK. (L'ACL de la clé
    registre autorise l'admin là où le SCM le bloque.)
  - Avant désactivation, `DoSvc` gardait ~15 connexions TLS vers `2.22.x` (Akamai / CDN
    Delivery Optimization — probablement du contenu, pas prouvé être le report GDID).
  - **Le GDID reste lisible localement** (`g:6755487812206045`) : non effacé, seulement
    empêché de remonter.
- `[À CONFIRMER]` État « after » propre : `DoSvc` désormais Disabled+Stopped, re-run
  `Get-GDID-Traffic` → plus aucune connexion de la chaîne (capture finale pour l'article).
- `[À TESTER]` Bascule en compte local : le `LID`/GDID disparaît-il ? Un identifiant CDP
  anonyme apparaît-il malgré tout (claim `[ASSESSED]` du chercheur) ?
