package com.jfpal


class Utilities {
  def steps
  Utilities(steps) {this.steps = steps}
  def mvn(def args) {
    /* Get jdk tool. */

    String jdktool = steps.tool name: "jdk8", type: 'hudson.model.JDK'
    /* Get the maven tool. */
    def mvnHome = steps.tool name: 'maven', type: 'hudson.tasks.Maven$MavenInstallation'

    /* Set JAVA_HOME, and special PATH variables. */
    List javaEnv = [
        "PATH+JDK=${jdktool}/bin", "JAVA_HOME=${jdktool}",
        '_JAVA_OPTIONS=-XX:MaxPermSize=160m -Xmx256m -Djava.awt.headless=true',
        'GIT_COMMITTER_EMAIL=lch@jfpal.com','GIT_COMMITTER_NAME=LCH@Jenkins','GIT_AUTHOR_NAME=LCH','GIT_AUTHOR_EMAIL=lch@jfpal.com', 'LOGNAME=LCH@Jenkins'
    ]

    /* Call maven tool with java envVars. */
    withEnv(javaEnv) {
        if (isUnix()) {
          steps.sh "${mvnHome}/bin/mvn ${args}"
        } else {
          steps.bat "${mvnHome}\\bin\\mvn ${args}"
        }
    }
  }
}
