#!/bin/bash
JAVA_OPTS=""
STEVE_VERSION="0.1"


NEXT_WAIT_TIME=0
COMMAND_STATUS=1


# Licensed to JFPAL.COM 
# -----------------------------------------------------------------------------
# Control Script for the JF Servers
#
# Environment Variable Prerequisites
#
#   Do not set the variables in this script. Instead put them into a script
#   setenv.sh in STEVE_BASE/bin to keep your customizations separate.
#
#   STEVE_HOME      May point at your STEVE "build" directory.
#
#   STEVE_BASE      (Optional) Base directory for resolving dynamic portions
#                   of a Catalina installation.  If not present, resolves to
#                   the same directory that STEVE_HOME points to.
#
#   STEVE_CONFIG    (Optional) Configuration directory path to a file where 
#                   store the options for server name. 
#                   Default is $STEVE_BASE/config/, and 
#                   the ${SERVER_NAME}.conf inside will be loaded.
#
#   WITH_SUDO       (Optional) Set it to sudo if you need.
#
#   STEVE_OUT       (Optional) Full path to a file where stdout and stderr
#                   will be redirected.
#                   Default is $STEVE_BASE/logs/catalina.out
#
#   STEVE_OPTS      (Optional) Java runtime options used when the "start",
#                   "run" or "debug" command is executed.
#                   Include here and not in JAVA_OPTS all options, that should
#                   only be used by Tomcat itself, not by the stop process,
#                   the version command etc.
#                   Examples are heap size, GC logging, JMX ports etc.
#
#   STEVE_TMPDIR   (Optional) Directory path location of temporary directory
#                   the JVM should use (java.io.tmpdir).  Defaults to
#                   $STEVE_BASE/temp.
#
#   JAVA_HOME       Must point at your Java Development Kit installation.
#                   Required to run the with the "debug" argument.
#
#   JRE_HOME        Must point at your Java Runtime installation.
#                   Defaults to JAVA_HOME if empty. If JRE_HOME and JAVA_HOME
#                   are both set, JRE_HOME is used.
#   LSOF_BIN        lsof bin
# -----------------------------------------------------------------------------

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

supervisorctl="supervisorctl"
[ -f steve_profile ] && source steve_profile




# OS specific support.  $var _must_ be set to either true or false.
cygwin=false
darwin=false
os400=false
case "`uname`" in
CYGWIN*) cygwin=true;;
Darwin*) darwin=true;;
OS400*) os400=true;;
esac

# resolve links - $0 may be a softlink
PRG="$0"

while [ -h "$PRG" ]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done
# Get standard environment variables
PRGDIR=`dirname "$PRG"`

# Only set CATALINA_HOME if not already set
[ -z "$STEVE_CONFIG" ] && STEVE_CONFIG="/etc/steve/"

echo "STEVE_HOME", ${STEVE_HOME}

# Copy STEVE_BASE from CATALINA_HOME if not already set
[ -z "$STEVE_BASE" ] && STEVE_BASE="$STEVE_HOME"

[ -z "$STEVE_CONFIG" ] && STEVE_CONFIG="/etc/steve/"

[ -z "$STEVE_OUT" ] && STEVE_OUT="$STEVE_BASE"/logs/steve.out

[ -z "$STEVE_TMPDIR" ] && STEVE_TMPDIR="$STEVE_BASE"/temp

[ -z "$WITH_SUDO" ] && WITH_SUDO=""

[ -z "$LSOF_BIN"] && LSOF_BIN="lsof"

usage()
{
  cat <<EOF
Usage:
$0 [h?vVfk:s:]
OPTIONS:
   -s     Service name
   -k     Action. start, stop, restart, debug
   -h|-?  Show this message
   -V     App Version
   -v     Verbose
   -f     Force run

Example:
    ./steve.sh [arguments] action
EOF
};
version()
{
    echo ${STEVE_VERSION};
}

