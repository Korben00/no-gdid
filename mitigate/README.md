# mitigate/ — vide volontairement

Les scripts de mitigation ne sont **pas** écrits tant que leur effet n'a pas été
mesuré sur une VM Windows 11 réelle. Publier un `Stop-Service wlidsvc` sans preuve
qu'il change réellement la valeur remontée serait un faux tuto.

À figer ici une fois validés (cf. `docs/technical-writeup.md`, section 6) :

- `Block-GDID-Endpoints.ps1` — règles pare-feu sortantes vers DDS/CDP (mitigation n°1 pressentie).
- `Disable-GDID-Services.ps1` — neutralisation `wlidsvc`/`CDPSvc`/`CDPUserSvc`/`DoSvc`/`DiagTrack` (+ effets de bord documentés).
- `Revert-GDID.ps1` — restauration complète de l'état d'origine.
