#!/bin/bash
#initalsync by abrevick@liquidweb.com
ver="Dev - Jan 19 2012"
#todo: 
# copy modsec configs? or at least display it.
# make ssh have quieter output? tried and failed before though.
# moar logging!

# Presync:
# streamline initial choice logic
# ssl cert status -expired or not
# get domains associated with users, for copying over zone files from new server. lower TTls only for domains that are migrating?
# check for remote mysql server, /root/.my.cnf, check for blank /etc/my.cnf, check for mysql moved to /home/

# Finalchecks:
# run expect on rebuildphpconf to make sure it installed correctly.
# automatically open ports for exim, apf IG_TCP_CPORTS ,csf TCP_IN
# copy apf/csf allow configs?
# show failed users after hosts and checks and apps 

#Changelog ###########
# Dec19 mysqldbfinalsync, added more logging to /tmp/mysqldump.log so it would show database names. want to add a db only sync.
# Dec 25 simplified single user sync
# Dec 26 Added "actions taken" to end of final sync.
# Jan 4 2012 added updating rsync to greater than 3, and logging for rsync/ found rsync loggin wiht --log-file isn't that useful actually :/  probably will want to log output of --stats but it adds the same output as -v
# added scriptlog for version, start, choice, end times.
# Jan 5 fixed rsync version comapre string
# Jan 8 2011 wrapped variable in if statement in quotes in mysqlextradbcheck
#  added rsync upgrade to final sync
#  added apacheprepostcheck function to presync
# Jan 16 2011 - implemented dbsync function.
#  Added dnsclustercheck function.
#  Tweaked apacheprepostcheck to print file contents and backup the conf file before copying.
# Jan 17 2011 - Fixed mysqlup so mysql actually updates.
# Jan 18 2011 - Added hosts/dbsync file script code into this script
# Jan 19 2011 - Added additional queries for finalsync userlist verification.
#  Added rsync logging and adjusted scriptlog location
#######################
#log when the script starts
starttime=`date +%F.%T`
scriptlogdir=/home/temp/
scriptlog=/home/temp/initialsync.$starttime.log
dnr=/home/didnotrestore.txt
[ -s $dnr ] && dnrusers=`cat $dnr`
#for home2 
> /tmp/remotefail.txt
> /tmp/localfail.txt
> /tmp/migration.rsync.log
mkdir -p $scriptlogdir
touch $scriptlog
echo "Version $ver" >> $scriptlog
echo "Started $starttime" >> $scriptlog

yesNo() { #generic yesNo function
#repeat if yes or no option not valid
while true; do
#$* read ever parameter giving to the yesNo function which will be the message
 echo -n "$* (Y/N)? "
 #junk holds the extra parameters yn holds the first parameters
 read yn junk
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

menutext() {
echo "Version: $ver"
echo "Main Menu:
Select the migration type:
1) Full sync (from /root/userlist.txt or all users, version matching)
2) Basic sync (all users, no version matching) 
3) Single user sync (no version matching)
4) User list sync (from /root/userlist.txt, no version matching)
5) Full sync - keeping old ips (/etc/ips is copied over)
8) Database sync - only sync databases for cpanel users.
9) Final sync (from /root/userlist.txt or all users)
0) Quit"
}

main() {
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
  keepipsync
  mainloop=1 ;;
 8) 
  dbsync
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
sleep 3
echo
echo "Started at $starttime"
[ $syncstarttime ] && echo "Sync started at $syncstarttime" |tee -a $scriptlog
[ $syncendtime ] &&  echo "Sync finished at $syncendtime" |tee -a $scriptlog
echo "Finished at `date +%F.%T`" | tee -a $scriptlog
echo 'Done!'
exit 0
}

dbsync() {
echo "Database only sync." |tee -a $scriptlog
userlist=`/bin/ls -A /var/cpanel/users`
getip        #asks for ip or checks a file to confirm destination
mysqldbfinalsync
}
#sync types
singleuser() {
echo
echo "Single user sync." | tee -a $scriptlog
singleuserloop=0
while [ $singleuserloop == 0 ]; do 
 echo -n "Input name of the user to migrate:"
 read userlist
 #check for error
 sucheck=`/bin/ls -A /var/cpanel/users | grep ^${userlist}$`
 if  [[ $sucheck = $userlist ]]; then
  echo "Found $userlist, restoring..."
  singleuserloop=1
  rsyncupgrade
  getip        #asks for ip or checks a file to confirm destination
  accountcheck #if conflicting accounts are found, asks
  acctcopy
  didntrestore

 else
  echo "Could not find $userlist."
 fi
done
}

