#!/bin/bash
#initalsync by abrevick@liquidweb.com
ver="Oct 22 2012"
# http://migration.sysres.liquidweb.com/initialsync.sh
# https://github.com/defenestration/initialsync

#todo: 
# copy modsec configs? or at least display it.
# make ssh have quieter output? tried and failed before though.
# moar logging!
# sslcheck - sanitize * in cert file names.

# Presync:
# streamline initial choice logic
# get domains associated with users, for copying over zone files from new server. lower TTls only for domains that are migrating?
# check for remote mysql server, /root/.my.cnf, check for blank /etc/my.cnf
# Show number of total cpanel users compared to what the script found in userlist.txt.
# Show a count of accounts left to sync during the sync like (2/15 synced)
# Compare disk space of partitions

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
# Jan 8 2012 wrapped variable in if statement in quotes in mysqlextradbcheck
#  added rsync upgrade to final sync
#  added apacheprepostcheck function to presync
# Jan 16 2012 - implemented dbsync function.
#  Added dnsclustercheck function.
#  Tweaked apacheprepostcheck to print file contents and backup the conf file before copying.
# Jan 17 2012 - Fixed  so mysql actually updates.
# Jan 18 2012 - Added hosts/dbsync file script code into this script
# Jan 19 2012 - Added additional queries for finalsync userlist verification.
#  Added rsync logging and adjusted scriptlog location
# Jan 22 2012 - Stop Ipaliases on new server if keepoldips is set.
#  Added logging of pkgacct and restorepkg instead of showing to screen.
# Jan 26 2012 - Memcache install was broken, missing a space >_< fixed.
# Jan 29 2012 - Added mysqlsymlink check
# Feb 1  2012 - added reloading for nsd nameserver
#  moved imagic ffmpeg and memcache to final checks so they are installed after EA
# Feb 2  2012 - added SSL cert check, removed IP sync migration.
# Feb 6 2012 -  Moved sslcertcheck to presync.
# Feb 16 2012 - Added gcccheck
# Feb 22 2012 - Fixed path of the dest.port.txt file when inputting new destination server ip
#  Updated single user sync to restore original authorized_keys on destination server after sync (for shared server moves)
# Feb 28 2012 - Fixed upcp from running twice
# Mar 22 2012 - Fixed postgres find.
# Mar 29 2012 - Added rubygems function.
# Apr 2 2012 - Fixed dbsync screen name
# Apr 16 2012 source ip count improvements by jmuffett
#   added dbonlysync var to check if only mysqldump menu option was ran.
# Apr 17 - removed dbonlysync var, final sync wasn't syncing dbs.
# Apr 19 - Added option to invoke --update during final rsync, rsyncupdate
# added cpbackupcheck to enable cpanel backups on the remote server.
# Apr 20 - clarified Override Ip check question text
# Apr 30 - Fixed cpbackupcheck, path to cpbackup.conf
# May  1 - Changed lowerttls to a find/sed to avoid bash wildcard completion errors
# May  8 - postgresfound variable was not set earlier, so postgres wouldn't get installed, changed variable to postgres.
# May 16 - dnscheck now checks for domains owned by users in /root/userlist.txt - awalilko
# May 18 - /home/dbdumps wasn't renamed on the new server during initial sync, this could cause issues if there was a previous migration. set to rename that folder with a date on hte new server.
# May 21 - Also check and rename /home/dbdumps on source server | skip logaholicDB copying.
# May 25 - switched Lower TTLS to perl as sed -i doesn't exist in old versions of sed
# Jun 05 - Added logging for which users were being migrated.
# Jun 22 - Quoted remotednscluster like 395ish, clarified text there a little.
# Jun 28 - Removed rsync upgrade from single user sync.
# Jul 23 - Remove safe-show-database and skip-locking from my.cnf if mysql is being upgraded to a version greater than 5.
# Jul 27 - Trimmed extra check function out of mysqlsymlinkcheck, updated eximcheck in finalchecks to compare ports between servers.
# Jul 31 - Added logvars function to simplify logging, added in some areas of script.
# Aug 7  - Exclude databases with * in the name from mysql -e show databases
# Aug 24 - Fixed logvars function to not overwrite the log :D
# Aug 29 - Added -y to gcc install
# Sep 12 - Added more logging
# Oct  2 - Option for Dedicated Ip in single user sync
# Oct  5 - more logging to sshkeygen
# Oct 22 - added option to remove ssh key at the end of final sync. 
#######################
#log when the script starts
starttime=`date +%F.%T`
scriptlogdir=/home/temp/
scriptlog=/home/temp/initialsync.$starttime.log
dnr=/home/didnotrestore.txt
rsyncflags="-avHl"
[ -s $dnr ] && dnrusers=`cat $dnr`
#for home2 
> /tmp/remotefail.txt
> /tmp/localfail.txt
> /tmp/migration.rsync.log
mkdir -p $scriptlogdir
touch $scriptlog
echo "Version $ver" |tee -a  $scriptlog
echo "Started $starttime" | tee -a $scriptlog

