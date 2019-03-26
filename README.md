# Steve
建立了一个Bash脚本，用于启停进程。启停前后，均会对进程关联进程进行检查，确保进程被完全关闭，也确保进程被正确启动。 对于顽固进程特别有效！
功能：
- 服务安全启动
- 服务安全关闭
- 监控服务状态
- 自动重启服务。 当服务意外蹦了的时候，自动重启之
- 以及Supervisord提供的管理服务的WEB工具

更多介绍和使用说明，参考 [Wiki](https://github.com/gikoluo/Steve/wiki)


# 安装
本脚本为纯Bash， 尽量较少运维依赖。 Git clone后即可使用。
服务启动依赖于Supervisor。 Supervisord是用Python实现的一款非常实用的进程管理工具，类似于monit。
Supervisord会能将你的程序转化为Daemon服务。

# Supervisord 安装
supervisord可使用Linux系统原生的包管理工具安装，也可以使用easy_install, pip进行安装。
详细参考 http://supervisord.org/installing.html 
简单介绍一下centos easy_install的方法：
```bash
 yum install python-setuptools
 easy_install -U supervisor
 echo_supervisord_conf > /etc/supervisord.conf
 supervisord
```

# Supervisor 配置
在/etc/supervisord.conf中增加行。
```
[include]
files = /etc/supervisor.d/*.ini
```

建立/etc/supervisor.d/目录，以servicename.ini命名，建立需要管理的多项任务。 示例任务见 examples 下文件。
配置文件修改和任务新增后，别忘了重启supervisor服务。通过命令可查看各任务状态：`supervisorctl status`

# Steve 配置
```
[hello]
###service manager. May be supervisord, init, systemd. Default: supervisord. 
servicetype=supervisord
###set the port here. You have to check the port manually.
use_port=10888
###set the pname here. I will check the processname which contains this.
use_pname=hello.jar
###sleep N second for next checking
sleep_time=2
### How many times need to check
retry_time=5
### use kill in N times checking
forcekill=1
### use kill -9 in N times checking
forcekill9=3

#stdlog=/data/workspace/architect/samples/logs/
#JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_25.jdk/Contents/Home
#supervisor_name=hello
### type may be jar, tomcat, weblogic
type=jar
### file is no useful
file=/data/workspace/architect/samples/hello.jar
```
配置为键值对，以=分割。 以#,[开头的配置行被直接忽略， 没有=号的也被忽略。  =号两边不要放空格， 行首行尾不要放空格。

- supervisor_name （option） 如果没有填写，则和service名称相同。 
- use_port    （option） 进程使用端口。 进程启停时，将检查端口占用情况。
- use_pname   （option） 进程名。 进程启停时，将通过ps进行检查。 应该选用能显示能唯一代表进程的名字，如文件名.jar等。 不要使用java等进程名，以防误判误伤。
- sleep_time  （option） Default： 5。检查后等待sleep_time秒后，进行下一次检查。
- retry_time  （option） Default： 5。检查失败后的重试次数
- forcekill    (option) 在第N次检查后，如果服务仍未停止，则使用`kill -TERM`杀掉进程。 检查包括port， pname检查。 N从0开始
- forcekill9   (option) 在第N次检查后，如果服务仍未停止，则使用`kill -KILL`（`kill -9`））杀掉进程。 检查包括port， pname检查。 N从0开始。 如果forcekill， forcekill9无此选项，或大约retry_time， 则不会使用kill灭进程。 forcekill9 数字应该大于 forcekill


# Steve使用
下载到steve.sh脚本后，在同级目录下建立config文件夹，并建立配置文件。
```
./steve.sh -k restart -s tomcat
```
参数说明：
- -s     Server name 服务名称。将读取文件夹下对应的配置文件，执行steve
- -k     Action. start, stop, restart, debug  操作明。 对服务进行启动、停止、重启、或显示测试信息
- -h|-?  Show this message  帮助
- -V     Steve Version   显示Steve版本
- -v     Verbose         显示调试信息
- -f     Force run       强制运行，即使在检查中发生错误。 尽量别用。

# Steve Processes
##STOP
```
            +---------------+
            |               |
+Stop+------>   Check Port  |
            |               |
            +--------+------+
                     |                     +---------------------+
                     |                     |                     |
                     |                     |                     |
           +---------v--------+            |                     +<-------------------------------------+
           |                  |            |                     |                                      |
           |  Check PID file  |            |                     |                                      |
           |                  |            |                     |                                      |
           +---------+--------+            |                     |                                      |
                     |                     |             +-------v-------+     +---------------------+  |
                     |                     |             |               |     |                     |  |
                     |           +---------+----------+  |   CheckPort   o-----+  kill +Signal       |  |
          +----------v-------+   |                    |  |               |     |         When Needed |  |
          |                  |   |    Stop Service    |  +--------+------+     +-----+---+-----------+  |
          |  Check Process   |   |                    |           |                  |   |              |
          |       Name       |   +--------^-----------+           |                  |   |              |
          +--------+---------+            |                       |                  |   |              |
                   |                      |             +---------v--------+         |   |              |
                   |                      |             |                  |         |   |              |
                   |                      |             |  Check PID file  o---------+   |              |
                   |                      |             |                  |             |              |
                   |                      |             +---------+--------+             |              |
                   |                      |                       |                      |              |
                   +----------------------+                       |                      |              |
                                                                  |                      |              |
                                                       +----------v-------+              |              |
                                                       |                  |              |              |
                                                       |  Check Process   o--------------+              |
                                                       |       file       |                             |
                                                       +----------+-------+                             |
                                                                  |          Retry when                 |
                                                                  |          check failed               |
                                                                  +-------------------------------------+
                                                                  |
                                                                  |
                                                       +----------v------------+
                                                       |                       |
                                                       |      Stop Result      |
                                                       |                       |
                                                       +-----------------------+
```
##START
```
             +---------------+
             |               |
-Start------->   CheckPort   |
             |               |
             +--------+------+
                      |                     +----------- ----------+
                      |                     |                      |
                      |                     |                      |
            +---------v--------+            |                      | <----------------+
            |                  |            |                      |                  |
            |  Check PID file  |            |                      |                  |
            |                  |            |                      |                  |
            +---------+--------+            |                      |                  |
                      |                     |              +-------v-------+          |
                      |                     |              |               |          |
                      |           +---------+----------+   |   CheckPort   |          |
           +----------v-------+   |                    |   |               |          |
           |                  |   |                    |   +--------+------+          |
           |  Check Process   |   |   Start Ser^ice    |            |                 |
           |    file          |   |                    |            |                 |
           +--------+---------+   +--------+-----------+            |                 |
                    |                      ^              +---------v--------+        |
                    |                      |              |                  |        |
                    |                      |              |  Check PID file  |        |
                    |                      |              |                  |        |
                    |                      |              +---------+--------+        |
                    |                      |                        |                 |
                    +----------------------+                        |                 |
                    |                                               |                 |
                    |                                    +----------v-------+         |
          +---------v---------------------+              |                  |         |
          |                               |              |  Check Process   |         |
          |         Exit                  |              |    file          |         |
          |   When the process is running |              +----------+-------+         |
          |                               |                         |                 |
          +-------------------------------+                         |   Retry when    |
                                                                    |  check failed   |
                                                                    +-----------------+
                                                                    |
                                                         +----------v------------+
                                                         |                       |
                                                         |                       |
                                                         |     Show  Result      |
                                                         |                       |
                                                         +-----------------------+
```
##RESTART
STOP && Start


# 咖啡
如果您觉得此功能有用，微信扫一扫，请我喝杯咖啡。
 ![即富二维码](https://raw.githubusercontent.com/gikoluo/Steve/master/samples/A00000000066.png)