listsync() {
echo
echo "List sync." | tee -a $scriptlog
listsyncvar=1
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
echo "Basic Sync started" |tee -a $scriptlog
presync
copyaccounts
}

fullsync() {
echo
echo "Full sync started" |tee -a $scriptlog
#check versions,  run ea, upcp, match php versions, lots of good stuff
presync
versionmatching
copyaccounts
}

keepipsync() {
echo
echo "Sync keeping old dedicated ips." |tee -a $scriptlog
keepoldips=1
fullsync
}

#Main sync procecures
presync() {
echo "Running Pre-sync functions..." |tee -a $scriptlog
#get ips and such
if ! [ "${singleuserloop}${listsyncvar}" ];then 
 dnrcheck     #userlist is defined here
fi
dnscheck     #lets you view current dns
rsyncupgrade
lowerttls    
getip        #asks for ip or checks a file to confirm destination
dnsclustercheck
accountcheck #if conflicting accounts are found, asks
dedipcheck  #asks if an equal amount of ips are not found
}

versionmatching() {
#only full syncs
echo "Running version matching..." |tee -a $scriptlog
nameservers
upcp
apacheprepostcheck
phpmemcheck 
thirdparty
mysqlcheck 
upea
installprogs
phpapicheck  # to be ran after ea so php4 can be compiled in if needed
}

copyaccounts() {
echo "Starting account copying functions..." |tee -a $scriptlog
acctcopy
didntrestore
mysqlextradbcheck
mysqldumpinitialsync
finalchecks
hostsgen
}

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
  #check for userlist file
  if [ -s /root/userlist.txt ]; then
   echo "/root/userlist.txt found, want to use this list?"
   cat /root/userlist.txt
   if yesNo ; then
    userlist=`cat /root/userlist.txt`
   else
    echo "Selecting all users."
    userlist=`/bin/ls -A /var/cpanel/users`
   fi
  else 
   echo "No previous migration found, migrating all users."
   userlist=`/bin/ls -A /var/cpanel/users`
  fi
fi

echo "Users slated for migration:"
echo $userlist
sleep 2
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
  sites=`grep $ips /etc/userdatadomains |awk -F== '{print $4}'|sort |uniq | sed -e 's/\(.*\)/\1 www.\1/g' `; 
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
rsync -avHPe "ssh -p$port" /scripts/hosts.sh $ip:/scripts/
ssh -p$port $ip "bash /scripts/hosts.sh"
sleep 2
}

dnsclustercheck() {
echo 
echo "Checking for DNS clustering..." |tee -a $scriptlog
if [ -d /var/cpanel/cluster ]; then
 echo 'Local DNS Clustering found!' |tee -a $scriptlog
 localcluster=1
fi
remotednscluster=`ssh -p$port $ip "if [ -d /var/cpanel/cluster ]; then echo \"Remote DNS Clustering found.\" ; fi" `
if [ $remotednscluster ]; then
 echo
 echo "Remote DNS clustering is detected, you shouldn't continue since restoring accounts has the potential to automatically update DNS for them in the cluster. Probably will be better to remove the remote server from the cluster before continuing." |tee -a $scriptlog
 if yesNo 'Do you want to continue?'; then
  echo "Continuing..." |tee -a $scriptlog
 else
  exit 0
 fi
fi

}

dnscheck() {
echo
echo "Checking Current dns..." |tee -a $scriptlog
if [ -f /root/dns.txt ]; then
 echo "Found /root/dns.txt"
 sleep 3
 cat /root/dns.txt | sort -n +3 -2 | more
else
 domainlist=`cat /etc/userdomains |sort | sed -e 's/:.*//' |grep -v \*`
 for each in $domainlist; do echo $each\ `dig @8.8.8.8 NS +short $each |sed 's/\.$//g'`\ `dig @8.8.8.8 +short $each` ;done | grep -v \ \ | column -t > /root/dns.txt
 cat /root/dns.txt | sort -n +3 -2 | more
fi
echo "Enter to continue..."
read
}

