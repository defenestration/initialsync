#!/bin/bash
#initalsync by abrevick@liquidweb.com
ver="Nov17 2011"
#todo: 
# match other php vars?   
# php open_basedir
# add home2 support, (grep etc passwd for user home)
# add -t -n to ssh to make it quiet
# install postgres if found on old 
# copy apf/csf allow configs?
# copy modsec configs? or at least display it.
# verify all users against current users for final sync.
#modsec rules
# check for dns clustering, the folder /var/cpanel/cluster will exist. http://www.thecpaneladmin.com/cpanel-command-line-dns-cluster-management/
#check for remote mysql server, /root/.my.cnf

#userlist=`/bin/ls -A /var/cpanel/users`
dnr=/home/didnotrestore.txt
[ -s $dnr ] && dnrusers=`cat $dnr`
starttime=`date +%F.%T`

yesNo(){ #generic yesNo function
#repeat if yes or no option not valid
while true; do
#$* read ever parameter giving to the yesNo function which will be the message
 echo -n "$* (Y/N)? "
 #junk holds the extra parameters yn holds the first parameters
 read yn junk
 #check for difference cases
 case $yn in
  yes|Yes|YES|y|Y)
    return 0  ;;
  no|No|n|N|NO)
    return 1  ;;
  *) 
    echo "Please enter y or n."
 esac
done    
#usage:
#if yesNo 'do you want to continue?' ; then
#    echo 'You choose to continue'
#else
#    echo 'You choose not to continue'
#fi
}

menuoptions(){
echo "Version: $ver"
echo "Main Menu:"
echo "Select the migration type:
1) Full sync (all users, matching versions as much as possible)
2) Basic sync (all users, no version matching) 
3) Single user sync (no version matching)
4) User list sync (no version matching)
5) Full sync - keeping old ips (/etc/ips is copied over)
9) Final sync (from /root/userlist.txt or all users)
0) Quit"
}

main() {
#menu options
mainloop=0
while [ $mainloop == 0 ] ; do
 clear
 menuoptions
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
  keepipsync
  mainloop=1 ;;
 9)
  finalsync
  mainloop=1 ;;
 0) 
  echo "Bye..."; exit 0 ;;
 *)  
   echo "Not a valid choice. Also, the game."; sleep 2 ; clear 
 esac
done
echo
echo "Started at $starttime"
echo "Sync started at $syncstarttime"
echo "Sync finished at $syncendtime"
echo "Finished at `date +%F.%T`"
echo 'Done!'
exit 0
}

#sync types
singleuser() {
echo
echo "Single user sync."
singleuserloop=0
while [ $singleuserloop == 0 ]; do 
 echo -n "Input name of the user to migrate:"
 read userlist
 #check for error
 sucheck=`/bin/ls -A /var/cpanel/users | grep ^${userlist}$`
 if  [[ $sucheck = $userlist ]]; then
  echo "Found $userlist, restoring..."
  singleuserloop=1
  basicsync
 else
  echo "Could not find $userlist."
 fi
done
}

listsync() {
echo
echo "List sync."
#search for /root/users.txt and /home/users.txt
if [ -s /root/userlist.txt ]; then
 echo "Found /root/userlist.txt"
 sleep 3
 userlist=`cat /root/userlist.txt`
 echo "$userlist"
 basicsync
elif [ -s /home/users.txt ]; then 
 echo "Found /home/users.txt"
 sleep 3
 userlist=` cat /home/users.txt`
 echo "$userlist"
 basicsync
elif [ -s /root/users.txt ]; then
 echo "found /root/users.txt"
 userlist=`cat /root/users.txt`
 sleep 3
 basicsync
else 
 echo "Did not find users.txt in /root or /home"
 sleep 3
fi
}

basicsync(){
echo
echo "Basic Sync started"
presync
copyaccounts
}

fullsync() {
echo
echo "Full sync started"
#check versions,  run ea, upcp, match php versions, lots of good stuff
presync
versionmatching
copyaccounts
}

keepipsync() {
echo
echo "Sync keeping old dedicated ips."
keepoldips=1
fullsync
}

