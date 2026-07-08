# mitigate/

Scripts de mitigation **validés sur VM** (Windows 11 Pro 26200, 2026-07-08). Chacun
tourne en **preview par défaut** ; il faut passer `-Apply` pour agir. Tous à lancer
en **admin**.

Ce que ça fait, et surtout ce que ça NE fait PAS :

- Ça **tarit la remontée** du GDID (register/report) et coupe l'accès au graphe
  Device Directory Service — **sans casser la connexion au compte Microsoft**.
- Ça **n'efface pas** le GDID : il reste lisible en local (cache) et il **existe déjà
  côté serveur Microsoft** (minté au login MSA). Aucun script local ne récupère le passé.

| Script | Effet |
|---|---|
| `Block-GDID-Endpoints.ps1 [-Apply]` | Blackhole les 5 endpoints DDS/DO dans `hosts` (→ `0.0.0.0`). Laisse `login.live.com`. |
| `Disable-GDID-Services.ps1 [-Apply]` | Désactive `CDPSvc` (SCM) + `DoSvc`/`CDPUserSvc` (registre `Start=4`, car le SCM refuse `DoSvc`). Laisse `wlidsvc`. |
| `Revert-GDID.ps1` | Restaure services + nettoie `hosts`. |

Effets de bord assumés : Delivery Optimization P2P, Phone Link / "Continuer sur PC",
partage de proximité cessent de fonctionner.

Pour ne rien laisser au hasard : la vraie protection vie privée reste **ne pas dépendre
de Windows** pour l'activité sensible. Ces scripts réduisent l'exposition, ils ne
rendent pas anonyme.