lowerttls() {
echo
echo "Lowering TTLs..." |tee -a $scriptlog
#lower ttls
sed -i.lwbak -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' /var/named/*.db
rndc reload
}

getip() {
echo
echo "Getting Ip for destination server..." |tee -a $scriptlog
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
  rm -rf /home/dest.port.txt
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
echo "Getting ssh port." |tee -a $scriptlog
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
echo "Generating SSH keys" |tee -a $scriptlog
if ! [ -f ~/.ssh/id_rsa ]; then
 ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
fi
cat ~/.ssh/id_rsa.pub | ssh $ip -p$port "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
ssh $ip -p$port "echo \'Connected!\';  cat /etc/hosts| grep $ip " 
}
 

accountcheck() { #check for users with the same name on each server:
echo
echo "Comparing accounts with destination server" |tee -a $scriptlog
for user in $userlist ; do ssh -qt $ip -p$port " if [ -f /var/cpanel/users/$user ]; then echo $user;fi"  ; done > /root/userexists.txt
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

if [ $keepoldips ];then 
 echo "Keeping old ips, copying ips file over."|tee -a $scriptlog
 ssh $ip -p$port "cp -rp /etc/ips{,.bak}"
 rsync -aqHe "ssh -p${port}" /etc/ips $ip:/etc/
 ssh $ip -p$port "/etc/init.d/ipaliases restart"
fi

echo
echo "Checking for dedicated Ips." |tee -a $scriptlog
sourceipcount=`cat /etc/ips | grep ^[0-9] | wc -l`
destipcount=`ssh  $ip -p$port "cat /etc/ips |grep ^[0-9] | wc -l"`
if (( $sourceipcount <= $destipcount ));then
 echo "Source server has less or equal ips compared to destination, continuing."
 ipcheck=1
else
 ipcheck=0
 sleep 2
 /scripts/ipusage
 echo 
 echo "Not enough dedicated IPs found on destination server ($destipcount) when compared to source server ($sourceipcount)."
 echo "If you are sure the server isn't using all its IPs for accounts you can override the Ip check by answering Yes. Otherwise answer No to put all sites on the main shared IP."
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

nameservers() {

echo "Set nameservers on remote host?"
grep ^NS[\ 0-9]  /etc/wwwacct.conf 
if yesNo ;then
 grep ^NS[\ 0-9]  /etc/wwwacct.conf > /tmp/nameservers.txt
 rsync -avHPe "ssh -p$port" /tmp/nameservers.txt $ip:/tmp/
 ssh $sshopts $ip -p$port "cp -rp /etc/wwwacct.conf{,.bak} ;
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
  echo "/usr/local/apache/conf/includes/$file"
  cat /usr/local/apache/conf/includes/$file
  echo
  echo "Found extra apache configuration in $file, copy to new server?"
  if yesNo ; then
   ssh -p$port $ip "mv /usr/local/apache/conf/includes/$file{,.bak}"
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
else

 phpver=`grep ^DEFAULT\ PHP /tmp/phpconf |awk '{print $3}'`
 php4sapi=`grep ^PHP4\ SAPI /tmp/phpconf |awk '{print $3}'`
 php5sapi=`grep ^PHP5\ SAPI /tmp/phpconf |awk '{print $3}'`
 phpsuexec=`grep ^SUEXEC /tmp/phpconf |awk '{print $2}'`
#php suexec will be either 'enabled' or 'not installed', check if its not enabled. can set the param with 1 or 0 also.
 if [ "$phpsuexec" != enabled ]; then
  phpsuexec=0
 fi
 #check if phpver is 4 or 5, old EA versions will fail the rebuild_phpconf command
 case $phpver in
 [45]) 
 ssh $ip -p$port "/usr/local/cpanel/bin/rebuild_phpconf --current > /tmp/phpconf.`date +%F.%T`.txt ;/usr/local/cpanel/bin/rebuild_phpconf $phpver $php4sapi $php5sapi $phpsuexec "  
 ;;
 *)  echo "Got unexpected output from /usr/local/cpanel/bin/rebuild_phpconf --current, skipping..." 
     phpapicheck=1 ;;
 esac
fi
}

