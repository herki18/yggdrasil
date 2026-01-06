@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0build-ffi.ps1" %*