yesNo() { #generic yesNo function
#repeat if yes or no option not valid
while true; do
#$* read ever parameter giving to the yesNo function which will be the message
 echo -n "$* (Y/N)? " | tee -a $scriptlog
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
    echo "Please enter y or n." | tee -a $scriptlog
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
3) Single user sync (no version matching, shared server safe)
4) User list sync (from /root/userlist.txt, no version matching)
8) Database sync - only sync databases for cpanel users, and from /root/dblist.txt.
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
# 5)
#  keepipsync
#  mainloop=1 ;;
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
dbonlysync=1
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
 echo -n "Input name of the user to migrate:"  |tee -a $scriptlog
 read userlist
 logvars userlist
 if yesNo "Restore to dedicated ip?"; then
   ipcheck=1 
   logvars ipcheck
 fi
 #check for error
 sucheck=`/bin/ls -A /var/cpanel/users | grep ^${userlist}$`
 if  [[ $sucheck = $userlist ]]; then
  echo "Found $userlist, restoring..." | tee -a $scriptlog
  singleuserloop=1
  #rsyncupgrade
  getip        #asks for ip or checks a file to confirm destination
  accountcheck #if conflicting accounts are found, asks
  acctcopy
  didntrestore
  echo
  echo "Removing ssh key from remote server." |tee -a $scriptlog
  ssh -p$port $ip "rm ~/.ssh/authorized_keys ; cp -rp ~/.ssh/authorized_keys{.syncbak,}"

 else
  echo "Could not find $userlist." |tee -a $scriptlog
 fi
done
}

listsync() {
echo
echo "List sync." | tee -a $scriptlog
listsyncvar=1
#search for /root/users.txt and /home/users.txt
if [ -s /root/userlist.txt ]; then
 echo "Found /root/userlist.txt" |tee -a $scriptlog
 sleep 3
 userlist=`cat /root/userlist.txt`
 echo "$userlist" | tee -a $scriptlog
 basicsync
elif [ -s /home/users.txt ]; then 
 echo "Found /home/users.txt" |tee -a $scriptlog
 sleep 3
 userlist=` cat /home/users.txt`
 echo "$userlist"
 basicsync
elif [ -s /root/users.txt ]; then
 echo "found /root/users.txt" |tee -a $scriptlog
 userlist=`cat /root/users.txt`
 sleep 3
 basicsync
else 
 echo "Did not find users.txt in /root or /home" |tee -a $scriptlog
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
echo "Running version matching..." |tee -a $scriptlog
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
}

copyaccounts() {
echo "Starting account copying functions..." |tee -a $scriptlog
acctcopy
didntrestore
mysqlextradbcheck
mysqldumpinitialsync
cpbackupcheck
finalchecks
hostsgen
}

