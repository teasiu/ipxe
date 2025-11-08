## iPXE 

### 直接在 ubuntu/debian 系统编译

```bash
./build_ipxe.sh
```

成品在 ipxe/products 下面  


### 统一使用菜单文件是 

```
menu.ipxe
```

### openwrt 双模式共存使用
#### 1. bios 网启

网络 - DHCP - TFTP 开启 (打勾)

比如在 /www 目录中新建一个 tftp目录

```
mkdir -p /www/tftp
```
在本仓库资源releases里下载  undionly-bios.kpxe  snponly-x64.efi 两个文件；  
在本仓库的 tftp 文件夹下载四个文件；  
放在 openwrt 系统的 /www/tftp 文件夹下;  

网络 - DHCP - TFTP 界面，填写目录为 ```/www/tftp``` ，启动文件为 ```undionly-bios.kpxe```

保存即可生效 bios 的机器的启动。  

#### 2. UEFI 网启

进入 openwrt 系统 ssh 后台，  
修改 /etc/dnsmasq.conf 文件，  
```
vi /etc/dnsmasq.conf
```
将下面内容添加到最后面：  
```
enable-tftp
tftp-lowercase
dhcp-no-override
tftp-root=/www/tftp

dhcp-match=set:iPXE,175

dhcp-vendorclass=set:flag,PXEClient:Arch:00000
dhcp-vendorclass=set:flag,PXEClient:Arch:00006
dhcp-vendorclass=set:flag,PXEClient:Arch:00007
dhcp-vendorclass=set:flag,PXEClient:Arch:00009

tag-if=set:load,tag:!iPXE,tag:flag

pxe-prompt="Press F8 or Enter key for PXE menu.", 5

pxe-service=tag:load,X86PC, "BIOS ipxe undionly", undionly-bios.kpxe
pxe-service=tag:load,X86PC, "boot from local", 0

pxe-service=tag:load,7, "iPXE snponly UEFI(7)", snponly-x64.efi
pxe-service=tag:load,9, "iPXE snponly UEFI(9)", snponly-x64.efi

pxe-service=tag:load,07,  "iPXE UEFI(07)", snponly-x64.efi
pxe-service=tag:load,09,  "iPXE UEFI(09)", snponly-x64.efi
```

保存后重启服务 ：
```
/etc/init.d/dnsmasq restart
```

#### 3.自行修改菜单文件内容，使能启动你需要的系统

双模式的启动都是共用菜单文件 menu.ipxe  
请使用正确的软件编辑这个菜单，建议使用 notepad3 文本编辑  

### 祝你玩机愉快