phpmemcheck(){
echo
echo "Checking php memory limit..."
phpmem=`php -i |grep ^memory_limit |cut -d" " -f3`
rphpmem=`ssh $ip -p$port 'php -i |grep ^memory_limit |cut -d" " -f3'`
if [ $phpmem ]; then
 if [ $rphpmem ]; then
  if [[ $phpmem != $rphpmem ]]; then
   phpmemcmd=`echo 'sed -i '\''s/\(memory_limit\ =\ \)[0-9]*M/\1'$phpmem'/'\'' /usr/local/lib/php.ini'`
   ssh $ip -p$port "cp -rp /usr/local/lib/php.ini{,.bak} ; $phpmemcmd ; service httpd restart" 
  else
   echo "Old memorylimit $phpmem matches new $rphpmem, skipping..."
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
 if yesNo "Change remote server's mysql version to $smysqlv?" ; then
  #get remote php version now since mysql will not allow us to check later.
  phpvr=`ssh $ip -p$port "php -v |head -n1 |cut -d\" \" -f2"`
  mysqlup=1
 else
  echo "Not updating mysql."
 fi
fi
sleep 1
}

mysqlextradbcheck() { #find dbs created outside of cpanel, with potential to copy them over.
#skip this fucntion if the username prefix is disabled.
dbprefixvar=`grep database_prefix /var/cpanel/cpanel.config `
if ! [ "$dbprefixvar" = "database_prefix=0" ]; then
 echo
 echo "Checking for extra mysql databases..."
 mkdir -p /home/temp/
 mysql -e 'show databases' |grep -v ^cphulkd |grep -v ^information_schema |grep -v ^eximstats |grep -v ^horde | grep -v leechprotect |grep -v ^modsec |grep -v ^mysql |grep -v ^roundcube |grep -v ^Database > /home/temp/dblist.txt
#still have user_ databases, filter those.
 cp -rp /home/temp/dblist.txt /home/temp/extradbs.txt
 #get all users here, not userlist.
 for user in `/bin/ls -A /var/cpanel/users`; do 
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
 fi

else
 echo
 echo "Detected user database prefixing is disabled in WHM.  Might want to set this up on the new server, accounts should migrate fine though."
 echo "Enter to continue..."
 read
fi
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
  upcp=1
  ssh $ip -p$port "/scripts/upcp"
 else
  echo "Okay, fine, not running upcp." 
 fi
 else
 echo "Found a higher version of cpanel on remote server, continuing."
fi
sleep 1
}

