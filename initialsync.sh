#!/bin/bash
#initialsync by abrevick@liquidweb.com
ver="Sep 27 2013"
# http://migration.sysres.liquidweb.com/initialsync.sh
# https://github.com/defenestration/initialsync

starttime=`date +%F.%T`
scriptlogdir="/home/temp"
scriptlog="${scriptlogdir}/initialsync.${starttime}.log"
userlistfile=/root/userlist.txt
rsyncflags="-avHl"
mysqldumplog="/tmp/mysqldump.log"
remoteusersfile="/home/temp/remoteusers.txt"
sshargs="" #-t, -qt, -qtt, doesn't matter, all end up causing some sort of problem, best to leave blank and deal with the stdin: is not tty error.  -q doesn't cause  aproblem but doesn't make it quiet either, its mostly -t

dnr=/root/didnotrestore.txt
dnrold="${dnr}.${starttime}.bak"
#back up current dnr file if it exists, and check dnrold for users that didn't restore later on (in the menu)
if [ -s $dnr ]; then
  dnrusers=`cat $dnr`
  if ! [ -s $dnrold ]; then
    mv $dnr $dnrold
  else
    > $dnr
  fi
  > $dnr
fi

> /tmp/remotefail.txt
> /tmp/localfail.txt
> /tmp/migration.rsync.log
> /tmp/userexists.txt
mkdir -p $scriptlogdir
echo $ver > $scriptlog
allcpusers=`/bin/ls -A /var/cpanel/users | grep -v ^root$ | grep -v ^system$`

#colors
nocolor="\E[0m"
black="\033[0;30m"
grey="\033[1;30m"
red="\033[0;31m"
lightRed="\033[1;31m"
green="\033[0;32m"
lightGreen="\033[1;32m"
brown="\033[0;33m"
yellow="\033[1;33m"
blue="\033[0;34m"
lightBlue="\033[1;34m"
purple="\033[0;35m"
lightPurple="\033[1;35m"
cyan="\033[0;36m"
lightCyan="\033[1;36m"
white="\033[1;37m" #a bold white
#background colors: \033[bold;color;background
greyBg="\033[1;37;40m"

#echo in a color function
ec() {
#Usage: ec $color "text"
ecolor=${!1} #get the color
shift #$1 is removed here
#echo the rest
echo -e ${ecolor}"${*}"${nocolor}
}

e2c() {
  #press enter to continue
  ec lightCyan "Press Enter to continue..."
  read
}

logit() {
tee -a $scriptlog
}

yesNo() { #generic yesNo function
#repeat if yes or no option not valid
while true; do
#$* read every parameter given to the yesNo function which will be the message
 echo -ne "${yellow}${*}${white} (Y/N)?${nocolor} " 
 #junk holds the extra parameters yn holds the first parameters
 read yn junk
 case $yn in
  yes|Yes|YES|y|Y)
    echo "y" >> $scriptlog
    return 0  ;;
  no|No|n|N|NO)
    echo "n" >> $scriptlog
    return 1  ;;
  *) 
    ec lightRed "Please enter y or n." 
 esac
done    
#usage:
#if yesNo 'do you want to continue?' ; then
#    echo 'You choose to continue'
#else
#    echo 'You choose not to continue'
#fi
}

menutext() {
echo "Version: $ver"
echo
#check for screen session
if [[ ! "${STY}" ]]; then
  ec lightRed "Warning! You are not in a screen session!"
  echo
fi

#check for didnotrestore now:
if [ -s "$dnrold" ]; then
  ec lightRed "Found users that did not restore from a previous sync in $dnrold! Press d to see these users."
  echo
  logvars dnrusers
fi

ec greyBg "=Initialsync Main Menu=
Select the migration type:"
echo "1) Full sync (from $userlistfile or all users, version matching)
2) Basic sync (all users, no version matching) 
3) Single user sync (no version matching, shared server safe)
4) User list sync (from $userlistfile, no version matching)
5) Restore users from $dnr. (no version matching)
8) Database sync - only sync databases for cpanel users, and from /root/dblist.txt.
9) Final sync (from $userlistfile or all users)
0) Quit

Post migration script at /root/postmigration.sh will run after the final sync if found."
}

main() {
echo "Version $ver" 
echo "Started $starttime" 
#menu options
mainloop=0
while [ $mainloop == 0 ] ; do
 clear
 menutext
 echo -n "Enter your choice: "
 read choice
 case $choice in 
 1) 
  fullsync 
  mainloop=1 ;;
 2) 
  basicsync 
  mainloop=1 ;;
 3)
  singleuser 
  mainloop=1 ;;
 4)
  listsync
  mainloop=1   ;;
 5)
  dnrsync
  mainloop=1 ;;
 8) 
  dbsync
  mainloop=1 ;;
 9)
  finalsync
  mainloop=1 ;;
 0) 
  echo "Bye..."; exit 0 ;;
 d)
  if [ -s ${dnrold} ]; then
    cat ${dnrold}
    if yesNo "Do you want to restore these users?"; then
      dnrsync
      mainloop=1
    fi 
   else
    echo "${dnrold} file not found! Quit mashing keys!"
  fi
  e2c
  clear
  ;; 
 *)  
   ec lightRed "Not a valid choice. Also, the game."; sleep 2 ; clear 
 esac
done
sleep 3
echo
echo "Started at $starttime"  
[ $syncstarttime ] && echo "Sync started at $syncstarttime" 
[ $syncendtime ] &&  echo "Sync finished at $syncendtime" 
echo "Finished at `date +%F.%T`" 
#cleanup
if [ -s /root/dblist.txt ]; then 
 mv /root/dblist.txt{,.$starttime}
fi
ec lightGreen 'Done!'  
exit 0
}

dbsync() {
dbonlysync=1
echo "Database only sync." 
userlist=$allcpusers
getip        #asks for ip or checks a file to confirm destination
mysqldbfinalsync
}

#sync types
singleuser() {
echo
echo "Single user sync." 
singleuserloop=0
while [ $singleuserloop == 0 ]; do 
  echo -n "Input name of the user to migrate:"  
  read userlist
  if yesNo "Restore to dedicated ip?"; then
   forcededip=1 
  fi
  #check for error
  sucheck=`/bin/ls -A /var/cpanel/users | grep ^${userlist}$`
  logvars userlist sucheck forcededip
  if  [[ $sucheck = $userlist ]]; then
    echo "Found $userlist, restoring..." 
    singleuserloop=1
    #rsyncupgrade
    getip        #asks for ip or checks a file to confirm destination
    accountcheck #if conflicting accounts are found, asks
    acctcopy
    didntrestore
    echo
    if yesNo "Remove ssh key from remote server?" ; then
      echo "Removing key..."
      ssh $sshargs -p$port $ip "rm ~/.ssh/authorized_keys ; cp -rp ~/.ssh/authorized_keys{.initialsyncbak,}"
    else
      echo "Leaving key."
    fi
  else
    ec lightRed "Could not find $userlist." 
  fi
done
}

dnrsync() {
  echo "DNR sync"
  #check the that dnr.starttime file exists, use it for list sync
  if [ -s "${dnrold}" ]; then
    echo $dnrusers > $userlistfile
    listsync
  else
    echo "Did not find any users in the ${dnrold} file. Try a list sync instead."
  fi
}

listsync() {
echo
echo "List sync." 
listsyncvar=1
if [ -s $userlistfile ]; then
 ec yellow "Found $userlistfile" 
 sleep 3
 userlist=`cat $userlistfile`
 logvars userlist
 echo "$userlist" 
 presync
 copyaccounts
else 
 echo "Did not find users in $userlistfile in /root or /home" 
 sleep 3
fi
}

