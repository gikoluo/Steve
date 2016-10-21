import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;

public class EchoServer {

    public EchoServer(int port) throws IOException {
        
        ServerSocket serverSocket = new ServerSocket(port);
        System.out.println("starting echo server on port: " + port);

        int flag = 0;
        // if (flag == 0) {
        //     throw new IOException();
        // }
        
        while (true) {
            Socket socket = serverSocket.accept();
            System.err.println("accept connection from client");
            InputStream in = socket.getInputStream();
            OutputStream out = socket.getOutputStream();
            byte[] b = new byte[4 * 1024];
            int len;
            while ((len = in.read(b)) != -1) {
                out.write(b, 0, len);
            }
            System.err.println("closing connection with client");
            out.close();
            in.close();
            socket.close();
        }
    }

    public static void main(String[] args) throws IOException {
        new EchoServer(10888);
    }
}