dnrcheck() { 
#define users
#check and suggest to restore accounts from a previous failed migration
#dnrusers is defined at the start
echo
echo "Checking for previous failed migration."  |tee -a $scriptlog
if [ "$dnrusers" ];then
 echo
 echo "Found users from failed migration in $dnr" |tee -a $scriptlog
 echo $dnrusers
 ls -l $dnr
 echo
 if yesNo 'Want to restore these failed users only?' ;then
  userlist=$dnrusers
  cp -rpf ${dnr}{,.bak}
  > $dnr
 else 
  echo "Okay, selecting all users for migration." |tee -a $scriptlog
  userlist=`/bin/ls -A /var/cpanel/users`	
 fi
 else
  #check for userlist file
  if [ -s /root/userlist.txt ]; then
   echo "/root/userlist.txt found, want to use this list?" |tee -a $scriptlog
   cat /root/userlist.txt
   if yesNo ; then
    userlist=`cat /root/userlist.txt`
   else
    echo "Selecting all users." |tee -a $scriptlog
    userlist=`/bin/ls -A /var/cpanel/users`
   fi
  else 
   echo "No previous migration found, migrating all users."
   userlist=`/bin/ls -A /var/cpanel/users`
  fi
fi

echo "Users slated for migration:" |tee -a $scriptlog
echo $userlist |tee -a $scriptlog
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
 logvars localcluster
fi
remotednscluster=`ssh -p$port $ip "if [ -d /var/cpanel/cluster ]; then echo \"Remote DNS Clustering found.\" ; fi" `
logvars remotednscluster
if [ "$remotednscluster" ]; then
 echo
 echo "DNS cluster on the new server is detected, you shouldn't continue since restoring accounts has the potential to automatically update DNS for them in the cluster. Probably will be better to remove the remote server from the cluster before continuing." |tee -a $scriptlog
 if yesNo 'Do you want to continue?'; then
  echo "Continuing..." |tee -a $scriptlog
 else
  exit 0
 fi
fi

}

sslcertcheck() {
#SSl cert checking.
echo "Checking for SSL Certificates in apache conf." |tee -a $scriptlog
crtcheck=`grep SSLCertificateFile /usr/local/apache/conf/httpd.conf`
logvars crtcheck
if [ "$crtcheck" ]; then
 echo "SSL Certificates detected." |tee -a $scriptlog
 echo
 for crt in `grep SSLCertificateFile /usr/local/apache/conf/httpd.conf |awk '{print $2}'`; do
  echo $crt; openssl x509 -noout -in $crt -issuer  -subject  -dates | tee -a $scriptlog
  echo 
 done
 echo
 echo "Enter to continue..."
 read
else
 echo "No SSL Certificates found in httpd.conf." |tee -a $scriptlog
 sleep 2 
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
 for user in $userlist; do cat /etc/userdomains | grep $user | cut -d: -f1 >> /root/domainlist.txt; done
 domainlist=`cat /root/domainlist.txt`
 logvars domainlist
 for each in $domainlist; do echo $each\ `dig @8.8.8.8 NS +short $each |sed 's/\.$//g'`\ `dig @8.8.8.8 +short $each` ;done | grep -v \ \ | column -t > /root/dns.txt
 cat /root/dns.txt | sort -n +3 -2 | more
fi
echo "Enter to continue..."
read
}

lowerttls() {
echo
echo "Lowering TTLs..." |tee -a $scriptlog
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
 echo "Nsd found, reloading"|tee -a $scriptlog
 nsdc rebuild
 nsdc reload
fi
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
 #echo "Testing connetion to remote server..."
 #echo
 #ssh $ip -p$port "cat /etc/hosts |tail -n3 ; ifconfig eth0 |head -n2"
 #echo
 #echo "Test complete."
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
logvars port

}

