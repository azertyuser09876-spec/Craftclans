@echo off
rem ============================================================================
rem  Publier une nouvelle version de Craftclans
rem
rem  Utilisation :  publier.bat mineure "Ajout des rôles"
rem                 publier.bat patch "Correction du chat"
rem                 publier.bat            (le script pose les questions)
rem
rem  1. vérifie la branche main et récupère les dernières modifications
rem  2. augmente la version (VERSION, project.godot, export_presets.cfg)
rem  3. exporte le jeu et le serveur Windows avec Godot pour vérifier que tout compile
rem  4. git add, commit, tag, push
rem  GitHub construit ensuite tout seul le .exe, le .apk et le serveur, et crée la release.
rem
rem  Godot est cherché dans : la variable GODOT, le fichier outils\godot_chemin.txt
rem  (une ligne avec le chemin complet de Godot_v4.4.1-stable_win64_console.exe), puis le PATH.
rem ============================================================================
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "TYPE=%~1"
set "MESSAGE=%~2"
if "%TYPE%"=="" set /p "TYPE=Type de version (patch, mineure ou majeure) : "
if /i not "%TYPE%"=="patch" if /i not "%TYPE%"=="mineure" if /i not "%TYPE%"=="majeure" (
    echo Type inconnu : "%TYPE%". Choisis patch, mineure ou majeure.
    goto erreur
)
if "%MESSAGE%"=="" set /p "MESSAGE=Description de la version : "
if "%MESSAGE%"=="" set "MESSAGE=Nouvelle version"

where git >nul 2>nul || (echo git est introuvable. Installe Git pour Windows. & goto erreur)

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set "BRANCHE=%%b"
if not "%BRANCHE%"=="main" (
    echo Tu es sur la branche "%BRANCHE%". Passe sur main avant de publier : git checkout main
    goto erreur
)

echo.
echo == Récupération des dernières modifications
git pull --rebase --autostash origin main || (echo Le pull a échoué : règle le conflit puis relance. & goto erreur)

for /f "delims=" %%v in ('powershell -NoProfile -ExecutionPolicy Bypass -File outils\version.ps1 -Type %TYPE% -Simuler') do set "VERSION=%%v"
if "%VERSION%"=="" (echo Impossible de calculer la version. & goto erreur)
echo.
echo Nouvelle version : v%VERSION%  ^(%MESSAGE%^)
choice /c ON /m "Publier cette version ? O = oui, N = non"
if errorlevel 2 goto annule

powershell -NoProfile -ExecutionPolicy Bypass -File outils\version.ps1 -Type %TYPE% >nul || goto erreur

echo.
echo == Vérification : export local avec Godot
call :trouver_godot
if not defined GODOT (
    echo Godot est introuvable : la vérification locale est sautée.
    echo Indique son chemin dans outils\godot_chemin.txt pour l'activer.
    choice /c ON /m "Continuer quand même ? GitHub vérifiera de son côté"
    if errorlevel 2 goto annuler_version
    goto envoyer
)
if exist build\verification rmdir /s /q build\verification
mkdir build\verification\serveur
"%GODOT%" --headless --export-release "Windows" build\verification\Craftclans.exe
if errorlevel 1 goto echec_export
if not exist build\verification\Craftclans.exe goto echec_export
"%GODOT%" --headless --export-release "Serveur Windows" build\verification\serveur\Craftclans-Serveur.exe
if errorlevel 1 goto echec_export
if not exist build\verification\serveur\Craftclans-Serveur.exe goto echec_export
echo Export réussi.

:envoyer
echo.
echo == Envoi sur GitHub
git add -A || goto erreur
git commit -m "v%VERSION% : %MESSAGE%" || goto erreur
git tag -a "v%VERSION%" -m "%MESSAGE%" || goto erreur
git push origin main || goto erreur
git push origin "v%VERSION%" || goto erreur
echo.
echo Version v%VERSION% envoyée.
echo GitHub construit maintenant le .exe, le .apk et le serveur (environ 10 minutes).
for /f "delims=" %%u in ('git remote get-url origin') do set "DEPOT=%%u"
set "DEPOT=!DEPOT:.git=!"
echo Suivi : !DEPOT!/actions
echo Release : !DEPOT!/releases/tag/v%VERSION%
goto fin

:echec_export
echo.
echo L'export Godot a échoué : rien n'a été envoyé.
echo Vérifie que les modèles d'export Godot 4.4.1 sont installés (Éditeur ^> Gérer les modèles d'export).
:annuler_version
git checkout -- VERSION project.godot export_presets.cfg
echo Version remise comme avant.
goto erreur

:trouver_godot
if defined GODOT if exist "%GODOT%" exit /b 0
set "GODOT="
if exist outils\godot_chemin.txt (
    set /p GODOT=<outils\godot_chemin.txt
    if exist "!GODOT!" exit /b 0
    set "GODOT="
)
for %%n in (godot.exe godot4.exe Godot_v4.4.1-stable_win64_console.exe Godot_v4.4.1-stable_win64.exe) do (
    if not defined GODOT for /f "delims=" %%p in ('where %%n 2^>nul') do if not defined GODOT set "GODOT=%%p"
)
exit /b 0

:annule
echo Publication annulée, rien n'a changé.
goto fin

:erreur
echo.
echo Publication arrêtée.
pause
exit /b 1

:fin
pause
exit /b 0
