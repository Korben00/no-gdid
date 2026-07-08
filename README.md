# no-gdid

> **Statut : privé / travail en cours.** Rien ici n'est encore validé sur une machine
> réelle. Ce dépôt sera ouvert quand l'audit et les mitigations auront été prouvés,
> captures à l'appui, sur une VM Windows 11.

Outils pour **lire, comprendre et réduire l'exposition** du *Global Device Identifier*
(GDID) de Windows — l'identifiant qui a permis au FBI de localiser un suspect
malgré un VPN et des IP dans trois pays (affaire *United States v. Peter Stokes*,
N.D. Ill., juillet 2026).

## Ce qu'est le GDID (en une phrase honnête)

Ce n'est **pas** un hash matériel qu'on efface, c'est un **PUID 64 bits** (Passport
Unique ID) assigné par les **serveurs Microsoft** (`login.live.com`) et enregistré
dans un graphe côté cloud (Device Directory Service). Conséquence directe :

- On ne « supprime » pas un GDID déjà envoyé — il vit sur les serveurs de Microsoft.
- Toute suppression locale est **re-provisionnée** au login suivant.
- Le seul levier client réel : **empêcher la génération et la remontée** (réseau + services).

## La chaîne technique

```
wlidsvc  ── mint ──►  PUID (login.live.com, SOAP)
   │
   ▼  stocké en clair : HKCU\SOFTWARE\Microsoft\IdentityCRL\ExtendedProperties\LID
CDPSvc / CDPUserSvc  ── register ──►  Device Directory Service (dds.microsoft.com)
   │
   ▼
DoSvc  ── report ──►  UCDOStatus.GlobalDeviceId  (Azure Monitor / Update Compliance)
```

Format serveur : `g:<décimal>` (le LID hex converti en entier non signé 64 bits).

## Contenu

| Dossier | Contenu | Statut |
|---|---|---|
| `audit/Get-GDID-Audit.ps1` | Lit *votre* GDID + état de la chaîne. **Lecture seule.** | ✅ écrit, à valider sur VM |
| `mitigate/` | Blocage endpoints, neutralisation services, revert. | ⏳ écrits après validation VM |
| `docs/technical-writeup.md` | Writeup sourcé (chaîne, registre, tags de confiance). | ✅ en cours |

## Avertissement

Outil défensif, orienté **vie privée**. Il n'efface pas le passé et ne rend pas
anonyme. Pour une activité réellement sensible, la seule réponse fiable reste de
ne pas dépendre de Windows (Linux/Tails) et/ou de contrôler tout le trafic sortant.

## Sources

- Reverse engineering primaire : [`SmtimesIWndr/gdid-reversal`](https://github.com/SmtimesIWndr/gdid-reversal)
  (méthodologie taguée `[COURT]` / `[OBSERVED]` / `[STATIC]` / `[ASSESSED]`).
- Plainte fédérale *United States v. Peter Stokes*, N.D. Ill., juillet 2026.
- Couverture : The Register, Tom's Hardware, Proton.

## Licence

À définir (MIT proposé). Voir `LICENSE`.