readconfig()
{
    configfile=$1
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
  port="${1}"
  debug "${WITH_SUDO} ${LSOF_BIN} -Pn -i:${port} -sTCP:LISTEN |grep -v COMMAND |awk '{print \$2}'"

  PID=`${WITH_SUDO} ${LSOF_BIN} -Pn -i:${port} -sTCP:LISTEN |grep -v COMMAND |awk '{print \$2}'`

  if [ -z $TMPPID ]; then
      debug "Port ${port} is free"
  else
      debug "Port ${port} #{$TMPPID} is used"
  fi
}

check_pid()
{
  PID=
  pidfile=$1
  
  if [ -f "$pidfile" ]; then
    if [ -s "$pidfile" ]; then
      echo "Existing PID file found during start."
      if [ -r "$pidfile" ]; then
        PID=`cat "$pidfile"`
        ps -p $PID >/dev/null 2>&1
        if [ $? -eq 0 ] ; then
          echo "Server appears to still be running with PID $PID."
          return
        else
          echo "PID exists, but server is not stopped"
        fi
      else
        echo "Unable to read PID file."
      fi
    else
      echo "A empty PID file."
    fi
  fi
}

check_pname()
{
  PID=
  pname=${1}
  PID=`ps aux | grep "${pname}" | grep -v "grep" |awk '{print $2}'`

  if [ ! -z "$PID" ]; then
      debug "Process named ${pname} #{$PID} exists"
  else
      debug "Process named ${pname} does NOT exists"
  fi
  return
}

function die() {
  echo "FATAL. $1";
  errcode=1
  if [ ! -z "$2" ]; then
    errcode=$2
  fi

  exit $errcode;
}

function info()    { echo "INFO.   " "$1"; }
function warning() { echo "WARNING." "$1"; }
function success() { echo "SUCCESS." "$1"; }
function debug()   { echo "DEBUG.  " "$1"; }
function fatal()   { echo "FATAL.  " "$1"; }
function cmd()     { echo "CMD.    " "$1"; }

function check_sv_service()
{
    if [[ $sv_result == *"supervisor.sock no such file"* ]]; then
        fatal "supervisord is not running"
        return ${ERROR_SV_NOTRUNNING}
    elif [[ $sv_result == *"no such processg"* ]]; then
        fatal "supervisor process ${supervisor_name} is not exists"
        return ${ERROR_SV_NOTEXISTS}
    fi

    if [[ $sv_result == *"RUNNING"* ]]; then
        #if [ $force -eq 0 ]; then
        info "supervisor process ${supervisor_name} is running" ${ERROR_SV_ISRUNNING}
        #fi
    elif [[ $sv_result == *"FATAL"* ]]; then
        info "NOTICE: The previously status is FATAL"
    elif [[ $sv_result == *"STOPPED"* ]]; then
        info "The previously status is STOPPED"
    elif [[ $sv_result == *"EXITED"* ]]; then
        info "The previously status is EXITED"
    fi

    #"STARTING" "STOPPING"
    if [[ $sv_result == *"RUNNING"* ]]; then
        info "supervisor process ${supervisor_name} is running"
    elif [[ $sv_result == *"FATAL"* ]]; then
        info "NOTICE: The previously supervisor status is FATAL"
    elif [[ $sv_result == *"STOPPED"* ]]; then
        info "The previously supervisor status is STOPPED"
    elif [[ $sv_result == *"EXITED"* ]]; then
        info "The previously supervisor status is EXITED"
    fi

    return 0
}

function service_prepare_check() 
{
  if [[ $servicetype == "supervisord" ]]; then
    sv_command="${WITH_SUDO} ${supervisorctl} status ${servicename}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`

    check_result=`check_sv_service`
    check_result_code=$?

    echo "${check_retulr}" 
    return $check_result_code
  elif [[ $servicetype == "init.d" ]]; then
    sv_command="/etc/init.d/${servicename}"
    if [[ ! -f ${sv_command} ]]; then
        fatal "service does NOT exists" 
        return ${ERROR_SV_NOTEXISTS}
    fi
  elif [[ $servicetype == "systemd" ]]; then
    sv_command="/etc/systemd/system/${servicename}.service"
    if [[ ! -f ${sv_command} ]]; then
        fatal "service does NOT exists" 
        return ${ERROR_SV_NOTEXISTS}
    fi
  fi
  debug "${sv_command}"
  debug "${sv_result}"

  return 0
}

