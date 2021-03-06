#!/bin/bash
#================================================================
# HEADER
# Licensed to LUOCHUNHUI.COM 
# Control Script for the Service Management
#================================================================
#% SYNOPSIS
#+    ${SCRIPT_NAME} [-hv] [-o[file]] args ...
#%
#%
#% ENVIROMENT
#%   Enviroment Variable Prerequisites
#%   STEVE_CONFIG    Default: "/etc/steve/"
#%                   Configuration directory path to a directory where 
#%                   store the configuration for steve and services.
#%                   Default is "/etc/steve/", and
#%                   the "setenv.sh" inside will be loaded.
#%
#% DESCRIPTION
#%    This is a script template
#%    to start any good shell script.
#%
#% OPTIONS
#%    -o [file], --output=[file]    Set log file (default=/dev/null)
#%                                  use DEFAULT keyword to autoname file
#%                                  The default value is /dev/null.
#%    
#%    -t, --timelog                 Add timestamp to log ("+%y/%m/%d@%H:%M:%S")
#%    -x, --ignorelock              Ignore if lock file exists
#%    -h, --help                    Print this help
#%    -v, --version                 Print script information
#%
#% EXAMPLES
#%    ${SCRIPT_NAME} -s hello -k restart
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} (www.uxora.com) 0.0.4
#-    author          Michel VONGVILAY
#-    copyright       Copyright (c) http://www.uxora.com
#-    license         GNU General Public License
#-    script_id       12345
#-
#================================================================
#  HISTORY
#     2015/03/01 : mvongvilay : Script creation
#     2015/04/01 : mvongvilay : Add long options and improvements
# 
#================================================================
#  DEBUG OPTION
#    set -n  # Uncomment to check your syntax, without execution.
#    set -x  # Uncomment to debug this shell script
#
#================================================================
# END_OF_HEADER
#================================================================


##########    Constants   ##########
STEVE_VERSION="0.9.2"

ERROR_UNKNOWN=1
ERROR_PORT_USED=2
ERROR_PID_EXISTS=3
ERROR_PNAME_EXISTS=4

ERROR_SV_NOTRUNNING=-11
ERROR_SV_NOTEXISTS=-12
ERROR_SV_ISRUNNING=-13
ERROR_SV_STARTFATAL=-14

SERVICE_STATE_NOT_EXIST=21
SERVICE_STATE_NOT_RUNNING=22
SERVICE_STATE_RUNNING=23
SERVICE_STATE_EXITED=24
SERVICE_STATE_FATAL=25
SERVICE_STATE_STOPPING=26
SERVICE_STATE_UNKNOWN=29

##########    Constants END   ##########

##########    Globals   ##########
PID=
PID_STR=
SERVICE_TYPE=
SERVICE_NAME=

RUN_RESULT=
RUN_CODE=
##########    Globals END   ##########

##########    Initialize config, which can be override in steve.conf   ##########
SUPERVISORCTL_BIN="supervisorctl"
UPSTART_BIN="initctl"
LSOF_BIN="lsof"
STEVE_OUT="/var/log/steve.log"
WITH_SUDO=""
VERBOSE=false

[ -z "$STEVE_CONFIG" ] && STEVE_CONFIG="/etc/steve/"

STEVE_ENV="${STEVE_CONFIG}/.setenv.sh"
[ -f $STEVE_ENV ] && source $STEVE_ENV

##########    Initialize config END   ##########



##########    Libraries    ##########

####################    logger    ###################
### This file is copy and modified
### from http://www.cubicrace.com/2016/03/efficient-logging-mechnism-in-shell.html ###
SCRIPT_LOG="${STEVE_OUT}"
cfn="${FUNCNAME[1]}"
script_name=`basename "$0"`
script_name="${script_name%.*}"
date_format="+%Y-%m-%dT%H:%M:%S%z"

SESSIONID=`date +%s | sha256sum | base64 | head -c 32`
function log_time() {
  echo `date "${date_format}"`
}
function join { local IFS="$1"; shift; echo "$*"; }

function SCRIPTENTRY(){
  local msg="$1"
  INFO "$cfn $FUNCNAME $msg"
}

