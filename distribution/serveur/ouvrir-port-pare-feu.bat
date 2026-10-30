@echo off
rem Autorise le serveur dans le pare-feu Windows (IPv4 et IPv6). A lancer en administrateur.
rem Supprime aussi les regles de blocage que Windows cree si on a ferme ou refuse
rem la fenetre "Autoriser l'acces" au premier lancement (elles passent avant les autorisations).
netsh advfirewall firewall delete rule name=all program="%~dp0Craftclans-Serveur.exe" >nul 2>nul
netsh advfirewall firewall delete rule name=all program="%~dp0Craftclans-Serveur.console.exe" >nul 2>nul
netsh advfirewall firewall delete rule name="Craftclans serveur" >nul 2>nul
netsh advfirewall firewall delete rule name="Craftclans serveur (programme)" >nul 2>nul
netsh advfirewall firewall add rule name="Craftclans serveur" dir=in action=allow protocol=TCP localport=8000 profile=any
if errorlevel 1 goto echec
netsh advfirewall firewall add rule name="Craftclans serveur (programme)" dir=in action=allow program="%~dp0Craftclans-Serveur.exe" profile=any
if errorlevel 1 goto echec
echo Port 8000 ouvert dans le pare-feu (IPv4 et IPv6), blocages supprimes.
pause
exit /b 0
:echec
echo Echec : fais clic droit puis "Executer en tant qu administrateur".
pause