function service_start()
{
  echo "servicetype=${servicetype}"
  if [[ $servicetype == "supervisord" ]]; then
    sv_command="${WITH_SUDO} ${supervisorctl} start ${servicename}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`
  elif [[ $servicetype == "init.d" ]]; then
    sv_command="${WITH_SUDO} /etc/init.d/${servicename} start"
    cmd "${sv_command}"
    sv_result=`${sv_command}`
  elif [[ $servicetype == "systemd" ]]; then
    sv_command="${WITH_SUDO} systemctl start ${servicename}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`
  fi
  info "${sv_command}"
  info "Service start info: $sv_result"
}

function service_check() {
  if [[ $sv_result == *"already started"* ]]; then
    debug "OK. Supervisor process ${servicename} is already started"
    return ${SERVICE_STATE_RUNNING}
  elif [[ $sv_result == *"started"* ]]; then
    debug "OK. Supervisor process ${servicename} started"
    return ${SERVICE_STATE_RUNNING}
  elif [[ $sv_result == *"ERROR"* ]]; then
    debug "FATAL: The supervisor status is FATAL: ${sv_result}" 
    return ${SERVICE_STATE_FATAL}
  fi

  if [[ $sv_result == *"RUNNING"* ]]; then
      debug "OK. Supervisor process ${servicename} is running"
      return ${SERVICE_STATE_RUNNING}
  elif [[ $sv_result == *"FATAL"* ]]; then
      debug "FATAL: The supervisor status is FATAL" 
      return ${SERVICE_STATE_FATAL}
  elif [[ $sv_result == *"STOPPED"* ]]; then
      debug "FATAL: The supervisor status is STOPPED" 
      return ${SERVICE_STATE_EXITED}
  elif [[ $sv_result == *"EXITED"* ]]; then
      debug "FATAL: The supervisor status is EXITED" 
      return ${SERVICE_STATE_EXITED}
  fi
  return 0
}

function service_stop()
{
  if [[ "${servicetype}" == "supervisord" ]]; then
    sv_command="${WITH_SUDO} ${supervisorctl} stop ${supervisor_name}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`

    info "Supervisorctl return: $sv_result"
  elif [[ "${servicetype}" == "init.d" ]]; then
    sv_command="${WITH_SUDO} /etc/init.d/${servicename} stop"
    cmd "${sv_command}"
    sv_result=`${sv_command}`
  elif [[ "${servicetype}" == "systemd" ]]; then
    sv_command="${WITH_SUDO} systemctl stop ${servicename}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`
  fi
  info "${servicetype}, ${sv_command}"
  info "Service stop info: $sv_result"
}


##main start###

verbose=false
force=0
while getopts "h?vVfk:t:s:" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    V)  
        version
        exit 0
        ;;
    v)
        verbose=true
        ;;
    s)
        servicename=$OPTARG
        ;;
    k)
        action=$OPTARG
        ;;
    f)
        force=1
        ;;
    t)  
        output_file=$OPTARG
        ;;
    esac
done

[ -z ${servicename} ] && usage && die "Server name must be set" $ERROR_UNKNOWN


readconfig "$STEVE_CONFIG""$servicename".ini

echo "servicetype=${servicetype}"

[ ! -z "$service_alias" ] && servicename="${service_alias}"
[ -z "$retry_time" ] && retry_time=5
[ -z "$sleep_time" ] && sleep_time=5
[ -z "$forcekill"  ] && forcekill=256
[ -z "$forcekill9" ] && forcekill9=256
[ -z "$servicetype" ] && servicetype="supervisord"