#Main sync procecures
presync() {
echo "Running Pre-sync functions..."
#get ips and such
if ! [ $singleuserloop ];then 
 dnrcheck     #userlist is defined here
fi
dnscheck     #lets you view current dns
lowerttls    
getip        #asks for ip or checks a file to confirm destination
accountcheck #if conflicting accounts are found, asks
dedipcheck  #asks if an equal amount of ips are not found
}
versionmatching() {
echo "Running version matching..."
upcp
phpmemcheck 
thirdparty   
mysqlcheck 
upea
phpapicheck  # to be ran after ea so php4 can be compiled in if needed
}
copyaccounts() {
echo "Starting account copying functions..."
acctcopy
didntrestore
hostsgen       #halts
finalchecks
}
##

dnrcheck() { 
#define users
#check and suggest to restore accounts from a previous failed migration
#dnrusers is defined at the start
echo
echo "Checking for previous failed migration."
if [ "$dnrusers" ];then
 echo
 echo "Found users from failed migration in $dnr"
 echo $dnrusers
 ls -l $dnr
 echo
 if yesNo 'Want to restore these failed users only?' ;then
  userlist=$dnrusers
  cp -rpf ${dnr}{,.bak}
  > $dnr
 else 
  echo "Okay, selecting all users for migration."
  userlist=`/bin/ls -A /var/cpanel/users`	
 fi
 else
  echo "No previous migration found, migrating all users."
  userlist=`/bin/ls -A /var/cpanel/users`
fi
echo "Users slated for migration:"
echo $userlist
sleep 2
}

hostsgen() {
echo
echo "Generating sample for hosts file..."
echo
ssh $ip -p$port "wget -O /scripts/hosts.sh http://migration.sysres.liquidweb.com/hosts.sh ; bash /scripts/hosts.sh" 
echo 
sleep 2
}

dnscheck() {
echo
echo "Checking Current dns..."
if [ -f /root/dns.txt ]; then
 echo "Found /root/dns.txt"
 sleep 3
 cat /root/dns.txt | sort -n +3 -2 
else
 domainlist=`cat /etc/userdomains |sort | sed -e 's/:.*//' |grep -v \*`
 for each in $domainlist; do echo $each\ `dig @8.8.8.8 NS +short $each |sed 's/\.$//g'`\ `dig @8.8.8.8 +short $each` ;done | grep -v \ \ | column -t > /root/dns.txt
 cat /root/dns.txt | sort -n +3 -2 
fi
echo "Enter to continue..."
read
}

lowerttls() {
echo
echo "Lowering TTLs..."
#lower ttls
sed -i.lwbak -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' /var/named/*.db
rndc reload
}

getip() {
echo
echo "Getting Ip for destination server..."
#check for previous migration, just in case.
ipfile=/root/dest.ip.txt
if [ -f $ipfile ]; then
 ip=`cat $ipfile`
 echo
 echo "Ip from previous migration found `echo $ip`" 
 getport
 echo "Testing connetion to remote server..."
 echo
 ssh $ip -p$port "cat /etc/hosts |tail -n3 ; ifconfig eth0 |head -n2"
 echo
 echo "Test complete."
 echo
 if yesNo "Is $ip the server you want? Check above output for a successful connection.  Otherwise enter No to input new ip." ;then
  echo "Ok, continuing with $ip"
  sshkeygen
 else
  ipask 
 fi
else
 ipask
fi
sleep 1
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
 echo "Previous Ssh port found ($port)."
else 
 echo -n "SSH Port [22]: "
 read port
fi
if [ -z $port ]; then
 echo "No port given, assuming 22"
 port=22
fi
echo $port > /root/dest.port.txt
sleep 1

}

sshkeygen() {
echo
echo "Generating SSH keys"
if ! [ -f ~/.ssh/id_rsa ]; then
 ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
fi
cat ~/.ssh/id_rsa.pub | ssh $ip -p$port "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
ssh $ip -p$port "echo \'Connected!\';  cat /etc/hosts| grep $ip " 
}
 

