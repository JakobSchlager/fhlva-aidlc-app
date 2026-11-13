@echo off
rem =============================================================================
rem run-local.cmd - Run the k6 load driver against the Compose stack (Windows cmd)
rem
rem Usage:
rem   set PROFILE=smoke
rem   load\run-local.cmd [extra k6 run arguments]
rem
rem Windows cmd counterpart of run-local.sh. Runs grafana/k6 in a container
rem attached to the Compose network and targets nginx directly
rem (http://nginx:80). No local k6 installation needed.
rem
rem Environment variables passed through to k6 (all optional):
rem   PROFILE RATE DURATION SPIKE_FACTOR USERS WRITE_RATIO RUN_NAME SLO_FILE
rem   BASE_URL AUTH_URL TRACKING_URL STATISTICS_URL NOTIFICATIONS_URL
rem
rem Script settings:
rem   CONTAINER_ENGINE  podman or docker (default: whichever is installed, podman first)
rem   K6_IMAGE          k6 image (default: docker.io/grafana/k6:2.3.0)
rem   COMPOSE_NETWORK   network to join (default: the network of the nginx container)
rem =============================================================================
setlocal EnableExtensions

if "%~1"=="--help" goto :help
if "%~1"=="-h" goto :help
if "%~1"=="/?" goto :help

set "LOAD_DIR=%~dp0"
if "%LOAD_DIR:~-1%"=="\" set "LOAD_DIR=%LOAD_DIR:~0,-1%"
if not defined K6_IMAGE set "K6_IMAGE=docker.io/grafana/k6:2.3.0"

rem --- Container engine --------------------------------------------------------
set "ENGINE=%CONTAINER_ENGINE%"
if defined ENGINE goto :network
where podman >nul 2>&1 && set "ENGINE=podman"
if defined ENGINE goto :network
where docker >nul 2>&1 && set "ENGINE=docker"
if defined ENGINE goto :network
echo ERROR: neither podman nor docker found 1>&2
exit /b 1

rem --- Compose network ---------------------------------------------------------
rem Both podman-compose and docker compose label containers with the service name.
:network
set "NETWORK=%COMPOSE_NETWORK%"
if defined NETWORK goto :run

set "NGINX="
for /f "usebackq delims=" %%n in (`%ENGINE% ps --filter "label=com.docker.compose.service=nginx" --format "{{.Names}}"`) do (
  if not defined NGINX set "NGINX=%%n"
)
if not defined NGINX (
  echo ERROR: no running nginx container from the Compose stack. 1>&2
  echo        Start the stack first: podman compose up -d ^(or docker compose up -d^) 1>&2
  exit /b 1
)

for /f "usebackq tokens=1" %%w in (`%ENGINE% inspect "%NGINX%" --format "{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}"`) do (
  if not defined NETWORK set "NETWORK=%%w"
)
if not defined NETWORK (
  echo ERROR: could not determine the network of container %NGINX% 1>&2
  exit /b 1
)

:run
if not defined BASE_URL set "BASE_URL=http://nginx:80"

rem "-e NAME" without a value makes the engine copy the variable from this
rem environment into the container, so values need no extra quoting.
rem k6 run exposes container environment variables to the script as __ENV.
set "ENV_ARGS="
for %%v in (PROFILE RATE DURATION SPIKE_FACTOR USERS WRITE_RATIO RUN_NAME SLO_FILE BASE_URL AUTH_URL TRACKING_URL STATISTICS_URL NOTIFICATIONS_URL) do (
  if defined %%v call set "ENV_ARGS=%%ENV_ARGS%% -e %%v"
)

set "SHOW_PROFILE=%PROFILE%"
if not defined SHOW_PROFILE set "SHOW_PROFILE=smoke"
echo k6: profile=%SHOW_PROFILE% target=%BASE_URL% network=%NETWORK% image=%K6_IMAGE%

%ENGINE% run --rm -i --network "%NETWORK%" -v "%LOAD_DIR%:/load:ro" -w /load %ENV_ARGS% "%K6_IMAGE%" run %* /load/script.js
exit /b %ERRORLEVEL%

:help
echo(run-local.cmd - Run the k6 load driver against the Compose stack ^(Windows cmd^)
echo(
echo(Usage:
echo(  set PROFILE=smoke
echo(  load\run-local.cmd [extra k6 run arguments]
echo(
echo(Runs grafana/k6 in a container attached to the Compose network and targets
echo(nginx directly ^(http://nginx:80^). No local k6 installation needed.
echo(
echo(Environment variables passed through to k6 ^(all optional^):
echo(  PROFILE RATE DURATION SPIKE_FACTOR USERS WRITE_RATIO RUN_NAME SLO_FILE
echo(  BASE_URL AUTH_URL TRACKING_URL STATISTICS_URL NOTIFICATIONS_URL
echo(
echo(Script settings:
echo(  CONTAINER_ENGINE  podman or docker ^(default: whichever is installed, podman first^)
echo(  K6_IMAGE          k6 image ^(default: docker.io/grafana/k6:2.3.0^)
echo(  COMPOSE_NETWORK   network to join ^(default: the network of the nginx container^)
exit /b 0