if [ "$action" = "debug" ] ; then
  echo "Debug command not available now."
  exit 1
elif [ "$action" = "start" ]; then
    #check port, DIE if port is in use
    if [ ! -z "$use_port" ]; then
      for port in $(echo $use_port | tr ";" "\n"); do
        check_port "$port"
        if [ ! -z "$PID" ]; then
          debug "PID ""$PID"
          if [ $force -eq 0 ]; then
            die "check port ${port} #{$PID} failed. The port is in used." "${ERROR_PORT_USED}"
          fi
        fi
      done
    fi

    if [ ! -z "$check_pid" ]; then
      check_pid "$check_pid"
      if [ ! $PID -eq 0 ]; then
        if [ $force -eq 0 ]; then
          die "check pid failed." "${ERROR_PID_EXISTS}"
        fi
      fi
    fi

    if [ ! -z "$use_pname" ]; then
      check_pname "$use_pname"
      if [ ! -z "$PID" ]; then
        if [ $force -eq 0 ]; then
          die "Check process name failed." "${ERROR_PNAME_EXISTS}"
        fi
      fi
    fi

    service_prepare_check

    service_check_code=$?
    if(( ${service_check_code} < 0 )); then
      die "FATAL" ${service_check_code}
    fi

    debug "===Starting...==="

    service_start
    
    debug "Checking after started..."

    NEXT_WAIT_TIME=0
    COMMAND_STATUS=1
    
    until [ $COMMAND_STATUS -eq 0 -o $NEXT_WAIT_TIME -eq $retry_time ]; do
    
      COMMAND_STATUS=0

      debug "Sleeping... ${sleep_time}, Loop ${NEXT_WAIT_TIME}"
      sleep $sleep_time

      service_check
      service_check_code=$?
      if(( ${service_check_code} < 0 )); then
        die "FATAL" ${service_check_code}
      fi

      if [ ! -z "$use_port" ]; then
        for port in $(echo $use_port | tr ";" "\n"); do
          check_port "$port"
          if [ -z "$PID" ]; then
            warning "check port ${port} failed."
            COMMAND_STATUS=1
          else
            success "Port ${port} started"
          fi
        done
      fi

      if [ ! -z "$check_pid" ]; then
        check_pid "$check_pid"
        if [ -z "$PID" ]; then
            warning "check pid failed."
            COMMAND_STATUS=1
        else
          success "Pid #${PID} is running"
        fi
      fi

      if [ ! -z "$use_pname" ]; then
        check_pname "$use_pname"
        if [ -z "$PID" ]; then
            warning "check process name failed, no named '${use_pname}' running."
            COMMAND_STATUS=1
        else
          success "process name ${use_pname} #${PID} is running"
        fi
      fi

      let NEXT_WAIT_TIME=NEXT_WAIT_TIME+1
    done

    if [ $COMMAND_STATUS -eq 0 ]; then
      success "===== OK. service '${servicename}' started. ====="
    else
      die "===== FATAL. started checked failed. Login to the server and check ====="
    fi

