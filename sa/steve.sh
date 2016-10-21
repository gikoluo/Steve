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
# -----------------------------------------------------------------------------

ERROR_UNKNOWN=1
ERROR_PORT_USED=2
ERROR_PID_EXISTS=3
ERROR_PNAME_EXISTS=4

ERROR_SV_NOTRUNNING=11
ERROR_SV_NOTEXISTS=12
ERROR_SV_ISRUNNING=13
ERROR_SV_STARTFATAL=14

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
[ -z "$STEVE_HOME" ] && STEVE_HOME=`cd "$PRGDIR" >/dev/null; pwd`

# Copy STEVE_BASE from CATALINA_HOME if not already set
[ -z "$STEVE_BASE" ] && STEVE_BASE="$STEVE_HOME"

[ -z "$STEVE_CONFIG" ] && STEVE_CONFIG="$STEVE_BASE"/config/

[ -z "$STEVE_OUT" ] && STEVE_OUT="$STEVE_BASE"/logs/steve.out

[ -z "$STEVE_TMPDIR" ] && STEVE_TMPDIR="$STEVE_BASE"/temp

[ -z "$WITH_SUDO" ] && WITH_SUDO=""

usage()
{
  cat <<EOF
Usage:
$0 [h?vVfk:s:]
OPTIONS:
   -s     Server name
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
      if [[ $rhs != "" ]]; then
        if [[ $lhs != "#"* -o $lhs != "[" ]]; then
            # you can test for variables to accept or other conditions here
            #let $lhs=$rhs
            export "$lhs"="$rhs"
        fi
      fi
    done < "$configfile"
}