upea() {
echo
echo "Prepping for EasyApache..."
#EA 
#copy the EA config
rsync -aqHe "ssh -p$port" /var/cpanel/easy/apache/ $ip:/var/cpanel/easy/apache/
#Copy Cpanel packages
rsync -aqHe "ssh -p$port" /var/cpanel/packages/ $ip:/var/cpanel/packages/
#Copy features
rsync -aqHe "ssh -p$port" /var/cpanel/features/ $ip:/var/cpanel/features/
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
 ea=1
 unset mysqlupcheck
else
 echo 'Just trying to help :/'
 skippedea=1
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
echo "Heres what we found to install:"
for prog in $proglist; do 
 if [ "${!prog}" ] ; then
  echo "${prog}"
 fi
done
echo "Press enter to begin installing and start the initial sync."
read

#lwbake,plbake
echo "Installing lwbake and plbake"
ssh $ip -p$port "wget -O /scripts/lwbake http://layer3.liquidweb.com/scripts/lwbake;
chmod 700 /scripts/lwbake
wget -O /scripts/plbake http://layer3.liquidweb.com/scripts/plBake/plBake
chmod 700 /scripts/plbake"

#ffmpeg
if [ $ffmpeg ] ; then
 echo "Ffmpeg found, installing on new server..."
 ssh $ip -p$port "/scripts/lwbake ffmpeg-php "
fi

#imagick
if [ $imagick ] ; then 
 echo "Imagemagick found, installing on new server..."
 ssh $ip -p$port "
 /scripts/lwbake imagemagick
 /scripts/lwbake imagick
 /scripts/lwbake magickwand"
fi

#memcache
if [ "$memcache" ]; then
 echo "Memcache found, installing remotely..."
 echo
 ssh $ip -p$port'
 wget -O /scripts/confmemcached.pl http://layer3.liquidweb.com/scripts/confMemcached/confmemcached.pl
chmod +x /scripts/confmemcached.pl
/scripts/confmemcached.pl --memcached-full
service httpd restart'
fi

#java
if [ "$java" ];then
 echo "Java found, installing..."
 ssh $ip -p $port "/scripts/plbake java"
fi

#upcp
if [ $upcp ]; then
 echo "Running Upcp..."
 sleep 2
 ssh $ip -p$port "/scripts/upcp"
fi

#mysql
if [ $mysqlup ]; then
 echo "Reinstalling mysql..."
 ssh $ip -p$port "
 sed -i.bak /mysql-version/d /var/cpanel/cpanel.config ; 
 echo mysql-version=$smysqlv >> /var/cpanel/cpanel.config ; 
 cp -rp /etc/my.cnf{,.bak} ; 
 cp -rp /var/lib/mysql{,.bak} ; 
 /scripts/mysqlup --force"
 echo "Mysql update completed, remember EA will need to be ran."
 mysqlupcheck=1
fi

#Easyapache
if [ $ea ]; then
 echo "Running EA..."
 ssh $ip -p$port "/scripts/easyapache --build"
 unset mysqlupcheck
fi

#postgres
if [ $postgresfound ]; then
 echo "Installing Postgresql..."
 #use expect to install since it asks for input
 ssh $ip -p$port 'cp -rp /var/lib/pgsql{,.bak}
 expect -c "spawn /scripts/installpostgres
expect \"Are you sure you wish to proceed? \"
send \"yes\r\"
expect eof"'
 rsync -avHPe "ssh -p$port" /var/lib/pgsql/data/pg_hba.conf $ip:/var/lib/pgsql/data/
 ssh $ip -p$port "/scripts/restartsrv_postgres"
fi

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
   ssh -t -n -q $ip -p$port "mkdir -p /home/temp; 
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

rsynchomedirs() { 
#to be ran inside of a for user in userlist loop, from both initial and final syncs
#for home2 
userhomelocal=`grep  ^$user: /etc/passwd |cut -d: -f6 `
userhomeremote=`ssh $ip -p$port " grep  ^$user: /etc/passwd |cut -d: -f6"` 
echo 

#rsync
echo
ruser=`ssh $ip -p$port "cd /var/cpanel/users/; ls $user"`
if [ "$user" == "$ruser" ]; then 
#check for non-empty vars
 if [ $userhomelocal ]; then
  if [ $userhomeremote ]; then
   echo "Syncing Home directory for $user. $userhomelocal to ${ip}:${userhomeremote}" |tee -a $scriptlog
   echo "Verbose rsync output logging to $scriptlog"
   echo "Please wait..."
   rsync -avHle  "ssh -p$port" ${userhomelocal}/ ${ip}:${userhomeremote}/ >> $scriptlog 
  else
   #remote fails
   echo "Remote path for $user not found."
   echo "$user remote path not found: \"$userhomeremote\"" >> /tmp/remotefail.txt
   echo $user >> $dnr 
  fi
 else
  #local fails
  echo "Local path for $user not found."
  echo "$user local path not found: \"$userhomelocal\"" >> /tmp/localfail.txt
  echo $user >> $dnr
 fi
 
else 
 #didn't find user on remote 
 echo $user >> $dnr
fi
}

didntrestore() {
#loop finished, check for users that didn't restore
if [ -s /tmp/localfail.txt ]; then
 echo
 echo "Couldnt find users local home directory path:"
 cat /tmp/localfail.txt
 echo "enter to continue"
 read
fi

if [ -s /tmp/remotefail.txt ]; then
 echo
 echo "Couldnt find users remote directory path:"
 cat /tmp/remotefail.txt
 echo "enter to continue"
 read
fi

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

#mailperm, fixquotas
finalfixes

echo
echo "===Final Checks==="

#3rdparty stuff
if [ "${xcachefound}${eaccelfound}${nginxfound}" ]; then
echo '3rd party stuff found on the old server!'
[ "$xcachefound" ] && echo "Xcache: $xcachefound"
[ "$eaccelfound" ] && echo "Eaccelerator: $eaccelfound"
[ "$nginxfound" ] && echo "Nginx: $nginxfound"
echo 'Press enter to continue...'
read
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
 echo 'Run EasyApache on new server! (press enter to continue)'
 read
 #fix php handlers if EA was skipped, could fail if php4 was mising before.
 phpapicheck
fi

if [ -s /etc/remotedomains ]; then
 echo 'Domains found in /etc/remotedomains, double check their mx settings!'
 cat /etc/remotedomains
 echo 'Press enter to continue...'
 read
fi


if [ $localcluster ];then
 echo 'Local DNS clustering was found! May need to setup on the new server.'
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

mysqldumpinitialsync() {
echo
mkdir -p /home/dbdumps
if [ -s /root/dblist.txt ]; then
 echo "Found extra databases to dump..."
 for db in `cat /root/dblist.txt`; do 
  mysqldumpfunction
  ssh $ip -p$port "mysqladmin create $db"
 done
 rsync --progress -avHlze "ssh -p$port" /home/dbdumps $ip:/home/
# ssh $ip -p$port "wget migration.sysres.liquidweb.com/dbsync.sh -O /scripts/dbsync.sh; screen -S dbsync -d -m bash /scripts/dbsync.sh" &
dbsyncscript
 echo "Databases restoring in screen dbsync on remote server."
 echo "Mysql user permissions will need to be restored to the new server."
 read
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
ssh $ip -p$port "screen -S dbsync -d -m bash /scripts/dbsync.sh" &
}

mysqldbfinalsync() {
echo "Dumping the databases..."
test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%T`.bak}
mkdir -p /home/dbdumps
ssh $ip -p$port 'test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%T`.bak}'
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
echo "Dumping $db" | tee -a /tmp/mysqldump.log; 
#mysqldump log-error doesn't work for versions less than 5.0.42 
if [[ $mysqldumpver < 5.0.42 ]]; then 
 mysqldump --add-drop-table $db > /home/dbdumps/$db.sql
else
 mysqldump --force --add-drop-table --log-error=/tmp/mysqldump.log $db > /home/dbdumps/$db.sql  
fi
}

finalsync() {
echo
echo "Running final sync..." |tee -a $scriptlog

#check for previous migration
if [ -s /root/userlist.txt ]; then 
 echo "Found /root/userlist.txt."
 userlist=`cat /root/userlist.txt`
 echo "$userlist"
 if yesNo "Are these users correct?"; then
  echo "Continuing."
 else
  if yesNo "Would you like to migrate all users?"; then
   echo "Syncing all users."
   userlist=`/bin/ls -A /var/cpanel/users`
  else
   echo "Please edit /root/userlist.txt with the users you wish to migrate and rerun the script."
   exit 0
  fi
 fi 
else
 echo "Syncing all users."
 userlist=`/bin/ls -A /var/cpanel/users`
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

for user in $userlist; do 
 rsynchomedirs
done

#packages, spool data
rsync -aqHPe "ssh -p$port" /var/cpanel/packages $ip:/var/cpanel/
rsync -aqHPe "ssh -p$port" /var/spool $ip:/var/

#mailperm, fixquotas
finalfixes

#copy zone files over from new server, if selected.
if [ $copydns ]; then 
 echo "Copying zone files over from new server..."
 rsync -aqHPe "ssh -p$port" /var/named/ /var/named.`date +%F.%T`/
 rsync -aqHPe "ssh -p$port" $ip:/var/named/*.db /var/named/
 sed -i -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' /var/named/*.db
 rndc reload 
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

echo "=Actions taken:="
if [ $stopservices ]; then 
 echo "Stopped services"
 if [ $restartservices ];then echo "Restarted services"; else echo "Didnt restart services"; fi
fi
[ $copydns ] && echo "DNS was copied over from new server."

echo 'Final sync complete, check the screen "dbdumps" on the remote server to ensure all databases imported correctly.'
}

finalfixes() {
#in final sync and initial sync
#fix mail permissisons
echo "Fixing mail permissions on new server."
ssh $ip -p$port "screen -S mailperm -d -m /scripts/mailperm" &

#fix quotas
echo "Starting a screen to fix cpanel quotas."
ssh $ip -p$port "screen -S fixquotas -d -m /scripts/fixquotas" &
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

#REMOTECENT=`ssh -p$PORT $USER@$IP "cat /etc/redhat-release" |awk '{print $3}'|cut -d '.' -f1`
#REMOTEARCH=`ssh -p$PORT $USER@$IP "uname -i"`
#       ssh -p$PORT $USER@$IP "rpm -Uvh http://migration.sysres.liquidweb.com/rsync/rsync-3.0.0-1.el$REMOTECENT.rf.$REMOTEARCH.rpm"
}

main
