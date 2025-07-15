#!/bin/bash

threads=(10)
test_script="/root/sysbench/src/lua/oltp_qgen.lua"


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

batch_count=5
query_count_per_batch=10
update_count_per_batch=10

run(){
  for thread in "${threads[@]}"; do
    echo "Start at $(date)"
    echo "$ /usr/local/bin/sysbench $test_script --table-size=$table_size --threads=$thread --rand-type=uniform --mysql-host=$mysql_host --mysql-port=$mysql_port --mysql-user=$mysql_user --mysql-password=$mysql_password --mysql-db=$mysql_db --tables=$tables --db-driver=$db_driver --report-interval=$report_interval --time=$run_time --number-of-ranges=$ranges_number --delta=$range_delta  run"

    /usr/local/bin/sysbench "$test_script" \
    --mysql-host=$mysql_host \
    --mysql-port=$mysql_port \
    --mysql-user=$mysql_user \
    --mysql-password=$mysql_password \
    --mysql-db=$mysql_db \
    --tables=$tables \
    --db-driver=$db_driver \
    --batch-count=$batch_count \
    --query-count-per-batch=$query_count_per_batch \
    --update-count-per-batch=$update_count_per_batch \
    qgen
    echo "End at $(date)"
    echo "-------------------------------------------------------"

    sleep 300s
  done
}

run
