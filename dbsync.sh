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

