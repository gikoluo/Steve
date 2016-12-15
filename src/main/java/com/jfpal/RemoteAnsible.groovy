package com.jfpal


class Remote implements Serializable {
    def script
    def host
    def user
    Remote() {}

    Remote(script, host, user) {

        this.script = script
        this.host = host
        this.user = user
    }

    public String cmd(String cmd) {
      script.sh "ssh -o StrictHostKeyChecking=no -l ${user} ${host} '${cmd}' "
    }

    public scp(String src, String dest) {
      script.sh "scp '${src}' '${user}'@'${host}':${dest}"
    }

    public play(def playbook, def inventory, def extra) {
      def playCmd = "cd ~/rhasta/ && ansible-playbook ${playbook}.yml -i ${inventory} ${extra}"
      cmd(playCmd)
    }
}