accountcheck() { #check for users with the same name on each server:
echo
echo "Comparing accounts with destination server"
for user in $userlist ; do  ssh -qt $ip -p$port " if [ -f /var/cpanel/users/$user ]; then echo $user;fi"  ; done > /root/userexists.txt
#check for userexists.txt greater than 0
if [ -s /root/userexists.txt ]; then
 echo 'Accounts that conflict with the destination server.'
 cat /root/userexists.txt
 if yesNo "Y to continue, N to exit."; then
  echo "Continuing..."
 else
  echo "Exiting..."
  exit 0
 fi
fi
}

dedipcheck() { #check for same amount of dedicated ips
echo
echo "Checking for dedicated Ips."
if [ $keepoldips ];then 
 echo "Keeping old ips, copying ips file over."
 ssh $ip -p$port "cp -rp /etc/ips{,.bak}"
 rsync -avHPe "ssh -p${port}" /etc/ips $ip:/etc/
 ssh $ip -p$port "/etc/init.d/ipaliases restart"
fi
sourceipcount=`cat /etc/ips | grep ^[0-9] | wc -l`
destipcount=`ssh $ip -p$port "cat /etc/ips |grep ^[0-9] | wc -l"`
if (( $sourceipcount <= $destipcount ));then
 echo "Source server has less or equal ips compared to destination, continuing."
 ipcheck=1
else
 ipcheck=0
 echo 
 echo "Not enough dedicated IPs found on destination server ($destipcount) when compared to source server ($sourceipcount)."
 echo "If you are sure the server isn't using all its IPs for accounts you can override the Ip check. Otherwise answer No to put all sites on the main shared IP."
 if yesNo "Override IP check?" ;then
  ipcheck=1
  echo "Restoring to dedicated ips."
 else
  ipcheck=0
  echo "Restoring to main shared ip."
 fi
fi
sleep 1

}

phpapicheck() { #run after EA so php4 can be supported
echo
echo "Matching php handlers..."
phpver=`/usr/local/cpanel/bin/rebuild_phpconf --current |grep ^DEFAULT\ PHP |awk '{print $3}'`
php4sapi=`/usr/local/cpanel/bin/rebuild_phpconf --current |grep ^PHP4\ SAPI |awk '{print $3}'`
php5sapi=`/usr/local/cpanel/bin/rebuild_phpconf --current |grep ^PHP5\ SAPI |awk '{print $3}'`
phpsuexec=`/usr/local/cpanel/bin/rebuild_phpconf --current |grep ^SUEXEC |awk '{print $2}'`
#check if phpver is 4 or 5, old EA versions will fail the rebuild_phpconf command
case $phpver in
[45]) ssh $ip -p$port "/usr/local/cpanel/bin/rebuild_phpconf --current > /tmp/phpconf.`date +%F.%T`.txt ;/usr/local/cpanel/bin/rebuild_phpconf $phpver $php4sapi $php5sapi $phpsuexec " ;;
*)  echo "Got unexpected output from /usr/local/cpnael/bin/rebuild_phpconf --current, skipping..." 
    phpapicheck=1 ;;
esac

}

phpmemcheck(){
echo
echo "Checking php memory limit..."
phpmem=`php -i |grep memory_limit |cut -d" " -f3`
rphpmem=`ssh $ip -p$port 'php -i |grep memory_limit |cut -d" " -f3'`
if [ $phpmem ]; then
 if [ $rphpmem ]; then
  if [[ $phpmem != $rphpmem ]]; then
   phpmemcmd=`echo 'sed -i '\''s/\(memory_limit\ =\ \)[0-9]*M/\1'$phpmem'/'\'' /usr/local/lib/php.ini'`
   ssh $ip -p$port "cp -rp /usr/local/lib/php.ini{,.bak} ; $phpmemcmd ; service httpd restart" 
  else
   echo "Old memorylimit $phpmem matches new $rphpmem, skipping..."
   phpmemcheck=1
  fi
 else 
  echo "Remote php memory_limit not found."
  phpmemcheck=1
 fi
else
 echo "Local php memory_limit not found."
 phpmemcheck=1
fi

}