basicsync(){
echo
echo "Basic Sync started" 
previousmigcheck
presync
copyaccounts
}

fullsync() {
echo
echo "Full sync started" 
#check versions,  run ea, upcp, match php versions, lots of good stuff
previousmigcheck
presync
versionmatching
copyaccounts
}

#Main sync procecures
presync() {
echo "Running Pre-sync functions..." 
#get ips and such
sslcertcheck
dnscheck     #lets you view current dns
rsyncupgrade
lowerttls    
getip        #asks for ip or checks a file to confirm destination
dnsclustercheck
accountcheck #if conflicting accounts are found, asks
dedipcheck  #asks if an equal amount of ips are not found
mysqlsymlinkcheck
}

versionmatching() {
#only full syncs
echo "Running version matching..." 
nameservers
gcccheck #needs to be before upcp, ea
upcp
apacheprepostcheck
phpmemcheck 
thirdparty
mysqlcheck 
upea
installprogs
phpapicheck  # to be ran after ea so php4 can be compiled in if needed
rubygems
matchpear
}

copyaccounts() {
echo "Starting account copying functions..." 
acctcopy
didntrestore
mysqlextradbcheck
mysqldumpinitialsync
cpbackupcheck
postmigrationhook
finalchecks
hostsgen
}

previousmigcheck() { 
#check for previous migration, and define userlist
echo
echo  "Checking for previous migrations..."
#check for userlist file
if [ -s $userlistfile ]; then
 echo "$userlistfile found: " 
 cat $userlistfile 
  if yesNo "Do you want to use this list from $userlistfile?" ; then
    userlist=`cat $userlistfile`
  else
    echo "Backing up $userlistfile to ${userlistfile}.${starttime}.bak."
    mv $userlistfile ${userlistfile}.${starttime}.bak
    echo "Selecting all users." 
    userlist=$allcpusers
  fi
else 
 echo "No previous migration found, migrating all users."
 userlist=$allcpusers
fi

ec yellow "Users selected for migration:" 
echo $userlist 
sleep 3
}

hostsgen() {
echo
echo "Generating hosts file..." 
#ssh $ip -p$port "wget -O /scripts/hosts.sh http://migration.sysres.liquidweb.com/hosts.sh ; bash /scripts/hosts.sh" 
cat > /scripts/hosts.sh <<'EOF'
#!/bin/bash
#abrevick@lw Nov 21 2011
#obtain hosts file format from a cpanel server for easy testing
hostsfile=/usr/local/apache/htdocs/hosts.txt
hostsfilealt=/usr/local/apache/htdocs/hostsfile.txt
ip=`grep ADDR /etc/wwwacct.conf |cut -f2 -d" "`
if [ -s $hostsfile ]; then
 mv $hostsfile{,.bak}
fi
if [ -s /etc/userdatadomains ]; then
#new way for cpanel 11.27+ 
 for ips in `/scripts/ipusage | cut -d" " -f1`; do 
  sites=`grep $ips /etc/userdatadomains |awk -F== '{print $1}' |cut -d: -f1 |sort |uniq | sed -e 's/\(.*\)/\1 www.\1/g' `; 
  echo $ips $sites ; 
 done | tee $hostsfile ; 
#one line per domain (purkis way)
  > $hostsfilealt
  cat /etc/userdatadomains | sed -e 's/:/ /g' -e 's/==/ /g' -e 's/\*/x/g' | while read sdomain user owner type maindomain docroot ip port ; do 
  echo $ip $sdomain "www."$sdomain >> $hostsfilealt 
 done 
echo
echo "Generated hosts file at http://${ip}/hosts.txt"
echo "One line per domain at http://${ip}/hostsfile.txt" 
else
#old way
echo "/etc/userdatadomains not found, using old way."
 /scripts/ipusage | sed -e 's/\[mail:.*//g' -e 's/,/ /g' -e 's/\[http://g' -e 's/\]//g' -e 's/\[ftp:.*//g' | sed 's/\ \ /\ /g' | tee $hostsfile 
/scripts/ipusage | sed -e 's/\[mail:.*//g' -e 's/,/ /g' -e 's/\[http://g' -e 's/\]//g' -e 's/\[ftp:.*//g' -e 's/\ \ /\ /g' -e 's/\ \([a-zA-Z0-9]\)/\ www.\1/g' | tee -a $hostsfile
echo
echo "Generated hosts file at http://${ip}/hosts.txt." 
fi
EOF
rsync -aqHPe "ssh -p$port" /scripts/hosts.sh $ip:/scripts/
ssh $sshargs -p$port $ip "bash /scripts/hosts.sh"
sleep 2
}

dnsclustercheck() {
echo 
echo "Checking for DNS clustering..." 
if [ -f /var/cpanel/useclusteringdns ]; then
 echo 'Local DNS Clustering found!' 
 localcluster=1
fi
remotednscluster=`ssh $sshargs -p$port $ip "if [ -f /var/cpanel/useclusteringdns ]; then echo \"Remote DNS Clustering found.\" ; fi" `
logvars localcluster remotednscluster
if [ "$remotednscluster" ]; then
 echo
 echo "DNS cluster on the new server is detected, you shouldn't continue since restoring accounts has the potential to automatically update DNS for them in the cluster. Probably will be better to remove the remote server from the cluster before continuing." 
 if yesNo 'Do you want to continue?'; then
  echo "Continuing..." 
 else
  exit 0
 fi
fi

}

sslcertcheck() {
#SSl cert checking.
echo "Checking for SSL Certificates in apache conf." 
crtcheck=`grep SSLCertificateFile /usr/local/apache/conf/httpd.conf`
logvars crtcheck
if [ "$crtcheck" ]; then
 ec yellow "SSL Certificates detected." 
 echo
 for crt in `grep SSLCertificateFile /usr/local/apache/conf/httpd.conf |awk '{print $2}'`; do
  echo $crt; openssl x509 -noout -in $crt -issuer  -subject  -dates 
  echo 
 done
 echo
 e2c
else
 echo "No SSL Certificates found in httpd.conf." 
 sleep 2 
fi
}

dnscheck() {
echo
echo "Checking Current dns..." 
if [ -f /root/dns.txt ]; then
 echo "Found /root/dns.txt" 
 sleep 3
 cat /root/dns.txt | sort -n +3 -2 | more
else
  if [ -f "/root/domainlist.txt" ]; then
    mv /root/domainlist.txt /root/domainlist.txt.${starttime}.bak
  fi
  for user in $userlist; do cat /etc/userdomains | grep $user | cut -d: -f1 >> /root/domainlist.txt; done
  domainlist=`cat /root/domainlist.txt`
  logvars domainlist
  for each in $domainlist; do echo $each\ `dig @8.8.8.8 NS +short $each |sed 's/\.$//g'`\ `dig @8.8.8.8 +short $each` ;done | grep -v \ \ | column -t > /root/dns.txt
  cat /root/dns.txt | sort -n +3 -2 | more
fi
e2c
}

lowerttls() {
echo
echo "Lowering TTLs..." 
#lower ttls, switched to find command for a lot of domains
#sed -i.lwbak -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' /var/named/*.db
#find /var/named/ -name \*.db -exec sed -i.lwbak -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' {} \;
#switched to perl as sed -i doesn't exist in old versions of sed
find /var/named/ -name \*.db -exec perl -pi -e 's/^\$TTL.*/\$TTL 300/g' {} \;
find /var/named/ -name \*.db -exec perl -pi -e 's/[0-9]{10}/'`date +%Y%m%d%H`'/g' {} \;


rndc reload
#for the one time i encountered NSD
nsdcheck=`ps aux |grep nsd |grep -v grep`
logvars nsdcheck
if [ "$nsdcheck" ]; then
 if [ `which nsdc` ]; then
  echo "Nsd found, reloading"
  nsdc rebuild
  nsdc reload
 fi
fi
}