function SCRIPTEXIT(){
  INFO "$cfn $FUNCNAME"
}

function ENTRY(){
  INFO "$cfn $FUNCNAME"
}

function EXIT(){
  INFO "$cfn $FUNCNAME"
}


function INFO(){
  local msg="$1"
  local timeAndDate=`log_time`
  echo "[$timeAndDate] [$SESSIONID] [INFO] [${SERVICE_NAME}] >>> $msg" |tee -a $SCRIPT_LOG
}


function DEBUG(){
  local msg="$1"
  local timeAndDate=`log_time`
  echo "[$timeAndDate] [$SESSIONID] [DEBUG] [${SERVICE_NAME}] >>> $msg" |tee -a $SCRIPT_LOG
}

function ERROR(){
  local msg="$1"
  local timeAndDate=`log_time`
  echo "[$timeAndDate] [$SESSIONID] [ERROR] [${SERVICE_NAME}] >>> $msg" |tee -a $SCRIPT_LOG
}
####################    logger end    ###################

function WARNING(){
  local msg="$1"
  local timeAndDate=`log_time`
  echo "[$timeAndDate] [$SESSIONID] [WARNING] [${SERVICE_NAME}] >>> $msg" |tee -a $SCRIPT_LOG
}

function FATAL(){
  local msg="$1"
  local timeAndDate=`log_time`
  echo "[$timeAndDate] [$SESSIONID] [FATAL] [${SERVICE_NAME}] >>> $msg" |tee -a $SCRIPT_LOG
}

function DIE() {
  FATAL "$1";
  local errcode=$ERROR_UNKNOWN
  if [ ! -z "$2" ]; then
    errcode=$2
  fi
  
  exit $errcode;
}


##########    Libraries End   ##########


##########    Functions   ##########

function usage()
{
  cat <<EOF
Usage:
$0 [h?lvVfk:s:]
OPTIONS:
   -s     Service name
   -k     Action. start, stop, restart, debug
   -l     List steve services
   -h|-?  Show this message
   -V     App Version
   -v     Verbose

Example:
    ./steve.sh [arguments] action
EOF
};

function version()
{
    echo ${STEVE_VERSION};
}

function list_services() {
    ls -1 "$STEVE_CONFIG" | sed -e 's/\.ini$//'
}

#Read the config, formatted with "key=value".
#Anything start with "#" or "[" will be ignored
function readconfig()
{
    local configfile=$1
    shopt -s extglob
    while IFS='=' read lhs rhs
    do
      if [[ "$rhs" != "" ]]; then
        if [[ ! ( "$lhs" = "["* || "$lhs" = "#"* ) ]]; then
            export "$lhs"="$rhs"
        fi
      fi
    done < "$configfile"
}

function check_port() 
{
  PID=
  local port="${1}"
  DEBUG "Checking port: ${port}"
  INFO "CMD: ${WITH_SUDO} ${LSOF_BIN} -Pn -i:${port} -sTCP:LISTEN |grep -v COMMAND |awk '{print \$2}'"

  PID=`${WITH_SUDO} ${LSOF_BIN} -Pn -i:${port} -sTCP:LISTEN |grep -v COMMAND |awk '{print \$2}'`
  PID_STR=$(join , ${PID[@]})
  if [ -z "$PID" ]; then
      INFO "Port ${port} is free"
  else
      INFO "Port ${port} is used"
  fi
}

function check_pid()
{
  PID=
  local pidfile=$1
  
  if [ -f "$pidfile" ]; then
    if [ -s "$pidfile" ]; then
      INFO "Existed PID file found during start."
      if [ -r "$pidfile" ]; then
        PID=`cat "$pidfile"`
        PID_STR=$(join , ${PID[@]})
        ps -p $PID >/dev/null 2>&1
        if [ $? -eq 0 ] ; then
          DEBUG "Server appears to still be running with PID $PID."
          return
        else
          DEBUG "PID file exists, but server is not stopped"
        fi
      else
        DEBUG "Unable to read PID file."
      fi
    else
      DEBUG "A empty PID file."
    fi
  fi
}

