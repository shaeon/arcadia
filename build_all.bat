@echo off
rem ---------------------------------------------------------------------------
rem Compila el core Arcadia para todas las placas, cada una con su Quartus.
rem
rem   build_all.bat                 -> las cuatro placas
rem   build_all.bat calypso sidi    -> solo las indicadas
rem
rem Los .rbf y los logs quedan en releases\
rem ---------------------------------------------------------------------------
setlocal

set "Q13=C:\altera_lite\13.1\quartus\bin64\quartus_sh.exe"
set "Q17=C:\altera_lite\17.0\quartus\bin64\quartus_sh.exe"
set "Q25=C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe"

set "ROOT=%~dp0"
set "OUT=%ROOT%releases"
if not exist "%OUT%" mkdir "%OUT%"

set "BOARDS=%*"
if "%BOARDS%"=="" set "BOARDS=mist sidi poseidon calypso"

set "OK="
set "FAIL="

for %%B in (%BOARDS%) do call :build %%B

echo.
echo ===========================================================
if defined OK   echo  Compiladas:%OK%
if defined FAIL echo  CON ERRORES:%FAIL%   (mira releases\arcadia_^<placa^>.log)
echo ===========================================================
if defined FAIL exit /b 1
exit /b 0


:build
set "B=%~1"
set "Q="
rem Cyclone III (MiST) solo esta hasta Quartus 13.1.
rem Cyclone 10 LP (Calypso) necesita Quartus 17.1 o posterior.
if /i "%B%"=="mist"     set "Q=%Q13%"
if /i "%B%"=="sidi"     set "Q=%Q17%"
if /i "%B%"=="poseidon" set "Q=%Q17%"
if /i "%B%"=="calypso"  set "Q=%Q25%"

if not defined Q (
    echo [%B%] placa desconocida, me la salto
    set "FAIL=%FAIL% %B%"
    goto :eof
)
if not exist "%Q%" (
    echo [%B%] no encuentro %Q%
    set "FAIL=%FAIL% %B%"
    goto :eof
)

echo.
echo [%B%] compilando con %Q% ...
pushd "%ROOT%%B%"
"%Q%" --flow compile arcadia_%B% > "%OUT%\arcadia_%B%.log" 2>&1
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" goto :fallo
if not exist "output_files\arcadia_%B%.rbf" goto :fallo

copy /y "output_files\arcadia_%B%.rbf" "%OUT%\arcadia_%B%.rbf" >nul
echo [%B%] OK  -^> releases\arcadia_%B%.rbf
set "OK=%OK% %B%"
popd
goto :eof

:fallo
echo [%B%] ERROR (codigo %RC%), ver releases\arcadia_%B%.log
set "FAIL=%FAIL% %B%"
popd
goto :eof