getip() {
echo
echo "Getting Ip for destination server..." 
#check for previous migration, just in case.
ipfile=/root/dest.ip.txt
if [ -f $ipfile ]; then
 ip=`cat $ipfile`
 echo
 ec yellow "Ip from previous migration found: `echo $ip`"   
 getport
 echo
 if yesNo "Is $ip the server you want?  Otherwise enter No to input new ip." ;then
  echo "Ok, continuing with $ip" 
  sshkeygen
 else
  rm -rf /root/dest.port.txt
  ipask 
 fi
else
 ipask
fi
sleep 1
logvars ip
}

ipask() {
echo
echo -n 'Destination IP: '; 
read ip 
echo $ip > $ipfile
getport
sshkeygen
}

getport() {
echo
echo "Getting ssh port." 
if [ -s /root/dest.port.txt ]; then
 port=`cat /root/dest.port.txt`
 ec yellow "Previous Ssh port found: ($port)."
else 
 echo -n "SSH Port [22]: "
 read port
fi
if [ -z $port ]; then
 echo "No port given, assuming 22"
 port=22
fi
echo $port > /root/dest.port.txt
logvars port

}

sshkeygen() {
echo
if ! [ -f ~/.ssh/id_rsa ]; then  
 echo "Generating SSH key..." 
 ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
else
  echo "SSH key found." 
fi
echo "Copying Key to remote server..." 
#create .ssh directory
#create authorized key file if it doesn't exist (for non-existing files) backup the file to syncbak, this will keep existing and blank files.
#don't overwrite existing .initialsyncbak files.
cat ~/.ssh/id_rsa.pub | ssh $sshargs $ip -p$port "mkdir -p ~/.ssh ; if [ ! -f ~/.ssh/authorized_keys ] ; then touch ~/.ssh/authorized_keys ; fi; if [ ! -f ~/.ssh/authorized_keys.initialsyncbak ] ; then cp -rp ~/.ssh/authorized_keys{,.initialsyncbak} ; fi ; cat >> ~/.ssh/authorized_keys"
sshtest=$?
#test exit value of ssh command.
if [[ "$sshtest" > 0 ]]; then 
  ec lightRed "Ssh connection to $ip failed, please check connection before retrying!"
  exit 3
else
  ec lightGreen "Ssh connection to $ip succeded!"
  
  ssh $sshargs -p$port $ip "chmod 2755 /usr/bin/screen; chmod 775 /var/run/screen"

fi

}
 

accountcheck() { #check for users with the same name on each server:
echo
echo "Comparing accounts with destination server..." 
ssh $sshargs $ip -p$port "/bin/ls -A /var/cpanel/users/" > $remoteusersfile
for user in $userlist ; do 
  if [ `grep "^$user$" "$remoteusersfile"` ]; then 
    echo $user
  fi  
done >> /tmp/userexists.txt
#check for userexists.txt greater than 0
if [ -s /tmp/userexists.txt ]; then
 ec lightRed 'Accounts that conflict with the destination server:' 
 cat /tmp/userexists.txt 
 if yesNo "Y to continue, N to exit."; then
  echo "Continuing..."
 else
  echo "Exiting..."
  exit 0
 fi
else
  echo "No conflicting accounts found."
fi
}

dedipcheck() { #check for same amount of dedicated ips
echo
echo "Checking for dedicated Ips." 
# If /etc/userdatadomains exists, calculate dedicated IPs based on usage.
# Otherwise uses same functionality as before.
if [[ -f /etc/userdatadomains ]]; then
  preliminary_ip_check=`cat /etc/userdatadomains|sed -e 's/:/ /g' -e 's/==/ /g' -e '/\*/d' |cut -d ' ' -f8|tr -d [:blank:]|sort|uniq`
  server_main_ip=`cat /etc/wwwacct.conf|grep ADDR|cut -d ' ' -f2`
  for preliminary_ips in $preliminary_ip_check; do
    if [[ $preliminary_ips != $server_main_ip ]]; then
      dedicated_ip_accounts="${dedicated_ip_accounts} $preliminary_ips"
    fi
    logvars preliminary_ips dedicated_ip_accounts
  done
  sourceipcount=`echo $dedicated_ip_accounts|sed -e 's/ /\n/g'|wc -l`
else
  sourceipcount=`cat /etc/ips | grep ^[0-9] | wc -l`
fi
# Check target server for number of dedicated IPs available
destipcount=`ssh $sshargs $ip -p$port "cat /etc/ips |grep ^[0-9] | wc -l"`
logvars destipcount preliminary_ip_check server_main_ip sourceipcount
echo "==Dedicated Ip Count==
Source (Ips in use): $sourceipcount
Destination        : $destipcount"
if (( $sourceipcount <= $destipcount ));then
  ec lightGreen "There seems to be enough IPs on the destination server for this migration."
  ipcheckquery
else
  ec lightRed "The Destination server does not seem to have enough dedicated IPs." 
  ipcheckquery
fi
sleep 1
}

ipcheckquery(){
ipcheck=0
if yesNo "Override IP check?
 yes = Restore accounts to dedicated Ips. (Please ensure there are enough Dedicated IPs)
 no  = Restore accounts to the Main Shared Ip." ;then
  echo "Restoring accounts to dedicated IPs."
  ipcheck=1
else
  echo "Restoring accounts to the main shared Ip."
  ipcheck=0
fi
logvars ipcheck
}

nameservers() {
echo "Current nameservers:" 
grep ^NS[\ 0-9]  /etc/wwwacct.conf 
if yesNo "Set nameservers on remote host?" ;then
 grep ^NS[\ 0-9]  /etc/wwwacct.conf > /tmp/nameservers.txt
 rsync -avHPe "ssh -p$port" /tmp/nameservers.txt $ip:/tmp/
 ssh $sshargs $ip -p$port "cp -rp /etc/wwwacct.conf{,.bak} ;
 sed -i -e '/^NS[\ 0-9]/d' /etc/wwwacct.conf ;
 cat /tmp/nameservers.txt >> /etc/wwwacct.conf " 
fi

}

apacheprepostcheck() { #check for pre/post conf files
apachefilelist="post_virtualhost_1.conf
post_virtualhost_2.conf
post_virtualhost_global.conf
pre_main_1.conf
pre_main_2.conf
pre_main_global.conf
pre_virtualhost_1.conf
pre_virtualhost_2.conf
pre_virtualhost_global.conf"
for file in $apachefilelist; do
 if [ -s /usr/local/apache/conf/includes/$file ]; then
  #file exists and is non-zero size
  echo
  ec lightCyan "Contents of /usr/local/apache/conf/includes/$file :
=================================" 
  cat /usr/local/apache/conf/includes/$file 
  ec cyan "================================="
  if yesNo "Found extra apache configuration in $file, shown above. copy to new server?";  then
   ssh $sshargs -p$port $ip "mv /usr/local/apache/conf/includes/$file{,.bak}"
   rsync -avHPe "ssh -p$port" /usr/local/apache/conf/includes/$file $ip:/usr/local/apache/conf/includes/
  fi
 fi
done
}