thirdparty() {
echo
echo "Checking for 3rd party apps..."
#check for 3rd party stuff
echo "Installing lwbake"
ssh $ip -p$port "wget -O /scripts/lwbake http://layer3.liquidweb.com/scripts/lwbake;
chmod 700 /scripts/lwbake"
#Check for ffmpeg
if [ `which ffmpeg 2>1 /dev/null` ] ; then
 echo "Ffmpeg found, installing on new server..."
 ssh $ip -p$port "/scripts/lwbake ffmpeg-php "
fi
#Check for Imagemagick
if [ `which convert 2>1 /dev/null` ] ; then 
 echo "Imagemagick found, installing on new server..."
 ssh $ip -p$port "
 /scripts/lwbake imagemagick
 /scripts/lwbake imagick
 /scripts/lwbake magickwand
 /scripts/lwbake perl-imagemagick"
fi
echo

#memcache
memcache=`ps aux | grep -e 'memcache' | grep -v grep | tail -n1 `
if [ "$memcache" ]; then
 echo "Memcache found, installing remotely..."
 echo
 ssh $ip -p$port'
 wget -O /scripts/confmemcached.pl http://layer3.liquidweb.com/scripts/confMemcached/confmemcached.pl
chmod +x /scripts/confmemcached.pl
/scripts/confmemcached.pl --memcached-full
service httpd restart'
fi

#other stuff, say if it needs to be installed at the end
xcachefound=`ps aux | grep -e 'xcache' | grep -v grep | tail -n1`
eaccelfound=`ps aux | grep -e 'eaccelerator' | grep -v grep |tail -n1`
nginxfound=`ps aux | grep  -e 'nginx' |grep -v grep| tail -n1`
postgresfound=`ps aux |grep -e 'postgres' |grep -v grep |tail -n1`

}

mysqlcheck() {
#mysql
echo
echo "Checking mysql versions..."
smysqlv=`grep -i mysql-version /var/cpanel/cpanel.config | cut -d= -f2`
dmysqlv=`ssh $ip -p$port 'grep -i mysql-version /var/cpanel/cpanel.config | cut -d= -f2'`
echo "Source: $smysqlv"
echo "Destination: $dmysqlv"
if [ $smysqlv == $dmysqlv ]; then  
 echo "Mysql versions match."; 
else 
 echo "Mysql versions do not match."
 if yesNo "Update remote server's mysql version to $smysqlv?" ; then
  #get remote php version now since mysql will now allow us to check later.
  phpvr=`ssh $ip -p$port "php -v |head -n1 |cut -d\" \" -f2"`
  echo "Updating mysql..."
  ssh $ip -p$port "sed -i.bak /mysql-version/d /var/cpanel/cpanel.config ; echo mysql-version=$smysqlv >> /var/cpanel/cpanel.config ; cp -rp /var/lib/mysql{,.bak} ; /scripts/mysqlup --force"
  echo "Mysql update completed, remember EA will need to be ran."
  mysqlupcheck=1
 else
  echo "Not updating mysql."
 fi
fi
sleep 1
}

upcp() {
echo
echo "Checking Cpanel versions..."
#upcp if local version is higher than remote
cpver=`cat /usr/local/cpanel/version`
rcpver=`ssh $ip -p$port "cat /usr/local/cpanel/version"`
if  [[ $cpver > $rcpver ]]; then
 echo "This server has $cpver"
 echo "Remote server has $rcpver"
 if yesNo "Run Upcp on remote server?" ; then
  echo "Running upcp..."
  ssh $ip -p$port "/scripts/upcp"
 else
  echo "Okay, fine, not running upcp." 
 fi
 else
 echo "Found a higher version of cpanel on remote server, carrying on."
fi
sleep 1
}

