@echo off
rem Autorise le port 8000 (TCP) dans le pare-feu Windows. A lancer en administrateur.
netsh advfirewall firewall delete rule name="Craftclans serveur" >nul 2>nul
netsh advfirewall firewall add rule name="Craftclans serveur" dir=in action=allow protocol=TCP localport=8000
if errorlevel 1 (echo Echec : fais clic droit puis "Executer en tant qu administrateur".) else (echo Port 8000 ouvert dans le pare-feu.)
pause
