# Celestia
<div>
<img src="https://avatars.githubusercontent.com/u/54859940?s=200&v=4"  style="float: right;" width="100" height="100"></img>
</div>

Official documentation:
>- [Validator setup instructions](https://docs.celestia.org/how-to-guides/nodes-overview)

---  

<h1 align="left" style="display: flex;"> ✅ Celestia node Setup for Mocha-4 Testnet and Celestia mainnet</h1>

# 📋 Upgrade celestia test app
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/upgradeapp.sh)
~~~
# 📋 Upgrade celestia test node 
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/upgradenode.sh)
~~~
# 📋 Upgrade celestia main app
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/upgradeappmain.sh)
~~~
# 📋 Upgrade celestia main node 
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/upgradenodemain.sh)
~~~
# 🛠️ Install test validator
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installvalidatortest.sh)
~~~
# 🛠️ Install main validator
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installvalidatormain.sh)
~~~
# 🛠️ Install full test node
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installfulltest.sh)
~~~
# 🛠️ Install full main node
~~~bash
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installfullmain.sh)
~~~
# 🛠️ Install test bridge
~~~bash 
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installbridgetest.sh)
~~~
# 🛠️ Install main bridge
~~~bash 
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installbridgemain.sh)
~~~
# 🛠️ Install monitoring
~~~bash 
source <(curl -s https://raw.githubusercontent.com/chaindigital/celestia/main/installmonitoring.sh)
~~~



### 🧑‍💻 Firewall security
Set the default to allow outgoing connections, deny all incoming, allow ssh and node p2p port
  ~~~bash
  sudo ufw enable 
  sudo ufw default allow outgoing 
  sudo ufw default deny incoming 
  sudo ufw allow ssh/tcp 
  sudo ufw allow 26658,2121/tcp 
  sudo ufw allow 2121/udp 
  ~~~
