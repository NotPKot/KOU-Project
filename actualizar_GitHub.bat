@echo off
setlocal enabledelayedexpansion

if "%1"=="" (
    set /p "msg=Descripcion del cambio: "
) else (
    set "msg=%*"
)

if "!msg!"=="" (
    echo No escribiste nada. Usa: actualizar.bat "mensaje"
    pause
    exit /b 1
)

git add -A
git commit -m "!msg!"
git push

if %errorlevel% equ 0 (
    echo Listo, respaldado en GitHub.
) else (
    echo Algo fallo. Revisa el mensaje de error.
)
pause
