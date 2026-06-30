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

echo Publishing project...
dotnet publish "%~dp0VerifiedHelpdesk.csproj" ^
  --configuration Release ^
  --output "%DEPLOYMENT_TARGET%" ^
  /p:GenerateFullPaths=true

IF !ERRORLEVEL! NEQ 0 goto error

echo Deployment successful.
exit /b 0

:error
echo Deployment failed with error level !ERRORLEVEL!.
exit /b 1
