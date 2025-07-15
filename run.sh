#!/bin/bash

threads=150
#test_script="/root/sysbench/src/lua/oltp_point_select.lua"
#test_script="/root/sysbench/src/lua/oltp_update_non_index.lua"
#test_script="/root/sysbench/src/lua/oltp_update_index.lua"
test_script="/root/sysbench/src/lua/oltp_select.lua"
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
ranges_number=1
range_delta=101

run(){
  
  echo "Start at $(date)"
  echo "$ /usr/local/bin/sysbench $test_script --table-size=$table_size --threads=$threads --rand-type=uniform --mysql-host=$mysql_host --mysql-port=$mysql_port --mysql-user=$mysql_user --mysql-password=$mysql_password --mysql-db=$mysql_db --tables=$tables --db-driver=$db_driver --report-interval=$report_interval --time=$run_time --number-of-ranges=$ranges_number --delta=$range_delta  run"

  /usr/local/bin/sysbench "$test_script" \
    --table-size=$table_size \
    --threads=$threads \
    --rand-type=uniform \
    --mysql-host=$mysql_host \
    --mysql-port=$mysql_port \
    --mysql-user=$mysql_user \
    --mysql-password=$mysql_password \
    --mysql-db=$mysql_db \
    --tables=$tables \
    --db-driver=$db_driver \
    --report-interval=$report_interval \
    --time=$run_time run
    
  echo "End at $(date)"
  echo "-------------------------------------------------------"
}

run