elif [ "$action" = "stop" ]; then
    if [ ! -z "$use_port" ]; then
      debug "Checking port ${use_port}..."
      for port in $(echo $use_port | tr ";" "\n"); do
        check_port "$port"
        if [ ! -z "$PID" ]; then
          success "Checked: Port ${port} #{$PID} is running."
        fi
      done
    fi

    if [ ! -z "$check_pid" ]; then
      debug "Checking pid"
      check_pid "$check_pid"
      if [ ! -z "$PID" ]; then
          info "check pid: pid ${use_pid} is running."
      fi
    fi

    if [ ! -z "$use_pname" ]; then
      debug "Checking pname..."
      check_pname "$use_pname"
      if [ ! -z "$PID" ]; then
        info "Checked process: ${use_pname} is running."
      fi
    fi

    debug "Checking service..."
    service_prepare_check

    debug "===Stoping...==="
    sv_result=`service_stop`
    service_stop_code=$?

    echo "${sv_result}"
    if(( ${service_stop_code} <  0 )); then
      die "FATAL" ${service_stop}
    fi

    #info "$sv_result"

    debug "Checking after stop..."

    NEXT_WAIT_TIME=0
    COMMAND_STATUS=1
    
    until [ $COMMAND_STATUS -eq 0 -o $NEXT_WAIT_TIME -eq $retry_time ]; do
      COMMAND_STATUS=0

      debug "Sleeping... ${sleep_time}, Loop ${NEXT_WAIT_TIME}"
      [ ${NEXT_WAIT_TIME} -eq 0 ] && sleep 2  #stop may be soon, only sleep 2 seconds when the first time
      [ ! ${NEXT_WAIT_TIME} -eq 0 ] && sleep $sleep_time

      service_check
      service_stop_code=$?

      if [[ ${service_stop_code} == ${SERVICE_STATE_NOT_RUNNING} ]]; then
        warning "${servicename} is not running."
      elif [[ ${service_stop_code} == ${SERVICE_STATE_RUNNING} ]]; then
        warning "Supervisor process ${servicename} is still running."
        COMMAND_STATUS=1
      elif [[ ${service_stop_code} == ${SERVICE_STATE_STOPPING} ]]; then
        warning "Supervisor process ${servicename} is still running."
      elif [[ ${service_stop_code} == ${SERVICE_STATE_FATAL} ]]; then
        warning "The supervisor status is FATAL"
      elif [[ ${service_stop_code} == ${SERVICE_STATE_EXITED} ]]; then
        success "OK: The supervisor status is STOPPED|EXITED"
      fi

      if [ ! -z "$use_port" ]; then
        for port in $(echo $use_port | tr ";" "\n"); do
          check_port "$port"
          if [ ! -z "$PID" ]; then
              warning "Check port $port #${PID} is still running."
              COMMAND_STATUS=1

              if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
                warning "Use Kill TERM to stop the process #{$PID} on port $port"
                kill -TERM $PID
              fi

              if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
                warning "Use Kill 9 to stop the process #${PID} on port $port"
                kill -KILL $$PID
              fi
          else
            success "Check port $port success."
          fi
        done
      fi

      if [ ! -z "$check_pid" ]; then
        check_pid "$check_pid"
        if [ ! -z "$PID" ]; then
         warning "check pid #${PID} is still running."
         COMMAND_STATUS=1

         if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
            warning "Use Kill TERM to stop the process $PID"
            kill -TERM $PID
          fi

          if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
            warning "Use Kill 9 to stop the process $PID"
            kill -KILL $PID
          fi
        else
          success "Check PID $check_pid success."
        fi
      fi

      if [ ! -z "$use_pname" ]; then
        check_pname "$use_pname"
        if [ ! -z "$PID" ]; then
          warning "Check process name ${use_pname} ${PID} is still running."
          COMMAND_STATUS=1

          if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
            warning "Use Kill TERM to stop the process $PID named ${use_pname}"
            kill -TERM $PID
          fi

          if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
            warning "Use Kill 9 to stop the process $PID named ${use_pname}"
            kill -KILL $PID
          fi
        else
          success "Check process name ${use_pname} success."
        fi
      fi
      let NEXT_WAIT_TIME=NEXT_WAIT_TIME+1
    done

    if [ $COMMAND_STATUS -eq 0 ]; then
      success "=== The '${servicename}' has been stopped. ==="
    else
      die "===== FATAL. ${servicename} is not stopped cleanly. Login to the server and check ====="
    fi
elif [ "$action" = "restart" ]; then
    command="${0} ${@}"
    stop_command=${command/\-k restart/\-k stop}
    start_command=${command/\-k restart/\-k start}

    info "=== Step1 Stoping...==="
    set +e; $stop_command; set -e

    info ""
    info ""

    info "=== Step2 Then Starting...==="
    $start_command
else
  die "Unknow Action $action" $ERROR_UNKNOWN
fi