phpapicheck() { #run after EA so php4 can be supported
echo
echo "Matching php handlers..." 
/usr/local/cpanel/bin/rebuild_phpconf --current > /tmp/phpconf
#check for ea failure message
if [ "`cat /tmp/phpconf`" == "Sorry, php has not yet been configured with EA3 tools" ]; then
 echo "EA fail message." 
 phpapicheck=1
 logvars phpapicheck
else

 phpver=`grep ^DEFAULT\ PHP /tmp/phpconf |awk '{print $3}'`
 php4sapi=`grep ^PHP4\ SAPI /tmp/phpconf |awk '{print $3}'`
 php5sapi=`grep ^PHP5\ SAPI /tmp/phpconf |awk '{print $3}'`
 phpsuexec=`grep ^SUEXEC /tmp/phpconf |awk '{print $2}'`
 logvars phpver
 logvars php4sapi
 logvars php5sapi
 logvars phpsuexec
#php suexec will be either 'enabled' or 'not installed', check if its not enabled. can set the param with 1 or 0 also.
 if [ "$phpsuexec" != enabled ]; then
  phpsuexec=0
  logvars phpsuexec
 fi
 #check if phpver is 4 or 5, old EA versions will fail the rebuild_phpconf command
 case $phpver in
 [45]) 
 ssh $sshargs $ip -p$port "/usr/local/cpanel/bin/rebuild_phpconf --current > /tmp/phpconf.`date +%F.%T`.txt ;/usr/local/cpanel/bin/rebuild_phpconf $phpver $php4sapi $php5sapi $phpsuexec "  
 ;;
 *)  echo "Got unexpected output from /usr/local/cpanel/bin/rebuild_phpconf --current, skipping..." 
     phpapicheck=1 
     logvars phpapicheck
     ;;
 esac
fi
}

phpmemcheck(){
echo
echo "Checking php memory limit..."  
phpmem=`php -i |grep ^memory_limit |cut -d" " -f3`
rphpmem=`ssh $sshargs $ip -p$port 'php -i |grep ^memory_limit |cut -d" " -f3'`
logvars phpmem
logvars rphpmem
if [ $phpmem ]; then
 if [ $rphpmem ]; then
  if [[ $phpmem != $rphpmem ]]; then
   phpmemcmd=`echo 'sed -i '\''s/\(memory_limit\ =\ \)[0-9]*M/\1'$phpmem'/'\'' /usr/local/lib/php.ini'`
   logvars phpmemcmd
   ssh $sshargs $ip -p$port "cp -rp /usr/local/lib/php.ini{,.bak} ; $phpmemcmd ; service httpd restart" 
  else
   echo "Old memorylimit $phpmem matches new $rphpmem, skipping..." 
  fi
 else 
  echo "Remote php memory_limit not found." 
  phpmemcheck=1
  logvars phpmemcheck
 fi
else
 echo "Local php memory_limit not found." 
 phpmemcheck=1
 logvars phpmemcheck
fi

}

thirdparty() {
#look for random apps to install here, they are installed in installprogs
echo
echo "Checking for 3rd party apps..." 

#Check for ffmpeg
ffmpeg=`which ffmpeg`

#Check for Imagemagick
imagick=`which convert`

#memcache
memcache=`ps aux | grep -e 'memcache' | grep -v grep | tail -n1 `

#java
java=`which java 2>1 /dev/null`

#postgresql 
postgres=`ps aux |grep -e 'postgres' |grep -v grep |tail -n1`

#other stuff, say if it needs to be installed at the end
xcachefound=`ps aux | grep -e 'xcache' | grep -v grep | tail -n1`
eaccelfound=`ps aux | grep -e 'eaccelerator' | grep -v grep |tail -n1`
nginxfound=`ps aux | grep  -e 'nginx' |grep -v grep| tail -n1`
lswsfound=`ps aux | grep  -e 'lsws' | grep -v grep | tail -n1`
logvars ffmpeg imagick memcache java postgres xcachefound eaccelfound nginxfound
}

mysqlcheck() {
#mysql
echo
echo "Checking mysql versions..." 
smysqlv=`grep -i mysql-version /var/cpanel/cpanel.config | cut -d= -f2`
dmysqlv=`ssh $sshargs $ip -p$port 'grep -i mysql-version /var/cpanel/cpanel.config | cut -d= -f2'`
logvars smysqlv dmysqlv
echo "Source: $smysqlv" 
echo "Destination: $dmysqlv" 
if [ $smysqlv == $dmysqlv ]; then  
 ec green "Mysql versions match." 
else 
 ec red "Mysql versions do not match."  
fi

if yesNo "Change remote server's Mysql version?"; then
  mysqlverloop=0
  while [ $mysqlverloop == 0 ]; do #asking for user input, so check for errors.
    echo -e "Please input desired mysql version, either 5.0, 5.1 or 5.5, or n to cancel: " #should really be upgrading to these newer versions, older than 5.0 isn't supported in cpanel 11.36
    read newmysqlver
    case $newmysqlver in
      5.0|5.1|5.5)
        ec green "New server's mysql will be changed to $newmysqlver" 
        mysqlup=1
        mysqlverloop=1;;
      n)
        echo "Canceling mysql version change." 
        mysqlverloop=1;;
      *)
        ec red "Incorrect input, try again." ;;
    esac
  done
  phpvr=`ssh $sshargs $ip -p$port "php -v |head -n1 |cut -d\" \" -f2"`     #get remote php version now since mysql will not allow us to check later.
  logvars phpvr mysqlup newmysqlver smysqlv
fi
sleep 1
}

mysqlextradbcheck() { #find dbs created outside of cpanel, with potential to copy them over.
#skip this fucntion if the username prefix is disabled.
dbprefixvar=`grep database_prefix /var/cpanel/cpanel.config `
logvars dbprefixvar
if ! [ "$dbprefixvar" = "database_prefix=0" ]; then
 echo
 echo "Checking for extra mysql databases..." 
 mkdir -p /home/temp/
 mysql -e 'show databases' |grep -v ^cphulkd |grep -v ^information_schema |grep -v ^eximstats |grep -v ^horde | grep -v leechprotect |grep -v ^modsec |grep -v ^mysql |grep -v ^roundcube |grep -v ^Database | grep -v ^logaholicDB | grep -v ^performance_schema |grep -v '*' > /home/temp/dblist.txt
#still have user_ databases, filter those.
 cp -rp /home/temp/dblist.txt /home/temp/extradbs.txt
 #get all users here, not userlist.
 for user in $allcpusers ; do 
  sed -i -e "/^$user\_/d" /home/temp/extradbs.txt
 done
 #check for non zero filesize
 if [ -s /home/temp/extradbs.txt ];then 
  echo "Extra databases Detected (/home/temp/extradbs.txt):"
  cat /home/temp/extradbs.txt |more 
  #offer to migrate
  if yesNo 'Copy these databases to the new server? (adds to /root/dblist.txt)' ; then
   cat /home/temp/extradbs.txt >> /root/dblist.txt
  fi
  #clear the extra dbs file so it wont interfere in future migrations.
  > /home/temp/extradbs.txt
 fi

else
 echo
 echo "Detected user database prefixing is disabled in WHM.  Might want to set this up on the new server, accounts should migrate fine though."
 e2c  
fi
}

mysqlsymlinkcheck() {
echo
echo "Checking if Mysql was moved to a different location..."
#test if symbolic link
if [ -L /var/lib/mysql ]; then
 ec red "Warning, /var/lib/mysql is a symlink! Grepping for datadir in my.cnf:"
 grep datadir /etc/my.cnf
 echo "You may want to relocate mysql on the new server (if it isnt already) before continuing."
 if yesNo 'Yes to continue, no to exit.'; then
  echo "Continuing..."
 else 
  echo "Exiting."
  exit 0
 fi
else
  echo "Mysql is in the default location."
fi
}

