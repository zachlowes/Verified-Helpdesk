@echo off
setlocal enabledelayedexpansion

echo.
echo ========================================
echo Verified Helpdesk Deploy
echo ========================================
echo.

IF NOT DEFINED DEPLOYMENT_TARGET (
  SET DEPLOYMENT_TARGET=%~dp0..\artifacts\wwwroot
)

SET WWWROOT=%DEPLOYMENT_TARGET%
SET STAGING=%~dp0..\artifacts\publish

echo %WWWROOT% | findstr /i "\\site\\wwwroot" >nul
IF ERRORLEVEL 1 (
  SET AZURE_DEPLOY=0
  SET PUBLISH_DIR=%WWWROOT%
) ELSE (
  SET AZURE_DEPLOY=1
  SET PUBLISH_DIR=%STAGING%
)

echo Publishing project to %PUBLISH_DIR%...
dotnet publish "%~dp0VerifiedHelpdesk.csproj" ^
  --configuration Release ^
  --output "%PUBLISH_DIR%" ^
  /p:GenerateFullPaths=true

IF !ERRORLEVEL! NEQ 0 goto error

IF !AZURE_DEPLOY! EQU 0 goto done

echo Taking app offline...
echo ^<!DOCTYPE html^>^<html^>^<head^>^<title^>Updating^</title^>^</head^>^<body^>^<p^>Site is updating...^</p^>^</body^>^</html^> > "%WWWROOT%\app_offline.htm"
timeout /t 8 /nobreak >nul

echo Copying build output to wwwroot...
robocopy "%STAGING%" "%WWWROOT%" /E /XO /NFL /NDL /NJH /NJS
SET ROBOCOPY_EXIT=!ERRORLEVEL!
IF !ROBOCOPY_EXIT! GEQ 8 goto error

del "%WWWROOT%\app_offline.htm"

:done
echo Deployment successful.
exit /b 0

:error
echo Deployment failed with error level !ERRORLEVEL!.
exit /b 1