function check_pname()
{
  PID=
  local pname=${1}
  PID=`ps aux | grep "${pname}" | grep -v "grep" | grep -v "steve" |awk '{print $2}'`
  PID_STR=$(join , ${PID[@]})

  if [ ! -z "$PID" ]; then
    DEBUG "Process named ${pname} #${PID_STR} exists"
  else
    DEBUG "Process named ${pname} does NOT exists"
  fi
  return
}


function check_sv_service()
{
  if [[ $sv_result == *"supervisor.sock no such file"* ]]; then
      ERROR "supervisord is not running"
      return ${ERROR_SV_NOTRUNNING}
  elif [[ $sv_result == *"no such processg"* ]]; then
      ERROR "supervisor process ${SERVICE_NAME} is not exists"
      return ${ERROR_SV_NOTEXISTS}
  fi

  if [[ $sv_result == *"RUNNING"* ]]; then
      INFO "supervisor process ${SERVICE_NAME} is running"
      return ${SERVICE_STATE_RUNNING}
  elif [[ $sv_result == *"FATAL"* ]]; then
      INFO "NOTICE: The previously supervisor status is FATAL"
      return ${SERVICE_STATE_FATAL}
  elif [[ $sv_result == *"STOPPED"* ]]; then
      INFO "The previously supervisor status is STOPPED"
      return ${SERVICE_STATE_NOT_RUNNING}
  elif [[ $sv_result == *"EXITED"* ]]; then
      INFO "The previously supervisor status is EXITED"
      return ${SERVICE_STATE_EXITED}
  fi

  return ${SERVICE_STATE_UNKNOWN}
}

function check_upstart_service() {
  if [[ $sv_result == *"Unknown job"* ]]; then
      ERROR "servive ${SERVICE_NAME} is not exists"
      return ${ERROR_SV_NOTEXISTS}
  fi

  if [[ $sv_result == *"start/running"* ]]; then
      INFO "servive process ${SERVICE_NAME} is running"
      return ${SERVICE_STATE_RUNNING}
  elif [[ $sv_result == *"stop/waiting"* ]]; then
      INFO "The previously supervisor status is STOPPED"
      return ${SERVICE_STATE_NOT_RUNNING}
  fi

  return ${SERVICE_STATE_UNKNOWN}
}

function service_prepare_check() 
{
  local cmd=
  local cmd_result=
  local chk_result=
  local chk_code=

  if [[ $SERVICE_TYPE == "supervisord" ]]; then
    cmd="${WITH_SUDO} ${SUPERVISORCTL_BIN} status ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    cmd_result=`${cmd}`

    chk_result=`check_sv_service`
    chk_code=$?

    INFO "CMD>: ${check_result}" 
    return $chk_code
  elif [[ $SERVICE_TYPE == "upstart" ]]; then
    cmd="${WITH_SUDO} ${UPSTART_BIN} status ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    cmd_result=`${cmd}`
    chk_result=`check_upstart_service`
    chk_code=$?

    INFO "CMD>: ${check_result}" 
    return $chk_code
  elif [[ $SERVICE_TYPE == "init.d" ]]; then
    cmd="/etc/init.d/${SERVICE_NAME}"
    INFO "CMD: ls ${cmd}"
    if [[ ! -f ${cmd} ]]; then
        ERROR "service does NOT exists" 
        return ${ERROR_SV_NOTEXISTS}
    fi
  elif [[ $SERVICE_TYPE == "systemd" ]]; then
    cmd="/etc/systemd/system/${SERVICE_NAME}.service"
    INFO "CMD: ls ${cmd}"
    if [[ ! -f ${cmd} ]]; then
        ERROR "service does NOT exists" 
        return ${ERROR_SV_NOTEXISTS}
    fi
  fi

  return 0
}

function service_start()
{
  local cmd=
  local cmd_result=

  if [[ $SERVICE_TYPE == "supervisord" ]]; then
    cmd="${WITH_SUDO} ${SUPERVISORCTL_BIN} start ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  elif [[ $SERVICE_TYPE == "upstart" ]]; then
    cmd="${WITH_SUDO} ${UPSTART_BIN} start ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  elif [[ $servicetype == "init.d" ]]; then
    cmd="${WITH_SUDO} /etc/init.d/${SERVICE_NAME} start"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  elif [[ $servicetype == "systemd" ]]; then
    cmd="${WITH_SUDO} systemctl start ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  fi
  INFO "Service start info: $RUN_RESULT"
}

