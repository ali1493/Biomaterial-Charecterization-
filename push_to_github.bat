@echo off
REM Pushes this folder to an EMPTY GitHub repo you created at github.com/new (make it Private).
REM Usage: double-click, then paste the repo URL, e.g. https://github.com/<you>/biomat-char-agent.git
REM Needs Git for Windows: https://git-scm.com/download/win

cd /d "%~dp0"
where git >nul 2>nul || (echo Git is not installed. Install it from https://git-scm.com/download/win & pause & exit /b 1)

set /p REPO_URL=Paste the GitHub repo URL:

if not exist ".git" git init -b main
git add .
git commit -m "Characterization pipeline and agent: nano-silica films + thesis hydrogels" 2>nul
git branch -M main
git remote remove origin 2>nul
git remote add origin %REPO_URL%
git push -u origin main

echo.
echo Done. Raw data and reports are excluded by .gitignore.
pause
