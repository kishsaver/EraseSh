# EraseSh  

## これはなに  
USB BootのLinux環境にて，内蔵ストレージを消去するシェルスクリプト 

## HowToUse

### 環境構築
非LVMで適当なcli linuxを入れる  

apt環境を想定  
`sudo apt update && sudo apt install -y  hdparm gdisk util-linux nvmi-cli`  
非lvmインストールのLinux環境にて，  
`/etc/profile.d/`配下に`.sh`形式で配置  
`sudo chmod +x <name>.sh` して実行権限付与

### 削除の実行
USB Bootにて`root`としてログイン
ログイン時，  
`Are you sure you want to ERASE all marked targets? (yes/NO):`  
と表示されるので`yes`で開始
処理終了後`Reboot the system now? (yes/NO):`を`yes`で再起動  

出力は
`/var/log/auto-wipe.log`
に書き込み

### 憂慮事項
実機未検証，VMのみでの検証