sshkeygen() {
echo
if ! [ -f ~/.ssh/id_rsa ]; then  
 echo "Generating SSH key..." |tee -a $scriptlog
 ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
else
  echo "SSH key found." | tee -a $scriptlog
fi
echo "Copying Key to remote server..." | tee -a $scriptlog
cat ~/.ssh/id_rsa.pub | ssh $ip -p$port "cp -rp ~/.ssh/authorized_keys{,.syncbak} ; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
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
# If /etc/userdatadomains exists, calculate dedicated IPs based on usage.
# Otherwise uses same functionality as before.
if [[ -f /etc/userdatadomains ]]; then
 preliminary_ip_check=`cat /etc/userdatadomains|sed -e 's/:/ /g' -e 's/==/ /g'|cut -d ' ' -f8|tr -d [:blank:]|sort|uniq`
 logvars preliminary_ip_check
 server_main_ip=`cat /etc/wwwacct.conf|grep ADDR|cut -d ' ' -f2`
 logvars server_main_ip
 for preliminary_ips in $preliminary_ip_check; do
  logvars preliminary_ips
  if [[ $preliminary_ips != $server_main_ip ]]; then
   dedicated_ip_accounts="${dedicated_ip_accounts} $preliminary_ips"
   logvars dedicated_ip_accounts
  fi
 done
 sourceipcount=`echo $dedicated_ip_accounts|sed -e 's/ /\n/g'|wc -l`
else
 sourceipcount=`cat /etc/ips | grep ^[0-9] | wc -l`
fi
logvars sourceipcount
# Check target server for number of dedicated IPs available
destipcount=`ssh  $ip -p$port "cat /etc/ips |grep ^[0-9] | wc -l"`
logvars destipcount
if (( $sourceipcount <= $destipcount ));then
 echo "Source server has less or equal ips compared to destination." | tee -a $scriptlog
  if yesNo "Override IP check?
 yes = Restore accounts to dedicated IPs (accouts will not all restore if there are not enough ips)
 no  = Restore all to the main Shared ip" ;then
   ipcheck=1
  else
   ipcheck=0
  fi
else
 ipcheck=0
 sleep 2
 /scripts/ipusage
 echo 
 echo "Not enough dedicated IPs found on destination server ($destipcount) when compared to source server ($sourceipcount)."
# echo "If you are sure the server isn't using all its IPs for accounts you can override the Ip check by answering Yes. Otherwise answer No to put all sites on the main shared IP."
 if yesNo "Override IP check?
 yes = Try to restore accounts to dedicated IPs anyway (accouts will not all restore if there are not enough ips)
 no  = Restore all to the main Shared ip" ;then
  ipcheck=1
  echo "Restoring to dedicated ips."
 else
  ipcheck=0
  echo "Restoring to main shared ip."
 fi
fi
sleep 1
logvars ipcheck

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

#postgresql 
postgres=`ps aux |grep -e 'postgres' |grep -v grep |tail -n1`

#other stuff, say if it needs to be installed at the end
xcachefound=`ps aux | grep -e 'xcache' | grep -v grep | tail -n1`
eaccelfound=`ps aux | grep -e 'eaccelerator' | grep -v grep |tail -n1`
nginxfound=`ps aux | grep  -e 'nginx' |grep -v grep| tail -n1`
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
 mysql -e 'show databases' |grep -v ^cphulkd |grep -v ^information_schema |grep -v ^eximstats |grep -v ^horde | grep -v leechprotect |grep -v ^modsec |grep -v ^mysql |grep -v ^roundcube |grep -v ^Database | grep -v ^logaholicDB |grep -v '*' > /home/temp/dblist.txt
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

mysqlsymlinkcheck() {
echo
echo "Checking if Mysql was moved to a different location."
#test if symbolic link
if [ -L /var/lib/mysql ]; then
 echo "Warning, /var/lib/mysql is a symlink! Grepping for datadir in my.cnf:"
 grep datadir /etc/my.cnf
 echo "You may want to relocate mysql on the new server (if it isnt already) before continuing."
 if yesNo 'Yes to continue, no to exit.'; then
  echo "Continuing..."
 else 
  echo "Exiting."
  exit 0
 fi
fi
}

gcccheck() {
echo 'Checking for gcc on new server, because some newer storm servers dont have gcc installed so EA and possibly other things will fail to install.'
gcccheck=$(ssh -p$port $ip "rpm -qa gcc")
if [ "$gcccheck" ]; then
 echo "Gcc found, continuing..."
else
 echo 'Gcc not found, running "yum install gcc" on remote server. You may have to hit "y" then Enter to install.'
 sleep 3
 ssh -p$port $ip "yum -y install gcc"
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
  #ssh $ip -p$port "/scripts/upcp"
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

echo "
Available software versions on remote server:"
ssh -p $port $ip "/scripts/easyapache --latest-versions"

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
 #mysql 5.5 won't start if safe-show-database and skip-locking are in my.cnf
 ssh $ip -p$port "
 sed -i.bak /mysql-version/d /var/cpanel/cpanel.config ; 
 echo mysql-version=$smysqlv >> /var/cpanel/cpanel.config ; 
 cp -rp /etc/my.cnf{,.bak} ; 
 if [ $smysqlv > 5 ]; then
  sed -i -e /safe-show-database/d /etc/my.cnf
  sed -i -e /skip-locking/d /etc/my.cnf
 fi
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
if [ $postgres ]; then
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
logvars userlist
#pack/send restore loop
> $dnr
mainip=`grep ADDR /etc/wwwacct.conf | awk '{print $2}'`
logvars mainip
for user in $userlist; do 
 logvars user
 userip=`grep ^IP= /var/cpanel/users/$user|cut -d '=' -f2`
 logvars userip
 echo "Packaging $user, logging to $scriptlog"  | tee -a $scriptlog
 /scripts/pkgacct --skiphomedir $user >> $scriptlog
 echo "Rsyncing cpmove-$user.tar.gz to $ip:/home/" | tee -a $scriptlog
 rsync -aqHlPe "ssh -p$port" /home*/cpmove-$user.tar.gz $ip:/home 
 echo "Restoring package" 
#check for not enough ips
#If keeping old ips.
 if [[ $keepoldips ]]; then
 logvars keepoldips
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
  logvars ipcheck
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
logvars userhomelocal
logvars userhomeremote
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
echo 
 
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
 echo '--did not restore--' |tee -a $scriptlog
 cat $dnr | tee -a $scriptlog
 echo '-------------------'
 echo 'You can re-run this script and run the basic sync to restore these users if desired.'
 echo 'Press enter to continue...'
 read
fi
}

php3rdpartyapps() {
#apps that add a php module should be installed after EA is ran at the end
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
 ssh $ip -p$port '
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

php3rdpartyapps

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

#if keep old ips was set, stop ipaliases on the new server, to prevent it from 'stealing' the ips if the old server goes offline.
if [ $keepoldips ]; then
 echo "Stopping Ip aliases on new server to prevent Ip stealing on new server."
 ssh -p$port $ip "/etc/init.d/ipaliases stop"
fi
 

#check for alternate exim ports
eximports=`grep ^daemon_smtp_ports /etc/exim.conf`
eximportsremote=`ssh $ip -p$port 'grep daemon_smtp_ports /etc/exim.conf'`
if [ "$eximports" != "$eximportsremote" ]; then
 echo 'Alternate smtp ports found!'
 echo $eximports
 echo 'Set them up within WHM on the new server. (enter to continue)'
 read
 else
 echo 'Exim ports match!'
fi

echo "===End Final Checks==="
echo "Enter to continue"
read
}

mysqldumpinitialsync() {
echo
#backup dbdumps folder on new server.
ssh $ip -p$port  "test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%R`.bak}"
#also check and backup /home/dbdumps on source server
test -d /home/dbdumps && mv /home/dbdumps{,.`date +%F.%R`.bak}
#dump backups on current server and copy them over.
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
 echo "Enter to continue."
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
finalsynccheck=1
#check for previous migration
if [ -s /root/userlist.txt ]; then 
 echo "Found /root/userlist.txt." |tee -a $scriptlog
 userlist=`cat /root/userlist.txt`
 echo "$userlist" | tee -a $scriptlog
 if yesNo "Are these users correct?"; then
  echo "Continuing." |tee -a $scriptlog
 else
  if yesNo "Would you like to migrate all users?"; then
   echo "Syncing all users." |tee -a $scriptlog
   userlist=`/bin/ls -A /var/cpanel/users`
  else
   echo "Please edit /root/userlist.txt with the users you wish to migrate and rerun the script."
   exit 0
  fi
 fi 
else
 echo "Syncing all users." |tee -a $scriptlog
 userlist=`/bin/ls -A /var/cpanel/users`
 echo "$userlist" |tee -a $scriptlog
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
echo "Stopping Services..." |tee -a $scriptlog
[ -s /etc/init.d/chkservd ] && /etc/init.d/chkservd stop
/usr/local/cpanel/bin/tailwatchd --disable=Cpanel::TailWatch::ChkServd
/etc/init.d/httpd stop
/etc/init.d/exim stop
/etc/init.d/cpanel stop
else
 echo "Not stopping services." |tee -a $scriptlog
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
 #for the one time i encountered NSD
 nsdcheck=`ps aux |grep nsd |grep -v grep`
 if [ "$nsdcheck" ]; then
  echo "Nsd found, reloading" |tee -a $scriptlog
  nsdc rebuild
  nsdc reload
 fi

fi

#restart services
if [ $restartservices ]; then
 echo "Restarting services..." |tee -a $scriptlog
 [ -s /etc/init.d/chkservd ] && /etc/init.d/chkservd start
 /etc/init.d/httpd start
 /etc/init.d/mysql start
 /etc/init.d/exim start
 /etc/init.d/cpanel start
 /usr/local/cpanel/bin/tailwatchd --enable=Cpanel::TailWatch::ChkServd
else
 echo "Skipping restart of services..."| tee -a $scriptlog
fi


syncendtime=`date +%F.%T`

#give cpanel time to spam to screen
sleep 10
echo
#display mysqldump errors
if [ -s /tmp/mysqldump.log ]; then
 echo 
 echo 'Errors detected during mysqldumps:' |tee -a $scriptlog
 cat /tmp/mysqldump.log |tee -a $scriptlog
 echo "End of errors from /tmp/mysqldump.log." |tee -a $scriptlog
 sleep 1
fi

echo "=Actions taken:="
if [ $stopservices ]; then 
 echo "Stopped services"
 if [ $restartservices ];then echo "Restarted services"; else echo "Didnt restart services"; fi
fi
[ $copydns ] && echo "DNS was copied over from new server."

if yesNo "Remove SSH key from new server?"; then
  ssh -p${port} root@$ip "
  mv ~/.ssh/authorized_keys{,.initialsync.`date +%F`}; 
  if [ -f ~/.ssh/authorized_keys.syncbak ]; then 
    cp -rp ~/.ssh/authorized_keys{.syncbak,}; 
  fi"
fi

echo 'Final sync complete, check the screen "dbsync" on the remote server to ensure all databases imported correctly.'
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
logvars RSYNCVERSION
rsyncmajor=`echo $RSYNCVERSION |cut -d. -f1`
logvars rsyncmajor
if [ "$rsyncmajor" -lt 3 ]; then
 echo "Updating rsync..." |tee -a $scriptlog
 LOCALCENT=`cat /etc/redhat-release |awk '{print $3}'|cut -d '.' -f1`
 logvars LOCALCENT
 LOCALARCH=`uname -i`
 logvars LOCALARCH
 rpm -Uvh http://migration.sysres.liquidweb.com//rsync/rsync-3.0.0-1.el$LOCALCENT.rf.$LOCALARCH.rpm
else
 echo "Rsync up to date." |tee -a $scriptlog
fi

#REMOTECENT=`ssh -p$PORT $USER@$IP "cat /etc/redhat-release" |awk '{print $3}'|cut -d '.' -f1`
#REMOTEARCH=`ssh -p$PORT $USER@$IP "uname -i"`
#       ssh -p$PORT $USER@$IP "rpm -Uvh http://migration.sysres.liquidweb.com/rsync/rsync-3.0.0-1.el$REMOTECENT.rf.$REMOTEARCH.rpm"
}

rubygems() {
echo 
echo "Copying ruby gems over to new server." | tee -a $scriptlog
gem list | tail -n+4 | awk '{print $1}' > /root/gemlist.txt
rsync -avHPe "ssh -p$port" /root/gemlist.txt $ip:/root/
ssh -p$port $ip " cat /root/gemlist.txt | xargs gem install "

}

cpbackupcheck() {
echo "
Checking if cpanel backups are enabled on new server." |tee -a $scriptlog
backupacctssetting=`ssh -p$port $ip "grep ^BACKUPACCTS /etc/cpbackup.conf" | awk '{print $2}' `
logvars backupacctssetting
backupenablesetting=`ssh -p$port $ip "grep ^BACKUPENABLE /etc/cpbackup.conf" | awk '{print $2}' `
logvars backupenablesetting
if [ $backupacctssetting = "yes" ]; then 
  #backupaccts is true, check for backupenable also
  if [ $backupenablesetting = "yes" ]; then
    #backupenable is also true
    echo "Backups are enabled" |tee -a $scriptlog
  else
    cpbackupenable
  fi
else
  cpbackupenable
fi
}

cpbackupenable(){
echo "Cpanel backups are disabled on $ip" | tee -a $scriptlog
if yesNo "Do you want to enable backups on the remote server?"; then
    ssh -p$port $ip "sed -i.syncbak -e 's/^\(BACKUPACCTS\).*/\1 yes/g' -e 's/^\(BACKUPENABLE\).*/\1 yes/g' /etc/cpbackup.conf"
fi
  
}

logvars() {
echo "$1"="${!1}" >> $scriptlog
}

main