gcccheck() {
echo 'Checking for gcc on new server, because some newer storm servers dont have gcc installed so EA and possibly other things will fail to install.'  
gcccheck=$(ssh $sshargs -p$port $ip "rpm -qa gcc")
logvars gcccheck
if [ "$gcccheck" ]; then
  echo "Gcc found, continuing..." 
else
  echo 'Gcc not found, running "yum install gcc" on remote server. You may have to hit "y" then Enter to install.'  
  sleep 3
  ssh $sshargs -p$port $ip "yum -y install gcc"
fi
}

upcp() {
echo
echo "Checking Cpanel versions..." 
#upcp if local version is higher than remote
cpver=`cat /usr/local/cpanel/version`
rcpver=`ssh $sshargs $ip -p$port "cat /usr/local/cpanel/version"`
if  [[ $cpver > $rcpver ]]; then
  echo "This server has $cpver" 
  echo "Remote server has $rcpver" 
  if yesNo "Run Upcp on remote server?" ; then
    echo "Upcp will be ran when the sync begins." 
    upcp=1

    #ssh $ip -p$port "/scripts/upcp"
    else
    echo "Okay, fine, not running upcp." 
  fi
  else
    echo "Found a higher version of cpanel on remote server, continuing."
fi
logvars cpver rcpver upcp
sleep 1
}

upea() {
echo
echo "Copying over WHM packages and features..."
#Copy Cpanel packages
rsync -aqHe "ssh -p$port" /var/cpanel/packages/ $ip:/var/cpanel/packages/
#Copy features
rsync -aqHe "ssh -p$port" /var/cpanel/features/ $ip:/var/cpanel/features/

#find php versions to judge whether or not ea should be run
phpv=`php -v |head -n1|cut -d" " -f2`
#check if the var is set by the mysql function
if ! [ $phpvr ]; then
 phpvr=`ssh $sshargs $ip -p$port "php -v |head -n1 |cut -d\" \" -f2"`
fi

echo "
Available software versions on remote server:"
ssh $sshargs -p $port $ip "/scripts/easyapache --latest-versions"

if [[ $phpv < 5.3 ]];then 
 ec red "If the php version does not match any of the above, you should manually run EA!"
fi
echo "Source: $phpv"
echo "Dest  : $phpvr"
if yesNo "Want me to run EA on remote server?" ;then
 ea=1
 unset mysqlupcheck
else
 echo 'Just trying to help :/'
 skippedea=1
 if yesNo "Want to copy over the easyapache config to the new server?"; then
   echo 'ok!'
   rsync -aqHe "ssh -p$port" /var/cpanel/easy/apache/ $ip:/var/cpanel/easy/apache/
 fi
fi
sleep 1
}

installprogs(){

proglist="ffmpeg
imagick
memcache
java
upcp
mysqlup
ea
postgres"

echo
ec lightGreen "Heres what we found to install:"
for prog in $proglist; do 
 if [ "${!prog}" ] ; then
  echo "${prog}"
 fi
done
sleep 3
ec lightGreen "Ready to begin installing and start the initial sync!"
e2c

#lwbake,plbake
ec yellow "Installing lwbake and plbake"
ssh $sshargs $ip -p$port "wget -O /scripts/lwbake http://layer3.liquidweb.com/scripts/lwbake;
chmod 700 /scripts/lwbake
wget -O /scripts/plbake http://layer3.liquidweb.com/scripts/plBake/plBake
chmod 700 /scripts/plbake"

#java
if [ "$java" ];then
 ec yellow "Java found, installing..."
 ssh $sshargs $ip -p $port "/scripts/plbake java"
fi

#upcp
if [ $upcp ]; then
 ec yellow "Running Upcp..."
 sleep 2
 ssh $sshargs $ip -p$port "/scripts/upcp"
fi

#mysql
if [ $mysqlup ]; then
 ec yellow "Reinstalling mysql..."
 #mysql 5.5 won't start if safe-show-database and skip-locking are in my.cnf
 remotecpanelversion=` ssh $sshargs $ip -p$port "cat /usr/local/cpanel/version"` #cant set variables in the next script for some reason
 ssh $sshargs $ip -p$port "
 sed -i.bak /mysql-version/d /var/cpanel/cpanel.config ; 
 echo mysql-version=$newmysqlver >> /var/cpanel/cpanel.config ; 
 cp -rp /etc/my.cnf{,.bak} ; 
 if [ $newmysqlver > 5 ]; then
  sed -i -e /safe-show-database/d /etc/my.cnf
  sed -i -e /skip-locking/d /etc/my.cnf
 fi
 cp -rp /var/lib/mysql{,.bak} ; 
if [ $remotecpanelversion > 11.36.0 ]; then
  /usr/local/cpanel/scripts/check_cpanel_rpms --targets=MySQL50,MySQL51,MySQL55 --fix
else
  /scripts/mysqlup --force
fi"
#double check that it is installed and working, or pause
ec yellow "Verifying mysql is started on new server..."
ssh -p $port $ip "service mysql status"
mysqlstatus=$?
if [ $mysqlstatus -gt 0  ];then
  ec lightRed "Mysql failed to start on new server, please check it out..."
  e2c
fi
 echo "Mysql update completed, remember EA will need to be ran."
 mysqlupcheck=1
fi

#Easyapache
if [ $ea ]; then
 ec yellow "Running EA..."
 #copy the EA config
 rsync -aqHe "ssh -p$port" /var/cpanel/easy/apache/ $ip:/var/cpanel/easy/apache/
 ssh $sshargs $ip -p$port "/scripts/easyapache --build"
 unset mysqlupcheck
fi

#postgres
if [ $postgres ]; then
 ec yellow "Installing Postgresql..."
 #use expect to install since it asks for input
 ssh $sshargs $ip -p$port 'cp -rp /var/lib/pgsql{,.bak}
 expect -c "spawn /scripts/installpostgres
expect \"Are you sure you wish to proceed? \"
send \"yes\r\"
expect eof"'
 rsync -avHPe "ssh -p$port" /var/lib/pgsql/data/pg_hba.conf $ip:/var/lib/pgsql/data/
 ssh $sshargs $ip -p$port "/scripts/restartsrv_postgres"
fi

}

