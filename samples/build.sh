rm -f hello.jar
javac EchoServer.java
jar cvfm hello.jar MANIFEST.MF *.class
