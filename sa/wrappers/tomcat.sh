#!/bin/bash
# Source: https://confluence.atlassian.com/plugins/viewsource/viewpagesrc.action?pageId=252348917
export TOMCAT_HOME=/data/tomcat
export CATALINA_HOME=/data/tomcat
#cd $TOMCAT_HOME/bin
function shutdown()
{
    date
    echo "Shutting down Tomcat"
    unset CATALINA_PID # Necessary in some cases
    unset LD_LIBRARY_PATH # Necessary in some cases
    unset JAVA_OPTS # Necessary in some cases

    $TOMCAT_HOME/bin/catalina.sh stop 10
}

date
echo "Starting Tomcat"
export CATALINA_PID=/tmp/$$
export JAVA_HOME=/opt/jdk1.7.0_80

#export LD_LIBRARY_PATH=/usr/local/apr/lib
#export JAVA_OPTS="-Dcom.sun.management.jmxremote.port=8999 -Dcom.sun.management.jmxremote.password.file=/etc/tomcat.jmx.pwd -Dcom.sun.management.jmxremote.access.file=/etc/tomcat.jmxremote.access -Dcom.sun.management.jmxremote.ssl=false -Xms128m -Xmx3072m -XX:MaxPermSize=256m"

# Uncomment to increase Tomcat's maximum heap allocation
# export JAVA_OPTS=-Xmx512M $JAVA_OPTS

#clean the cache
rm -rf $TOMCAT_HOME/work/Catalina/
. $TOMCAT_HOME/bin/catalina.sh start

# Allow any signal which would kill a process to stop Tomcat
trap shutdown HUP INT QUIT ABRT KILL ALRM TERM TSTP

echo "Waiting for `cat $CATALINA_PID`"
wait `cat $CATALINA_PID`