acctcopy() {
echo
ec yellow "Packaging cpanel accounts and restoring on remote server..." 
syncstarttime=`date +%F.%T`
#backup userlist variable
if [ -f "$userlistfile" ]; then
  mv $userlistfile $userlistfile.$starttime.bak
fi
echo $userlist > $userlistfile
#setup a counter to track account progress
acct_num=1
total_accts=`echo $userlist | tr ' ' '\n' |wc -l`
> $dnr
mainip=`grep ADDR /etc/wwwacct.conf | awk '{print $2}'`
logvars acct_num total_accts mainip syncstarttime userlist
for user in $userlist; do  
  #account progress
  acct_progress="( $acct_num / $total_accts )"
  userip=`grep ^IP= /var/cpanel/users/$user|cut -d '=' -f2`
  logvars user userip acct_progress
  ec grey "${acct_progress} Packaging $user. "  
  /scripts/pkgacct --skiphomedir $user >> $scriptlog
  #check for location of packaged account ( could be home2 )
  cpmovefiles=`find /home*/ -maxdepth 1 -name cpmove-$user.tar.gz -mtime -1 |head -n1`
  #if more than one cpmove file is found, most likely /home2 is symlinked to /home, they should be the same file, mtime should weed out old copies of the backup. 
  cpmovefilecount=`echo $cpmovefiles | wc -w`
  if [[ $cpmovefilecount -eq 1 ]]; then
    #only 1 file found, continue.
    cpmovefile=$cpmovefiles
    #check if the cpmove file was created
    if [ -f "$cpmovefile" ]; then
      ec brown "${acct_progress} Rsyncing $cpmovefile to $ip:/home/" 
      rsync -aqHlPe "ssh -p$port" $cpmovefile $ip:/home 
      ec yellow "${acct_progress} Restoring account $user" 
      #ipcheck returns one if Restore To Dedicated Ips is seletcted by the user
      #If the user ip doesn't equal the main server ip, then it is is on a dedicated ip
      if [[ $userip != $mainip && $ipcheck = 1 ]] ; then
        restoretodedip=1
      elif [[ $forcededip = 1 ]]; then  #singleuser sync does this, just a way to force it if needed
        restoretodedip=1  
      else
        restoretodedip=0
      fi
      logvars restoretodedip
      #build restorepkg command
      if [[ $restoretodedip = 1 ]]; then
        restorecmd="/scripts/restorepkg --ip=y /home/temp/cpmove-$user.tar.gz"
      else
        restorecmd="/scripts/restorepkg /home/temp/cpmove-$user.tar.gz"
      fi
      logvars restorecmd
      #do the restorepkg command
      ssh $sshargs $ip -p$port "mkdir -p /home/temp ;
      mv /home/cpmove-$user.tar.gz /home/temp/;
      $restorecmd ; 
      mv /home/temp/cpmove-$user.tar.gz /home/" 
      #make sure user restored, rsync homedir
      rsynchomedirs
    else
      #cpmove file wasn't created
      ec lightRed "Did not find cpmove backup file for $user!"
      echo $user >> $dnr
      sleep 1
    fi
  else
    #anything other than 1 cpmove file was found, show error
    ec lightRed "Found $cpmovefilecount cpmove files, dont know which one is good. User $user will not be copied."
    for file in $cpmovefiles; do 
      ls -lah $file;
    done
    echo $user >> $dnr
#    e2c 
  fi
  acct_num=$(( $acct_num+1 ))
done  
syncendtime=`date +%F.%T`
}


rsynchomedirs() { 
#to be ran inside of a for user in userlist loop, from both initial and final syncs
userhomelocal=`grep  ^$user: /etc/passwd  | tail -n1 |cut -d: -f6 `
userhomeremote=`ssh $sshargs $ip -p$port " grep  ^$user: /etc/passwd | tail -n1 |cut -d: -f6"` 
#rsync
echo
#check if cpanel user exists on remote server
ruser=`ssh $sshargs $ip -p$port "cd /var/cpanel/users/; ls $user"`
logvars userhomeremote userhomelocal ruser
if [ "$user" == "$ruser" ]; then 
  #check for non-empty vars
  if [ $userhomelocal ]; then
    if [ $userhomeremote ]; then
     ec white "${acct_progress} Syncing Home directory for $user. $userhomelocal to ${ip}:${userhomeremote}" 
     echo "Please wait..."
     #add update flag for final rsync to add --update flag for rsync, doesn't over write files updated on the new server.
      if [ $rsyncupdate ]; then
        rsyncflags="-avHl --update" 
      else 
        #use for initial sync or overwriting files updated on the newer server.
        rsyncflags="-avHl"
      fi
    rsync $rsyncflags -e  "ssh -p$port" ${userhomelocal}/ ${ip}:${userhomeremote}/ >> $scriptlog 
    else
     #remote fails
     ec lightRed "Remote path for $user not found."
     echo "$user remote path not found: \"$userhomeremote\"" >> /tmp/remotefail.txt
     echo $user >> $dnr 
    fi
  else
    #local fails
    ec lightRed  "Local path for $user not found."
    echo "$user local path not found: \"$userhomelocal\"" >> /tmp/localfail.txt
    echo $user >> $dnr
  fi
else 
 #didn't find user on remote 
 ec lightRed "User $user was not found in /var/cpanel/users on remote server."
 echo $user >> $dnr
fi
echo  
}

didntrestore() {
#loop finished, check for users that didn't restore
if [ -s /tmp/localfail.txt ]; then
 echo
 ec lightRed "Couldnt find users local home directory path:"
 cat /tmp/localfail.txt
 e2c
fi

if [ -s /tmp/remotefail.txt ]; then
 echo
 ec lightRed "Couldnt find users remote directory path:"
 cat /tmp/remotefail.txt
 e2c
fi

if [ -s $dnr ]; then 
 ec lightRed '--did not restore--' 
 cat $dnr 
 ec lightRed '-------------------'
 echo 'You can re-run this script and run the basic sync to restore these users if desired.'
 e2c
fi
}

php3rdpartyapps() {
#apps that add a php module should be installed after EA is ran at the end
#ffmpeg
if [ $ffmpeg ] ; then
 echo "Ffmpeg found, installing on new server..." 
 ssh $sshargs $ip -p$port "/scripts/lwbake ffmpeg-php "
fi

#imagick
if [ $imagick ] ; then
 echo "Imagemagick found, installing on new server..." 
 ssh $sshargs $ip -p$port "
 /scripts/lwbake imagemagick
 /scripts/lwbake imagick
 /scripts/lwbake magickwand"
fi
 
#memcache
if [ "$memcache" ]; then
 echo "Memcache found, installing remotely..." 
 echo
 ssh $sshargs $ip -p$port '
 wget -O /scripts/confmemcached.pl http://layer3.liquidweb.com/scripts/confMemcached/confmemcached.pl
chmod +x /scripts/confmemcached.pl
/scripts/confmemcached.pl --memcached-full
service httpd restart'
fi
}

finalchecks() {

#mailperm, fixquotas
finalfixes

echo
ec yellow "===Final Checks===" 

#3rdparty stuff for which there is no autoinstall for (yet)
if [ "${xcachefound}${eaccelfound}${nginxfound}${lswsfound}" ]; then
ec yellow '3rd party stuff found on the old server!'  
[ "$xcachefound" ] && echo "Xcache: $xcachefound" 
[ "$eaccelfound" ] && echo "Eaccelerator: $eaccelfound" 
[ "$nginxfound" ] && echo "Nginx: $nginxfound" 
[ "$lswsfound" ] && echo "Litespeed: $lswsfound"
ec yellow 'It is up to you to install these. Sorry bro/brosephina!'
e2c
fi

#phpapicheck
if [ $phpapicheck ]; then
 ec lightRed 'The php api check failed, make sure it matches up on the new server!' 
 e2c
fi

#phpmemcheck
if [ $phpmemcheck ]; then
 echo 'Double check the php memory limit on old and new server!' 
fi

#if ea was skipped, show reminder
if [ "${skippedea}${mysqlupcheck}" ]; then
  logvars mysqlupcheck skippedea
  echo "Php versions:"
  echo "Source: $phpv"
  echo "Dest: $phpvr"

  echo "Mysql versions:"
  echo "Source: $smysqlv" 
  echo "Dest: $dmysqlv" 

  ec lightRed 'We detected that Easyapache should be ran on the new server. Please run it now if still needed!'
  e2c
  #fix php handlers if EA was skipped, could fail if php4 was mising before.
  phpapicheck
fi

php3rdpartyapps

if [ -s /etc/remotedomains ]; then
  ec lightRed 'Domains found in /etc/remotedomains, double check their mx settings!' 
  cat /etc/remotedomains
  e2c  
fi


if [ $localcluster ];then
 ec lightRed 'Local DNS clustering was found! May need to setup on the new server.' 
 e2c  
fi

#check for alternate exim ports
eximports=`grep ^daemon_smtp_ports /etc/exim.conf`
eximportsremote=`ssh $sshargs $ip -p$port 'grep daemon_smtp_ports /etc/exim.conf'`
logvars eximportsremote eximports
if [ "$eximports" != "$eximportsremote" ]; then
 ec lightRed 'Alternate smtp ports found!' 
 echo $eximports
 echo 'Set them up within WHM on the new server.'
 e2c
 else
 echo 'Exim ports match!' 
fi

echo "===End Final Checks===" 
}