function service_check_supervisor() {
  if [[ $RUN_RESULT == *"already started"* ]]; then
    INFO "OK. Supervisor process ${SERVICE_NAME} is already started"
    return ${SERVICE_STATE_RUNNING}
  elif [[ $RUN_RESULT == *"RUNNING"* ]]; then
      INFO "OK. Supervisor process ${SERVICE_NAME} is running"
      return ${SERVICE_STATE_RUNNING}
  elif [[ $RUN_RESULT == *"started"* ]]; then
    INFO "OK. Supervisor process ${SERVICE_NAME} started"
    return ${SERVICE_STATE_RUNNING}
  elif [[ $RUN_RESULT == *"ERROR"* ]]; then
    INFO "FATAL: The supervisor status is FATAL: ${RUN_RESULT}" 
    return ${SERVICE_STATE_FATAL}
  elif [[ $RUN_RESULT == *"FATAL"* ]]; then
    INFO "FATAL: The supervisor status is FATAL" 
    return ${SERVICE_STATE_FATAL}
  elif [[ $RUN_RESULT == *"STOPPED"* ]]; then
    INFO "FATAL: The supervisor status is STOPPED" 
    return ${SERVICE_STATE_EXITED}
  elif [[ $RUN_RESULT == *"EXITED"* ]]; then
      INFO "FATAL: The supervisor status is EXITED" 
      return ${SERVICE_STATE_EXITED}
  fi
}

function service_check() {
  if [[ $SERVICE_TYPE == "supervisord" ]]; then
    service_check_supervisor
    service_check_code=$?
    return $service_check_code
  elif [[ $servicetype == "init.d" ]]; then
    DEBUG "";
  elif [[ $servicetype == "systemd" ]]; then
    DEBUG "";
  fi

  return 0
}

function service_stop()
{
  local cmd=

  DEBUG "${SERVICE_TYPE} stop"

  if [[ "${SERVICE_TYPE}" == "supervisord" ]]; then
    cmd="${WITH_SUDO} ${SUPERVISORCTL_BIN} stop ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  elif [[ "${SERVICE_TYPE}" == "upstart" ]]; then
    cmd="${WITH_SUDO} ${UPSTART_BIN} stop ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  elif [[ "${servicetype}" == "init.d" ]]; then
    cmd="${WITH_SUDO} service ${SERVICE_NAME} stop"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  elif [[ "${servicetype}" == "systemd" ]]; then
    cmd="${WITH_SUDO} systemctl stop ${SERVICE_NAME}"
    INFO "CMD: ${cmd}"
    RUN_RESULT=`${cmd}`
  fi
  
  DEBUG "Service stop info: $RUN_RESULT"
}


##########    MAIN START   ##########


while getopts "h?vlVk:o:s:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    l)
        list_services
        exit 0
        ;;
    V)  
        version
        exit 0
        ;;
    v)
        VERBOSE=true
        ;;
    s)
        SERVICE_NAME=$OPTARG
        ;;
    k)
        ACTION=$OPTARG
        ;;
    o)  
        output_file=$OPTARG
        ;;
    esac
done

[ -z ${SERVICE_NAME} ] && usage && DIE "Server name must be set" $ERROR_UNKNOWN
[ -z ${output_file} ] && STEVE_OUT=${output_file}

SCRIPTENTRY "$@"

readconfig "${STEVE_CONFIG}${SERVICE_NAME}.ini"


[ ! -z "$service_alias" ] && SERVICE_NAME="${service_alias}"
#[ -z "$servicetype" ] && SERVICE_TYPE="supervisord"
SERVICE_TYPE=${servicetype-supervisord}
retry_time=${retry_time-5}
sleep_time=${sleep_time-5}
forcekill=${forcekill-256}
forcekill9=${forcekill9-256}

if [ "$ACTION" = "debug" ] ; then
  DEBUG "Debug command not available now."
  exit 1
