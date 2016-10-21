#!/bin/bash
export DOMAIN_HOME="/data/weblogic"
WEBLOGIC_HOME="${DOMAIN_HOME}"
export JAVA_HOME=/data/weblogic/java1.8

function shutdown()
{
    date
    echo "Shutting down Weblogic"
    $WEBLOGIC_HOME/bin/stopWebLogic.sh username password
}

date
echo "Starting Weblogic"

# Allow any signal which would kill a process to stop Weblogic
trap shutdown HUP INT QUIT ABRT KILL ALRM TERM TSTP

. $WEBLOGIC_HOME/bin/startWebLogic.sh username password


#echo "Waiting for `cat $WWEBLOGIC_PID`"
#wait `cat $WWEBLOGIC_PID`