mysqldumpinitialsync() {
echo
#backup dbdumps folder on new server.
ssh $sshargs $ip -p$port  "test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%R`.bak}"
#also check and backup /home/dbdumps on source server
test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%R`.bak}
#dump backups on current server and copy them over.
mkdir -p /home/dbdumps
if [ -s /root/dblist.txt ]; then
 echo "Found extra databases to dump..." 
 for db in `cat /root/dblist.txt`; do 
  mysqldumpfunction
  ssh $sshargs $ip -p$port "mysqladmin create $db"
 done
 rsync --progress -avHlze "ssh -p$port" /home/dbdumps $ip:/home/
# ssh $ip -p$port "wget migration.sysres.liquidweb.com/dbsync.sh -O /scripts/dbsync.sh; screen -S dbsync -d -m bash /scripts/dbsync.sh" &
dbsyncscript
 ec yellow "Databases restoring in screen dbsync on remote server." 
 ec lightRed "Mysql user permissions will need to be restored to the new server."
 e2c
else
 echo "Did not find /root/dblist.txt" 
fi

}
dbsyncscript() {
cat > /scripts/dbsync.sh <<'EOF'
#!/bin/bash
#ran on remote server to sync dbs.
LOG=/home/dbdumps/dbdumps.log
if [ -d /home/dbdumps ]; then
 cd /home/dbdumps
 echo "Dump dated `date`" > $LOG
 #if the prefinalsyncdb directory exists, rename it
 test -d /home/prefinalsyncdbs && mv /home/prefinalsyncdbs{,.`date +%F.%R`.bak}
 mkdir /home/prefinalsyncdbs
 for each in `ls|grep .sql|cut -d '.' -f1`; do
  echo "dumping $each" |tee -a $LOG
  (mysqldump $each > /home/prefinalsyncdbs/$each.sql) 2>>$LOG
  echo " importing $each" | tee -a $LOG
  (mysql $each < /home/dbdumps/$each.sql)  2>>$LOG
 done
 echo "Finished, hit a key to see the log."
 read
 less $LOG
else
 echo "/home/dbdumps not found"
 read
fi
EOF
rsync -aHPe "ssh -p$port" /scripts/dbsync.sh $ip:/scripts/
ssh $sshargs $ip -p$port "screen -S dbsync -d -m bash /scripts/dbsync.sh" &
}

mysqldbfinalsync() {
echo "Dumping the databases..." 
test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%T`.bak}
mkdir -p /home/dbdumps
ssh $sshargs $ip -p$port 'test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%T`.bak}'
mysqldumpver=`mysqldump --version |cut -d" " -f6 |cut -d, -f1`
#dump user dbs
for each in $userlist; do 
  for db in `mysql -e 'show databases' | grep "^$each\_"`; do 
   mysqldumpfunction
 done  
done
#dump from list of dbs
if [ -s /root/dblist.txt ]; then
 for db in `cat /root/dblist.txt`; do 
  mysqldumpfunction
 done
fi

#copy dbs over
rsync --progress -avHlze "ssh -p$port" /home/dbdumps $ip:/home/

#dbsyncin screen madness
#ssh $ip -p$port "wget migration.sysres.liquidweb.com/dbsync.sh -O /scripts/dbsync.sh; screen -S dbsync -d -m bash /scripts/dbsync.sh" &
dbsyncscript
}

mysqldumpfunction() {
#should be run inside a loop, where db is your database name
echo "Dumping $db" | tee -a $mysqldumplog; 
#mysqldump log-error doesn't work for versions less than 5.0.42 
if [[ $mysqldumpver < 5.0.42 ]]; then 
 mysqldump --add-drop-table $db > /home/dbdumps/$db.sql
else
 mysqldump --force --add-drop-table --log-error=${mysqldumplog} $db > /home/dbdumps/$db.sql  
fi
}