elif [ "$ACTION" = "start" ]; then
    #check port, DIE if port is in use
    if [ ! -z "$use_port" ]; then

      for port in $(echo $use_port | tr ";" "\n"); do
        check_port "$port"
        if [ ! -z "$PID" ]; then
          DIE "PORT ${port} is used by PID: $PID_STR" "${ERROR_PORT_USED}"
        fi
      done
    fi

    if [ ! -z "$check_pid" ]; then
      check_pid "$check_pid"
      if [ ! -z "$PID" ]; then
        DIE "PidFile is used by PID: ${PID_STR}." "${ERROR_PORT_USED}"
      fi
    fi

    if [ ! -z "$use_pname" ]; then
      check_pname "$use_pname"
      if [ ! -z "$PID" ]; then
        DIE "Process name is existed with PID: ${PID_STR}." "${ERROR_PNAME_EXISTS}"
      fi
    fi

    service_prepare_check

    service_check_code=$?
    if(( ${service_check_code} < 0 )); then
      DIE "FATAL" ${service_check_code}
    fi

    INFO "===Starting...==="

    service_start
    
    INFO "Checking after started..."

    NEXT_WAIT_TIME=0
    COMMAND_STATUS=1
    
    until [ $COMMAND_STATUS -eq 0 -o $NEXT_WAIT_TIME -eq $retry_time ]; do
    
      COMMAND_STATUS=0

      DEBUG "Sleeping... ${sleep_time}, Loop ${NEXT_WAIT_TIME}"
      sleep "$sleep_time"

      service_check
      service_check_code=$?
      if(( ${service_check_code} < 0 )); then
        die "FATAL" ${service_check_code}
      fi

      if [ ! -z "$use_port" ]; then
        for port in $(echo $use_port | tr ";" "\n"); do
          check_port "$port"
          if [ -z "$PID" ]; then
            WARNING "check port ${port} failed."
            COMMAND_STATUS=1
          else
            INFO "Port ${port} started"
          fi
        done
      fi

      if [ ! -z "$check_pid" ]; then
        check_pid "$check_pid"
        if [ -z "$PID" ]; then
            WARNING "check pid failed."
            COMMAND_STATUS=1
        else
          INFO "Pid #${PID_STR} is running"
        fi
      fi

      if [ ! -z "$use_pname" ]; then
        check_pname "$use_pname"
        if [ -z "$PID" ]; then
            WARNING "check process name failed, no named '${use_pname}' running."
            COMMAND_STATUS=1
        else
          INFO "Process name ${use_pname} #${PID_STR} is running"
        fi
      fi

      let NEXT_WAIT_TIME=NEXT_WAIT_TIME+1
    done

    if [ $COMMAND_STATUS -eq 0 ]; then
      INFO "===== OK. service '${SERVICE_NAME}' started. ====="
    else
      DIE "===== FATAL. started checked failed. Login to the server and check =====" ${ERROR_SV_NOTRUNNING}
    fi

