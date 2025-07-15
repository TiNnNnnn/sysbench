#!/bin/bash

test_script="/root/sysbench/src/lua/oltp_common.lua"

mysql_host="127.0.0.1","127.0.0.1"
mysql_port=33061,33062
mysql_user="mysql","mysql"
mysql_password="Yyk123456","Yyk123456"

table_size=200
mysql_db="sysbench"
tables=10
db_driver="cmp"
report_interval=10
run_time=1800


run(){
      echo "Start at $(date)"
      echo "$ sysbench $test_script --table-size=$table_size --mysql-host=$mysql_host --mysql-port=$mysql_port --mysql-user=$mysql_user --mysql-password=$mysql_password --mysql-db=$mysql_db --tables=$tables --db-driver=$db_driver --report-interval=$report_interval --time=$run_time prepare"

      sysbench "$test_script" --table-size=$table_size --mysql-host=$mysql_host --mysql-port=$mysql_port --mysql-user=$mysql_user --mysql-password=$mysql_password --mysql-db=$mysql_db --tables=$tables --db-driver=$db_driver --report-interval=$report_interval --time=$run_time prepare

      echo "End at $(date)"
      echo "-------------------------------------------------------"
}

run
