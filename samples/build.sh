rm -f echoserver.jar
javac EchoServer.java
jar cvfm echoserver.jar MANIFEST.MF *.class