upea() {
echo
echo "Prepping for EasyApache..."
#EA 
#copy the EA config
rsync -avHle "ssh -p$port" /var/cpanel/easy/apache/ $ip:/var/cpanel/easy/apache/
#Copy Cpanel packages
rsync -avHle "ssh -p$port" /var/cpanel/packages/ $ip:/var/cpanel/packages/
#Copy features
rsync -avHle "ssh -p$port" /var/cpanel/features/ $ip:/var/cpanel/features/
#find php versions to judge whether or not ea should be run
phpv=`php -v |head -n1|cut -d" " -f2`
#check if the var is set by the mysql function
if ! [ $phpvr ]; then
 phpvr=`ssh $ip -p$port "php -v |head -n1 |cut -d\" \" -f2"`
fi
if [[ $phpv < 5.3 ]];then 
 echo "If the php version should stay 5.2, you should manually run EA."
fi
echo "Source: $phpv"
echo "Dest: $phpvr"
if yesNo "Want me to run EA on remote server?" ;then
 ssh $ip -p$port "/scripts/easyapache --build"
 unset mysqlupcheck
else
 echo 'Just trying to help :/'
 skippedea=1
fi
sleep 1
}

acctcopy() {
echo
echo "Packaging cpanel accounts and restoring on remote server..."
syncstarttime=`date +%F.%T`
#backup userlist variable
echo $userlist > /root/userlist.txt
#pack/send restore loop
> $dnr
mainip=`grep ADDR /etc/wwwacct.conf | awk '{print $2}'`
for user in $userlist; do 
 userip=`grep ^IP= /var/cpanel/users/$user|cut -d '=' -f2`
 /scripts/pkgacct --skiphomedir $user 
 rsync -avHlPe "ssh -p$port" /home*/cpmove-$user.tar.gz $ip:/home 
#check for not enough ips
 echo "main ip:$mainip"
 echo "user ip:$userip"
 echo "ipcheck: $ipcheck"

#If keeping old ips.
 if [[ $keepoldips ]]; then
  ssh $ip -p$port "mkdir -p /home/temp; 
  mv /home/cpmove-$user.tar.gz /home/temp/;
  if [[ $userip != $mainip ]]; then 
   /scripts/restorepkg --ip=$userip /home/temp/cpmove-$user.tar.gz ; 
  else
   /scripts/restorepkg /home/temp/cpmove-$user.tar.gz ; 
  fi
  mv /home/temp/cpmove-$user.tar.gz /home/" 
  
 else
  #normal restore
  if [[ $ipcheck = 1 ]] ; then
  #restore to dedicated ips
   ssh $ip -p$port "mkdir -p /home/temp; 
   mv /home/cpmove-$user.tar.gz /home/temp/;
   if [[ $userip != $mainip ]]; then 
    /scripts/restorepkg --ip=y /home/temp/cpmove-$user.tar.gz ; 
   else
    /scripts/restorepkg /home/temp/cpmove-$user.tar.gz ; 
   fi
   mv /home/temp/cpmove-$user.tar.gz /home/" 
  else
   #restore everything to main ip
   ssh $ip -p$port "mkdir -p /home/temp; 
   mv /home/cpmove-$user.tar.gz /home/temp/;
   /scripts/restorepkg /home/temp/cpmove-$user.tar.gz ; 
   mv /home/temp/cpmove-$user.tar.gz /home/" 
  fi
 fi
 
#make sure user restored, rsync homedir
 rsynchomedirs
 
done  
syncendtime=`date +%F.%T`
}

rsynchomedirs() { #to be ran inside of a for user in userlist loop
echo
echo "Syncing Home directory for $user."
ruser=`ssh -q $ip -p$port "cd /var/cpanel/users/; ls $user"`
 if [ "$user" == "$ruser" ]; then 
  rsync -avHlPe "ssh -p$port" /home*/$user $ip:/home/ 
 else 
   echo $user >> $dnr
 fi
}

didntrestore() {
#loop finished, check for users that didn't restore
if [ -s $dnr ]; then 
 echo '--did not restore--'
 cat $dnr
 echo '-------------------'
 echo 'You can re-run this script and run the basic sync to restore these users if desired.'
 echo 'Press enter to continue...'
 read
fi
}