elif [ "$ACTION" = "stop" ]; then
    if [ ! -z "$use_port" ]; then
      INFO "Checking port ${use_port}..."
      for port in $(echo $use_port | tr ";" "\n"); do
        check_port "$port"
        if [ ! -z "$PID" ]; then
          INFO "Checked: Port ${port} #{$PID_STR} is running."
        fi
      done
    fi

    if [ ! -z "$check_pid" ]; then
      INFO "Checking pid"
      check_pid "$check_pid"
      if [ ! -z "$PID" ]; then
          INFO "check pid: pid ${use_pid} is running."
      fi
    fi

    if [ ! -z "$use_pname" ]; then
      INFO "Checking pname..."
      check_pname "$use_pname"
      if [ ! -z "$PID" ]; then
        INFO "Checked process: ${use_pname} is running."
      fi
    fi

    INFO "Checking service..."
    service_prepare_check

    INFO "===Stoping...==="
    sv_result=`service_stop`
    service_stop_code=$?

    if(( ${service_stop_code} <  0 )); then
      DIE "FATAL" ${service_stop_code}
    fi


    INFO "Checking after stop..."

    NEXT_WAIT_TIME=0
    COMMAND_STATUS=1
    
    until [ $COMMAND_STATUS -eq 0 -o $NEXT_WAIT_TIME -eq $retry_time ]; do
      COMMAND_STATUS=0

      INFO "Sleeping... ${sleep_time}, Loop ${NEXT_WAIT_TIME}"
      [ ${NEXT_WAIT_TIME} -eq 0 ] && sleep 2  #stop may be soon, only sleep 2 seconds when the first time
      [ ! ${NEXT_WAIT_TIME} -eq 0 ] && sleep "$sleep_time"

      service_check
      service_stop_code=$?

      if [[ ${service_stop_code} == ${SERVICE_STATE_NOT_RUNNING} ]]; then
        WARNING "${SERVICE_NAME} is not running."
      elif [[ ${service_stop_code} == ${SERVICE_STATE_RUNNING} ]]; then
        WARNING "Service process ${service_stop_code} is still running."
        COMMAND_STATUS=1
      elif [[ ${service_stop_code} == ${SERVICE_STATE_STOPPING} ]]; then
        WARNING "Service process ${service_stop_code} is still running."
      elif [[ ${service_stop_code} == ${SERVICE_STATE_FATAL} ]]; then
        WARNING "The service status is FATAL"
      elif [[ ${service_stop_code} == ${SERVICE_STATE_EXITED} ]]; then
        INFO "OK: The service status is STOPPED|EXITED"
      fi

      if [ ! -z "$use_port" ]; then
        for port in $(echo $use_port | tr ";" "\n"); do
          check_port "$port"
          if [ ! -z "$PID" ]; then
              WARNING "Check port $port is still running with PID #${PID_STR}"
              COMMAND_STATUS=1

              if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
                WARNING "Use Kill TERM to stop the process #{$PID_STR} who is using port $port"
                ${WITH_SUDO} kill -TERM $PID
              fi

              if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
                WARNING "Use Kill 9 to stop the process #${PID_STR} who is using port $port"
                ${WITH_SUDO} kill -KILL $PID
              fi
          else
            INFO "Check port $port success, it is free."
          fi
        done
      fi

      if [ ! -z "$check_pid" ]; then
        check_pid "$check_pid"
        if [ ! -z "$PID" ]; then
         WARNING "check pid #${PID} is still running."
         COMMAND_STATUS=1

         if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
            WARNING "Use Kill -TERM to stop the process #${PID_STR}"
            ${WITH_SUDO} kill -TERM $PID
          fi

          if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
            WARNING "Use Kill -KILL to stop the process #${PID_STR}"
            ${WITH_SUDO} kill -KILL $PID
          fi
        else
          DEBUG "Check PID $check_pid success."
        fi
      fi

      if [ ! -z "$use_pname" ]; then
        check_pname "$use_pname"
        if [ ! -z "$PID" ]; then
          WARNING "Check process name ${use_pname} ${PID_STR} is still running."
          COMMAND_STATUS=1

          if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
            WARNING "Use Kill TERM to stop the process $PID_STR named ${use_pname}"
            ${WITH_SUDO} kill -TERM $PID
          fi

          if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
            WARNING "Use Kill 9 to stop the process $PID_STR named ${use_pname}"
            ${WITH_SUDO} kill -KILL $PID
          fi
        else
          DEBUG "Check process name ${use_pname} success."
        fi
      fi
      let NEXT_WAIT_TIME=NEXT_WAIT_TIME+1
    done

    if [ $COMMAND_STATUS -eq 0 ]; then
      INFO "=== The '${SERVICE_NAME}' has been stopped. ==="
    else
      DIE "===== FATAL. ${SERVICE_NAME} is not stopped cleanly. Login to the server and check =====" ${ERROR_SV_ISRUNNING}
    fi
elif [ "$ACTION" = "restart" ]; then
    cmd="${0} ${@}"
    stop_command=${cmd/\-k restart/\-k stop}
    start_command=${cmd/\-k restart/\-k start}

    INFO "=== Step1 Stoping...==="
    set +e; $stop_command; set -e

    INFO "=== Step2 Then Starting...==="
    $start_command
else
  DIE "Unknow Action $ACTION" $ERROR_UNKNOWN
fi