check_port() 
{
  PID=
  port=${1}
  PID=`lsof -Pn -i:${port} -sTCP:LISTEN |grep -v COMMAND |awk '{print \$2}'`
  if [ -z $PID ]; then
      debug "Port ${port} is free"
  else
      debug "Port ${port} #{$PID} is used"
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
function cmd()     { echo "CMD.    " "$1"; }

function check_sv_service()
{
    if [[ $sv_result == *"supervisor.sock no such file"* ]]; then
        die "supervisord is not running" ${ERROR_SV_NOTRUNNING}
    elif [[ $sv_result == *"no such processg"* ]]; then
        die "supervisor process ${supervisor_name} is not exists" ${ERROR_SV_NOTEXISTS}
    fi
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
        servername=$OPTARG
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

[ -z servername ] && echo "Server name must be set" && die 1

readconfig "$STEVE_CONFIG""$servername".conf

[ -z "$supervisor_name" ] && supervisor_name="${servername}"
[ -z "$retry_time" ] && retry_time=5
[ -z "$sleep_time" ] && sleep_time=5
[ -z "$forcekill" ] && $forcekill=256
[ -z "$forcekill9" ] && $forcekill9=256

if [ "$action" = "debug" ] ; then
  echo "Debug command not available now."
  exit 1
elif [ "$action" = "start" ]; then
    #check port, DIE if port is in use
    if [ ! -z "$use_port" ]; then
      check_port "$use_port"
      if [ ! -z "$PID" ]; then
        debug "PID ""$PID"
        if [ $force -eq 0 ]; then
          die "check port ${use_port} #{$PID} failed. The port is in used." "${ERROR_PORT_USED}"
        fi
      fi
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

    sv_command="${WITH_SUDO} ${supervisorctl} status ${supervisor_name}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`

    check_sv_service
    if [[ $sv_result == *"RUNNING"* ]]; then
        if [ $force -eq 0 ]; then
            die "supervisor process ${supervisor_name} is running" ${ERROR_SV_ISRUNNING}
        fi
    elif [[ $sv_result == *"FATAL"* ]]; then
        info "NOTICE: The previously status is FATAL"
    elif [[ $sv_result == *"STOPPED"* ]]; then
        info "The previously status is STOPPED"
    elif [[ $sv_result == *"EXITED"* ]]; then
        info "The previously status is EXITED"
    fi

    debug "===Starting...==="
    sv_command="${WITH_SUDO} ${supervisorctl} start ${supervisor_name}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`

    info "Supervisorctl return: $sv_result"

    debug "Checking after started..."

    NEXT_WAIT_TIME=0
    COMMAND_STATUS=1
    
    until [ $COMMAND_STATUS -eq 0 -o $NEXT_WAIT_TIME -eq $retry_time ]; do
    
      COMMAND_STATUS=0

      debug "Sleeping... ${sleep_time}, Loop ${NEXT_WAIT_TIME}"
      sleep $sleep_time

      if [[ $sv_result == *"already started"* ]]; then
        debug "OK. Supervisor process ${supervisor_name} is already started"
      elif [[ $sv_result == *"started"* ]]; then
        debug "OK. Supervisor process ${supervisor_name} started"
      elif [[ $sv_result == *"ERROR"* ]]; then
        die "FATAL: The supervisor status is FATAL: ${sv_result}" ${ERROR_SV_STARTFATAL}
      fi

      if [[ $sv_result == *"RUNNING"* ]]; then
          debug "OK. Supervisor process ${supervisor_name} is running"
      elif [[ $sv_result == *"FATAL"* ]]; then
          die "FATAL: The supervisor status is FATAL" ${ERROR_SV_STARTFATAL}
      elif [[ $sv_result == *"STOPPED"* ]]; then
          die "FATAL: The supervisor status is STOPPED" ${ERROR_SV_STARTFATAL}
      elif [[ $sv_result == *"EXITED"* ]]; then
          die "FATAL: The supervisor status is EXITED" ${ERROR_SV_STARTFATAL}
      fi


      if [ ! -z "$use_port" ]; then
        check_port "$use_port"
        if [ -z "$PID" ]; then
          warning "check port ${use_port} failed."
          COMMAND_STATUS=1
        else
          success "Port ${use_port} started"
        fi
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
      success "===== OK. service '${servername}' started. ====="
    else
      die "===== FATAL. started checked failed. Login to the server and check ====="
    fi

elif [ "$action" = "stop" ]; then
    if [ ! -z "$use_port" ]; then
      debug "Checking port ${use_port}..."
      check_port "$use_port"
      if [ ! -z "$PID" ]; then
        success "Checked: Port ${use_port} #{$PID} is running."
      fi
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

    debug "Checking supervisor..."
    check_sv_service
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

    debug "===Stoping...==="
    sv_command="${WITH_SUDO} ${supervisorctl} stop ${supervisor_name}"
    cmd "${sv_command}"
    sv_result=`${sv_command}`

    info "Supervisorctl return: $sv_result"

    #info "$sv_result"

    debug "Checking after stop..."

    NEXT_WAIT_TIME=0
    COMMAND_STATUS=1
    
    until [ $COMMAND_STATUS -eq 0 -o $NEXT_WAIT_TIME -eq $retry_time ]; do
      COMMAND_STATUS=0

      debug "Sleeping... ${sleep_time}, Loop ${NEXT_WAIT_TIME}"
      [ ${NEXT_WAIT_TIME} -eq 0 ] && sleep 2  #stop may be soon, only sleep 2 seconds when the first time
      [ ! ${NEXT_WAIT_TIME} -eq 0 ] && sleep $sleep_time

      if [[ $sv_result == *"ERROR (not running)"* ]]; then
          warning "${supervisor_name} is not running."
      elif [[ $sv_result == *"RUNNING"* ]]; then
          warning "Supervisor process ${supervisor_name} is still running."
          COMMAND_STATUS=1
      elif [[ $sv_result == *"STOPPING"* ]]; then
          warning "Supervisor process ${supervisor_name} is still running."
      elif [[ $sv_result == *"FATAL"* ]]; then
          warning "The supervisor status is FATAL"
      elif [[ $sv_result == *"STOPPED"* ]]; then
          success "OK: The supervisor status is STOPPED"
      elif [[ $sv_result == *"EXITED"* ]]; then
          success "OK: The supervisor status is EXITED"
      fi


      if [ ! -z "$use_port" ]; then
        check_port "$use_port"
        if [ ! -z "$PID" ]; then
            warning "Check port $use_port #${PID} is still running."
            COMMAND_STATUS=1

            if [ $NEXT_WAIT_TIME -ge $forcekill ]; then
              warning "Use Kill TERM to stop the process #{$PID} on port $use_port"
              kill -TERM $PID
            fi

            if [ $NEXT_WAIT_TIME -ge $forcekill9 ]; then
              warning "Use Kill 9 to stop the process #${PID} on port $use_port"
              kill -KILL $$PID
            fi
        else
          success "Check port $use_port success."
        fi
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
      success "=== The '${servername}' has been stopped. ==="
    else
      die "===== FATAL. ${servername} is not stopped cleanly. Login to the server and check ====="
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
  die "Unknow Action $action" ERROR_UNKNOWN
fi