finalchecks() {
echo
echo "===Final Checks==="
#3rdparty stuff
if [ "${xcachefound}${eaccelfound}${nginxfound}${postgresfound}" ]; then
echo 'Install any found 3rd party stuff on the new server!'
[ "$xcachefound" ] && echo "Xcache: $xcachefound"
[ "$eaccelfound" ] && echo "Eaccelerator: $eaccelfound"
[ "$nginxfound" ] && echo "Nginx: $nginxfound"
[ "$postgresfound" ] && echo "Postgres: $postgresfound"
#pause here
sleep 3
fi

#phpapicheck
if [ $phpapicheck ]; then
 echo 'The php api check failed, make sure it matches up on the new server!'
fi

#phpmemcheck
if [ $phpmemcheck ]; then
 echo 'Double check the php memory limit on old and new server!'
fi

#if ea was skipped, show reminder
if [ "${skippedea}${mysqlupcheck}" ]; then
 
 echo 'Remeber to run EasyApache on new server! (press enter to continue)'
 read
fi

if [ -s /etc/remotedomains ]; then
 echo 'Domains found in /etc/remotedomains, double check their mx settings!'
 cat /etc/remotedomains
 echo 'Press enter to continue...'
 read
fi

#check for alternate exim ports
eximcheck=`grep ^daemon_smtp_ports /etc/exim.conf`
eximexpect="daemon_smtp_ports = 25 : 465"
if [ "$eximcheck" != "$eximexpect" ]; then
 echo 'Alternate smtp ports found!'
 echo $eximcheck
 echo 'Set them up within WHM on the new server. (enter to continue)'
 read
fi
 
echo "===End Final Checks==="
echo "Enter to continue"
read
}


finalsync() {
echo
echo "Running final sync..."

#check for previous migration
if [ -s /root/userlist.txt ]; then 
 echo "Found /root/userlist.txt, using as userlist"
 userlist=`cat /root/userlist.txt`
 echo "$userlist"
else
 echo "Syncing all users."
 userlist=`/bin/ls -A /var/cpanel/users`
 echo "$userlist"
fi
sleep 3
getip

if yesNo 'Stop services for final sync?'; then
 stopservices=1
fi

echo "Press enter to begin final sync..."
read

if [ $stopservices ]; then
echo "Stopping Services..."
/etc/init.d/chkservd stop
/usr/local/cpanel/bin/tailwatchd --disable=Cpanel::TailWatch::ChkServd
/etc/init.d/httpd stop
/etc/init.d/exim stop
/etc/init.d/cpanel stop
else
 echo "Not stopping services."
fi

echo "Dumping the databases..."
test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%T`.bak}
mkdir -p /home/dbdumps
ssh $ip -p$port 'test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%T`.bak} '
for each in $userlist; do 
  for db in `mysql -e 'show databases' | grep "^$each\_"`; do 
   echo "Dumping $db"; 
   #mysqldump log-error doesn't work for versions less than 5.0.42 
   mysqldumpver=`mysqldump --version |cut -d" " -f6 |cut -d, -f1`
   if [[ $mysqldumpver < 5.0.42 ]]; then 
    mysqldump --add-drop-table $db > /home/dbdumps/$db.sql
   else
    mysqldump --force --add-drop-table --log-error=/tmp/mysqldump.log $db > /home/dbdumps/$db.sql  
   fi
 done  
done

#copy dbs over
rsync --progress -avHlze "ssh -p$port" /home/dbdumps $ip:/home/

#dbsyncin screen madness
ssh $ip -p$port "wget migration.sysres.liquidweb.com/dbsync.sh -O /tmp/dbsync.sh; screen -S dbsync -d -m bash /tmp/dbsync.sh" &

for user in $userlist; do 
 rsynchomedirs
done

#added to fix email perms
chgrp mail /home/$user/etc/*/shadow

#packages, spool data
rsync -avHPe "ssh -p$port" /var/cpanel/packages $ip:/var/cpanel/
rsync -ave "ssh -p$port" /var/spool $ip:/var/


#restart services
if [ $stopservices ]; then
echo "Restarting services..."
/etc/init.d/chkservd start
/etc/init.d/httpd start
/etc/init.d/mysql start
/etc/init.d/exim start
/etc/init.d/cpanel start
/usr/local/cpanel/bin/tailwatchd --enable=Cpanel::TailWatch::ChkServd
fi

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
echo
echo 'Final sync complete, check the screen "dbdumps" on the remote server to ensure all databases imported correctly.'
}

main