finalsync() {
echo
echo "Running final sync..." 
finalsynccheck=1
#check for previous migration
if [ -s $userlistfile ]; then 
 echo "Found $userlistfile." 
 userlist=`cat $userlistfile`
 echo "$userlist" 
 if yesNo "Are these users correct?"; then
  echo "Continuing." 
 else
  if yesNo "Would you like to migrate all users?"; then
   echo "Syncing all users." 
   userlist=$allcpusers
  else
   echo "Please edit $userlistfile with the users you wish to migrate and rerun the script."
   exit 0
  fi
 fi 
else
 echo "Syncing all users." 
 userlist=$allcpusers
 echo "$userlist" 
fi
sleep 3
getip

if yesNo 'Stop services for final sync?'; then
 stopservices=1
 if yesNo 'Restart services after sync?'; then
  restartservices=1
 fi
fi

if yesNo 'Copy /var/named/*.db over from new server? Will backup current directory. Dont do this unless migrating all users!' ;then 
 copydns=1
fi

#rsyncupdate
if yesNo 'Use --update flag for final rsync? If files were updated on the destination server they wont be overwritten'; then
 rsyncupdate=1
fi

echo "Press enter to begin final sync..."
read
syncstarttime=`date +%F.%T`

rsyncupgrade

if [ $stopservices ]; then
  echo "Stopping Services..." 
  [ -s /etc/init.d/chkservd ] && /etc/init.d/chkservd stop
  /usr/local/cpanel/bin/tailwatchd --disable=Cpanel::TailWatch::ChkServd
  /etc/init.d/httpd stop
  /etc/init.d/exim stop
  /etc/init.d/cpanel stop
else
 echo "Not stopping services." 
fi

mysqldbfinalsync

acct_num=1
total_accts=`echo $userlist | tr ' ' '\n' |wc -l`
for user in $userlist; do 
  acct_progress="( $acct_num / $total_accts )"
  logvars acct_num total_accts user acct_progress
  rsynchomedirs
  acct_num=$(( $acct_num+1 ))
done

#packages, spool data
rsync -aqHPe "ssh -p$port" /var/cpanel/packages $ip:/var/cpanel/
#damn them who add cronjobs after initial sync! also not supposed to do this on cent6 for some reason
#rsync -aqHPe "ssh -p$port" /var/spool $ip:/var/


#mailperm, fixquotas
finalfixes

#copy zone files over from new server, if selected.
if [ $copydns ]; then 
 echo "Copying zone files over from new server..."
 rsync -aqHPe "ssh -p$port" /var/named/ /var/named.`date +%F.%T`/
 rsync -aqHPe "ssh -p$port" $ip:/var/named/*.db /var/named/
 sed -i -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' /var/named/*.db
 rndc reload 
 #for the one time i encountered NSD
 nsdcheck=`ps aux |grep nsd |grep -v grep`
 if [ "$nsdcheck" ]; then
  echo "Nsd found, reloading" 
  nsdc rebuild
  nsdc reload
 fi
fi

#restart services
if [ $restartservices ]; then
 echo "Restarting services..." 
 [ -s /etc/init.d/chkservd ] && /etc/init.d/chkservd start
 /etc/init.d/httpd start
 /etc/init.d/mysql start
 /etc/init.d/exim start
 /etc/init.d/cpanel start
 /usr/local/cpanel/bin/tailwatchd --enable=Cpanel::TailWatch::ChkServd
else
 echo "Skipping restart of services..."
fi

syncendtime=`date +%F.%T`

#give cpanel time to spam to screen
sleep 10
echo
#display mysqldump errors
if [ -s /tmp/mysqldump.log ]; then
 echo 
 echo 'Errors detected during mysqldumps:' 
 cat /tmp/mysqldump.log 
 echo "End of errors from /tmp/mysqldump.log." 
 sleep 1
fi

postmigrationhook

echo "=Actions taken:="
if [ $stopservices ]; then 
 echo "Stopped services"
 if [ $restartservices ];then echo "Restarted services"; else echo "Didnt restart services"; fi
fi
[ $copydns ] && echo "DNS was copied over from new server."
echo "============"
echo
if yesNo "Remove SSH key from new server?"; then
  ssh $sshargs -p${port} root@$ip "
  mv ~/.ssh/authorized_keys{,.initialsync.$starttime}; 
  if [ -f ~/.ssh/authorized_keys.initialsyncbak ]; then 
    cp -rp ~/.ssh/authorized_keys{.initialsyncbak,}; 
  fi"
fi

echo 'Final sync complete, check the screen "dbsync" on the remote server to ensure all databases imported correctly.'
}

finalfixes() {
#in final sync and initial sync
#fix mail permissisons
echo "Fixing mail permissions on new server."
ssh $sshargs $ip -p$port "screen -S mailperm -d -m /scripts/mailperm" &

#fix quotas
echo "Starting a screen to fix cpanel quotas."
ssh $sshargs $ip -p$port "screen -S fixquotas -d -m /scripts/fixquotas" &
}

rsyncupgrade () {
#Optional function to upgrade rsync to V 3.0
#rsync 3+ supports the --log-file option
#get current rsync version
RSYNCVERSION=`rsync --version |head -n1 |awk '{print $3}'`
rsyncmajor=`echo $RSYNCVERSION |cut -d. -f1`
if [ "$rsyncmajor" -lt 3 ]; then
 echo "Updating rsync..." 
 LOCALCENT=`cat /etc/redhat-release |awk '{print $3}'|cut -d '.' -f1`
 LOCALARCH=`uname -i`
 rpm -Uvh http://migration.sysres.liquidweb.com//rsync/rsync-3.0.0-1.el$LOCALCENT.rf.$LOCALARCH.rpm
else
 echo "Rsync up to date." 
fi
logvars LOCALARCH LOCALCENT RSYNCVERSION rsyncmajor
}

rubygems() {
echo 
echo "Copying ruby gems over to new server." 
gem list | tail -n+4 | awk '{print $1}' > /root/gemlist.txt
echo "gemlist:" 
cat /root/gemlist.txt 
echo 'cat /root/gemlist.txt | xargs gem install' > /root/geminstall.sh
chmod +x /root/geminstall.sh
rsync -avHPe "ssh -p$port" /root/geminstall.sh /root/gemlist.txt $ip:/root/
ssh -p$port $ip "screen -S geminstall -d -m bash /root/geminstall.sh" &
}

cpbackupcheck() {
echo "
Checking if cpanel backups are enabled on new server." 
backupacctssetting=`ssh $sshargs -p$port $ip "grep ^BACKUPACCTS /etc/cpbackup.conf" | awk '{print $2}' ` 
backupenablesetting=`ssh $sshargs -p$port $ip "grep ^BACKUPENABLE /etc/cpbackup.conf" | awk '{print $2}' `
logvars backupenablesetting backupacctssetting
if [ $backupacctssetting = "yes" ]; then 
  #backupaccts is true, check for backupenable also
  if [ $backupenablesetting = "yes" ]; then
    #backupenable is also true
    echo "Backups are enabled" 
  else
    cpbackupenable
  fi
else
  cpbackupenable
fi
}

cpbackupenable(){
echo "Cpanel backups are disabled on $ip" 
if yesNo "Do you want to enable backups on the remote server?"; then
    ssh $sshargs -p$port $ip "sed -i.syncbak -e 's/^\(BACKUPACCTS\).*/\1 yes/g' -e 's/^\(BACKUPENABLE\).*/\1 yes/g' /etc/cpbackup.conf"
fi
}

logvars() {
  # make it easy to log variables
  #logvars variablename var2 var3
for i in $*; do
  echo "$i"="${!i}" >> $scriptlog
done
}

matchpear() {
echo
echo "Matching PEAR packages..."
pear list | egrep [0-9]{1}.[0-9]{1} | awk '{print$1}' > /root/pearlist.txt
scp -P$port /root/pearlist.txt root@$ip:/root/
ssh $sshargs $ip -p$port "cat /root/pearlist.txt |xargs pear install $pear"
}

modsecmatch() { #not used... yet
  #centos=`cat /etc/redhat-release |cut -d" " -f3`
  #check for installed modsec version
  #if 5 or less, lpyum is used, 6 uses regular yum
  #if [[ $centos -lt 6 ]]; then

  #just use rpm to check
  modsec=`rpm -qa --queryformat "[%{name}\n]" lp-modsec*` #lp-modsec2-rules
  #if rpm finds multiple installed modsec?
  echo "Modsec version $modsec found."
  #check remote server for modsec version
  modsecremote=`ssh $sshargs -p$port $ip 'rpm -qa --queryformat "[%{name}\n]" lp-modsec*' `
  #turtle-rules files: /usr/local/apache/conf/turtle-rules/modsec/00_asl_whitelist.conf
  #/usr/local/apache/conf/modsec/lw_whitelist.conf /usr/local/apache/conf/modsec2/lw_whitelist.conf
  

  modseccopy() {
    #install on remote server?    
    ssh $sshargs -p$port $ip "cp -rp $modsecwlist{,.initialsync.$starttime.bak} "
    rsync -avHP -e "ssh -p$port" $modsecwlist $ip:$modsecwlist
  }
  case $modsec in 
    lp-modsec2-rules) 
      modsecwlist="/usr/local/apache/conf/modsec2/whitelist.conf"
      modseccopy
      ;;
    lp-modsec-rules)
      modsecwlist="/usr/local/apache/conf/modsec/whitelist.conf"
      modseccopy
      ;;
    *)
      echo "Modsec case not found"
      ;;
  esac
}

postmigrationhook() {
  #run a custom script once the migration is complete:
  echo "Checking for post migration scripts to run."
  postmigscript="/root/postmigration.sh"
  if [ -f "$postmigscript" ]; then
    if yesNo "Found $postmigscript, run it?"; then
      bash $postmigscript 
      echo "Finished $postmigscript"
    fi
  else 
    echo "None found."
  fi
}

control_c() {
  #if user hits control-c 
  echo
  ec lightRed "Control-C pushed, exiting..."
  #if ip variable exists, and if our key exists on the remote server, clean it up.
  if [ -f "/root/dest.ip.txt" ]; then
    #variables from main script will not transfer over for some reason, so create new variables.
    ip=`cat /root/dest.ip.txt`
    port=`cat /root/dest.port.txt`
    #test if sshkey is working, ignore errors and don't prompt
    ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no $ip -p$port "echo Found ssh key on remote server, removing..."
    sshtest=$?
    #test exit value of ssh command.
    if [[ "$sshtest" == 0 ]]; then
      ssh $sshargs -p${port} root@$ip "
mv ~/.ssh/authorized_keys{,.initialsync.$starttime}; 
if [ -f ~/.ssh/authorized_keys.initialsyncbak ]; then 
    cp -rp ~/.ssh/authorized_keys{.initialsyncbak,}; 
fi"
    ec lightRed "Clean up any data/users accidentally transferred to remote server! This script will not do it for you."
    fi
  fi
  ec yellow "Bye!"
  exit 10
}


trap control_c SIGINT

#run main last so all functions are loaded
main | logit
