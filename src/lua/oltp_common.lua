-- Copyright (C) 2006-2018 Alexey Kopytov <akopytov@gmail.com>

-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

-- -----------------------------------------------------------------------------
-- Common code for OLTP benchmarks.
-- -----------------------------------------------------------------------------

function init()
   assert(event ~= nil,
          "this script is meant to be included by other OLTP scripts and " ..
             "should not be called directly.")
end

if sysbench.cmdline.command == nil then
   error("Command is required. Supported commands: prepare, warmup, run, " ..
            "cleanup, help")
end

-- Command line options
sysbench.cmdline.options = {
   table_size =
      {"Number of rows per table", 10000},
   range_size =
      {"Range size for range SELECT queries", 100},
   tables =
      {"Number of tables", 1},
   point_selects =
      {"Number of point SELECT queries per transaction", 10},
   simple_ranges =
      {"Number of simple range SELECT queries per transaction", 1},
   sum_ranges =
      {"Number of SELECT SUM() queries per transaction", 1},
   order_ranges =
      {"Number of SELECT ORDER BY queries per transaction", 1},
   distinct_ranges =
      {"Number of SELECT DISTINCT queries per transaction", 1},
   index_updates =
      {"Number of UPDATE index queries per transaction", 1},
   non_index_updates =
      {"Number of UPDATE non-index queries per transaction", 1},
   delete_inserts =
      {"Number of DELETE/INSERT combinations per transaction", 1},
   range_selects =
      {"Enable/disable all range SELECT queries", true},
   auto_inc =
   {"Use AUTO_INCREMENT column as Primary Key (for MySQL), " ..
       "or its alternatives in other DBMS. When disabled, use " ..
       "client-generated IDs", true},
   create_table_options =
      {"Extra CREATE TABLE options", ""},
   skip_trx =
      {"Don't start explicit transactions and execute all queries " ..
          "in the AUTOCOMMIT mode", false},
   secondary =
      {"Use a secondary index in place of the PRIMARY KEY", false},
   create_secondary =
      {"Create a secondary index in addition to the PRIMARY KEY", true},
   reconnect =
      {"Reconnect after every N events. The default (0) is to not reconnect",
       0},
   mysql_storage_engine =
      {"Storage engine, if MySQL is used", "innodb"},
   pgsql_variant =
      {"Use this PostgreSQL variant when running with the " ..
          "PostgreSQL driver. The only currently supported " ..
          "variant is 'redshift'. When enabled, " ..
          "create_secondary is automatically disabled, and " ..
          "delete_inserts is set to 0"},
   batch_count = 
      {"Number of batch", 2},
   query_count_per_batch = 
      {"Number of query count per batch", 10},
   update_count_per_batch = 
     {"Number of update count per batch", 10},
}

-- Prepare the dataset. This command supports parallel execution, i.e. will
-- benefit from executing with --threads > 1 as long as --tables > 1
function cmd_prepare()
   local drv = sysbench.sql.driver()
   local con = drv:connect()

   for i = sysbench.tid % sysbench.opt.threads + 1, sysbench.opt.tables,
   sysbench.opt.threads do
     create_table(drv, con, i)
   end
end

-- Preload the dataset into the server cache. This command supports parallel
-- execution, i.e. will benefit from executing with --threads > 1 as long as
-- --tables > 1
--
-- PS. Currently, this command is only meaningful for MySQL/InnoDB benchmarks
function cmd_warmup()
   local drv = sysbench.sql.driver()
   local con = drv:connect()

   assert(drv:name() == "mysql", "warmup is currently MySQL only")

   -- Do not create on disk tables for subsequent queries
   con:query("SET tmp_table_size=2*1024*1024*1024")
   con:query("SET max_heap_table_size=2*1024*1024*1024")

   for i = sysbench.tid % sysbench.opt.threads + 1, sysbench.opt.tables,
   sysbench.opt.threads do
      local t = "sbtest" .. i
      print("Preloading table " .. t)
      con:query("ANALYZE TABLE sbtest" .. i)
      con:query(string.format(
                   "SELECT AVG(id) FROM " ..
                      "(SELECT * FROM %s FORCE KEY (PRIMARY) " ..
                      "LIMIT %u) t",
                   t, sysbench.opt.table_size))
      con:query(string.format(
                   "SELECT COUNT(*) FROM " ..
                      "(SELECT * FROM %s WHERE k LIKE '%%0%%' LIMIT %u) t",
                   t, sysbench.opt.table_size))
   end
end

-- Implement parallel prepare and warmup commands, define 'prewarm' as an alias
-- for 'warmup'
sysbench.cmdline.commands = {
   prepare = {cmd_prepare, sysbench.cmdline.PARALLEL_COMMAND},
   warmup = {cmd_warmup, sysbench.cmdline.PARALLEL_COMMAND},
   prewarm = {cmd_warmup, sysbench.cmdline.PARALLEL_COMMAND}
}


-- Template strings of random digits with 11-digit groups separated by dashes

-- 10 groups, 119 characters
local c_value_template = "###########-###########-###########-" ..
   "###########-###########-###########-" ..
   "###########-###########-###########-" ..
   "###########"

-- 5 groups, 59 characters
local pad_value_template = "###########-###########-###########-" ..
   "###########-###########"

local workload = {}

function get_c_value()
   return sysbench.rand.string(c_value_template)
end

function get_pad_value()
   return sysbench.rand.string(pad_value_template)
end

function create_table(drv, con, table_num)
   local id_index_def, id_def
   local engine_def = ""
   local extra_table_options = ""
   local query

   if sysbench.opt.secondary then
     id_index_def = "KEY xid"
   else
     id_index_def = "PRIMARY KEY"
   end

   if drv:name() == "mysql" or drv:name() == "cmp"
   then
      if sysbench.opt.auto_inc then
         id_def = "INTEGER NOT NULL AUTO_INCREMENT"
      else
         id_def = "INTEGER NOT NULL"
      end
      engine_def = "/*! ENGINE = " .. sysbench.opt.mysql_storage_engine .. " */"
   elseif drv:name() == "pgsql"
   then
      if not sysbench.opt.auto_inc then
         id_def = "INTEGER NOT NULL"
      elseif pgsql_variant == 'redshift' then
        id_def = "INTEGER IDENTITY(1,1)"
      else
        id_def = "SERIAL"
      end
   else
      error("Unsupported database driver:" .. drv:name())
   end

   print(string.format("Creating table 'sbtest%d'...", table_num))

   query = string.format([[
CREATE TABLE sbtest%d(
  id %s,
  k INTEGER DEFAULT '0' NOT NULL,
  c CHAR(120) DEFAULT '' NOT NULL,
  pad CHAR(60) DEFAULT '' NOT NULL,
  %s (id)
) %s %s]],
      table_num, id_def, id_index_def, engine_def,
      sysbench.opt.create_table_options)

   con:query(query)

   if (sysbench.opt.table_size > 0) then
      print(string.format("Inserting %d records into 'sbtest%d'",
                          sysbench.opt.table_size, table_num))
   end

   if sysbench.opt.auto_inc then
      query = "INSERT INTO sbtest" .. table_num .. "(k, c, pad) VALUES"
   else
      query = "INSERT INTO sbtest" .. table_num .. "(id, k, c, pad) VALUES"
   end

   con:bulk_insert_init(query)

   local c_val
   local pad_val

   for i = 1, sysbench.opt.table_size do

      c_val = get_c_value()
      pad_val = get_pad_value()

      if (sysbench.opt.auto_inc) then
         query = string.format("(%d, '%s', '%s')",
                               sysbench.rand.default(1, sysbench.opt.table_size),
                               c_val, pad_val)
      else
         query = string.format("(%d, %d, '%s', '%s')",
                               i,
                               sysbench.rand.default(1, sysbench.opt.table_size),
                               c_val, pad_val)
      end

      con:bulk_insert_next(query)
   end

   con:bulk_insert_done()

   if sysbench.opt.create_secondary then
      print(string.format("Creating a secondary index on 'sbtest%d'...",
                          table_num))
      con:query(string.format("CREATE INDEX k_%d ON sbtest%d(k)",
                              table_num, table_num))
   end
end

local t = sysbench.sql.type
local stmt_defs = {
   point_selects = {
      "SELECT c FROM sbtest%u WHERE id=?",
      t.INT},
   simple_ranges = {
      "SELECT c FROM sbtest%u WHERE id BETWEEN ? AND ?",
      t.INT, t.INT},
   sum_ranges = {
      "SELECT SUM(k) FROM sbtest%u WHERE id BETWEEN ? AND ?",
       t.INT, t.INT},
   order_ranges = {
      "SELECT c FROM sbtest%u WHERE id BETWEEN ? AND ? ORDER BY c",
       t.INT, t.INT},
   distinct_ranges = {
      "SELECT DISTINCT c FROM sbtest%u WHERE id BETWEEN ? AND ? ORDER BY c",
      t.INT, t.INT},
   index_updates = {
      "UPDATE sbtest%u SET k=k+1 WHERE id=?",
      t.INT},
   non_index_updates = {
      "UPDATE sbtest%u SET c=? WHERE id=?",
      {t.CHAR, 120}, t.INT},
   deletes = {
      "DELETE FROM sbtest%u WHERE id=?",
      t.INT},
   inserts = {
      "INSERT INTO sbtest%u (id, k, c, pad) VALUES (?, ?, ?, ?)",
      t.INT, t.INT, {t.CHAR, 120}, {t.CHAR, 60}},
   selects = {
      {"SELECT t1.c, t2.k FROM sbtest1 as t1 JOIN sbtest%u as t2 ON t1.id = t2.id WHERE t1.id BETWEEN ? AND ? LIMIT 10",
      t.INT, t.INT},
      {"SELECT t1.c, t2.k FROM sbtest3 as t1 LEFT JOIN sbtest%u as t2 ON t1.c > t2.c WHERE t1.pad BETWEEN ? AND ? LIMIT 10",
         {t.CHAR, 60}, {t.CHAR, 60}},
      {"SELECT k, COUNT(*) as count FROM sbtest%u WHERE k >= ? GROUP BY k ORDER BY count DESC LIMIT 10 ",
         t.INT},
      {"SELECT c FROM sbtest%u WHERE k > ? ORDER BY k DESC LIMIT 10",
         t.INT},
      {"SELECT k, c, COUNT(*) as count FROM sbtest%u WHERE k >= ? GROUP BY k, c ORDER BY count DESC LIMIT 10",
         t.INT},
      {"SELECT c FROM sbtest%u WHERE k IN (SELECT k FROM sbtest4 WHERE id BETWEEN ? AND ?) ORDER BY k DESC LIMIT 10",
         t.INT, t.INT
      },
      {"SELECT k, COUNT(*) as count FROM sbtest%u WHERE k >= ? GROUP BY k ORDER BY count DESC LIMIT 10 OFFSET ?",
      t.INT, t.INT
      },
      {"SELECT k, COUNT(*) as count FROM sbtest%u WHERE k >= (SELECT MAX(k) from sbtest5 where c < ? GROUP BY c) GROUP BY k ORDER BY count DESC LIMIT 10",
      {t.CHAR, 120}, t.INT
      },
      {"SELECT t1.c, t2.k FROM sbtest1 as t1 JOIN sbtest%u as t2 ON t1.id = t2.id WHERE t1.id NOT IN (SELECT t3.k FROM sbtest2 as t3 where t1.c = t3.c) AND t1.id BETWEEN ? AND ? LIMIT 10",
      t.INT, t.INT},
   }
}

function workload_generate()
   local workload_file = "workload.txt"
   local batch_separator = "--BATCH_SEPARATOR--"

   -- open files
   local file = io.open(workload_file, "w")
   assert(file, "Failed to open workload file for writing")

   print("Generating workload,Batch count: " .. sysbench.opt.batch_count .. 
      ", Query count per batch: " .. sysbench.opt.query_count_per_batch .. 
      ", Update count per batch: " .. sysbench.opt.update_count_per_batch .. "")
   for batch = 1, sysbench.opt.batch_count do
      -- generate query batches
      local query_batches = {}
      for i = 1, sysbench.opt.query_count_per_batch do
         local tnum = sysbench.rand.uniform(1, sysbench.opt.tables)
         local template = stmt_defs.selects[sysbench.rand.uniform(1, #stmt_defs.selects)]
         
         -- Parameter generation based on template type
         local query = string.format(template[1], tnum)
         if #template == 2 then  -- 1-parameter query
             local param = sysbench.rand.default(1, sysbench.opt.table_size)
             query = query:gsub("%?", param)
         elseif #template == 3 then  -- 2-parameter query
             local p1 = sysbench.rand.default(1, sysbench.opt.table_size)
             local p2 = math.min(p1 + sysbench.rand.default(1, 100), sysbench.opt.table_size)
             query = query:gsub("%?", p1, 1)  -- Replace first ?
             query = query:gsub("%?", p2)     -- Replace second ?
         end
         table.insert(query_batches, query)
     end

      -- write query batches to file
      file:write("--QUERY_BATCH_START--\n")
      for _, query in ipairs(query_batches) do
         file:write(query .. "\n")
      end
      file:write(batch_separator .. "\n")

      -- generate update batches
      local update_batches = {}
      for i = 1, sysbench.opt.update_count_per_batch do
         local tnum = sysbench.rand.uniform(1, sysbench.opt.tables)
         local template = stmt_defs.index_updates
         local id = sysbench.rand.uniform(1, sysbench.opt.table_size)
         local update = string.format(template[1], tnum)
         update = string.gsub(update, "?", id)
         table.insert(update_batches, update)
      end

      -- write update batches to file
      file:write("--UPDATE_BATCH_START--\n")
      for _, update in ipairs(update_batches) do
         file:write(update .. "\n")
      end
      file:write(batch_separator .. "\n")
   end

   file:close()
   print("Workload generated and written to " .. workload_file)
end

function prepare_begin()
   stmt.begin = con:prepare("BEGIN")
end

function prepare_commit()
   stmt.commit = con:prepare("COMMIT")
end

function prepare_for_each_table(key)
   for t = 1, sysbench.opt.tables do
      stmt[t][key] = con:prepare(string.format(stmt_defs[key][1], t))

      local nparam = #stmt_defs[key] - 1

      if nparam > 0 then
         param[t][key] = {}
      end

      for p = 1, nparam do
         local btype = stmt_defs[key][p+1]
         local len

         if type(btype) == "table" then
            len = btype[2]
            btype = btype[1]
         end
         if btype == sysbench.sql.type.VARCHAR or
            btype == sysbench.sql.type.CHAR then
               param[t][key][p] = stmt[t][key]:bind_create(btype, len)
         else
            param[t][key][p] = stmt[t][key]:bind_create(btype)
         end
      end

      if nparam > 0 then
         stmt[t][key]:bind_param(unpack(param[t][key]))
      end
   end
end

function prepare_selects()
   prepare_for_each_table("selects")
end

function prepare_point_selects()
   prepare_for_each_table("point_selects")
end

function prepare_simple_ranges()
   prepare_for_each_table("simple_ranges")
end

function prepare_sum_ranges()
   prepare_for_each_table("sum_ranges")
end

function prepare_order_ranges()
   prepare_for_each_table("order_ranges")
end

function prepare_distinct_ranges()
   prepare_for_each_table("distinct_ranges")
end

function prepare_index_updates()
   prepare_for_each_table("index_updates")
end

function prepare_non_index_updates()
   prepare_for_each_table("non_index_updates")
end

function prepare_delete_inserts()
   prepare_for_each_table("deletes")
   prepare_for_each_table("inserts")
end

function thread_init()
   drv = sysbench.sql.driver()
   con = drv:connect()

   -- Create global nested tables for prepared statements and their
   -- parameters. We need a statement and a parameter set for each combination
   -- of connection/table/query
   stmt = {}
   param = {}

   for t = 1, sysbench.opt.tables do
      stmt[t] = {}
      param[t] = {}
   end

   -- This function is a 'callback' defined by individual benchmark scripts
   prepare_statements()
end

-- Close prepared statements
function close_statements()
   for t = 1, sysbench.opt.tables do
      for k, s in pairs(stmt[t]) do
         stmt[t][k]:close()
      end
   end
   if (stmt.begin ~= nil) then
      stmt.begin:close()
   end
   if (stmt.commit ~= nil) then
      stmt.commit:close()
   end
end

function thread_done()
   close_statements()
   con:disconnect()
end

function cleanup()
   local drv = sysbench.sql.driver()
   local con = drv:connect()

   for i = 1, sysbench.opt.tables do
      print(string.format("Dropping table 'sbtest%d'...", i))
      con:query("DROP TABLE IF EXISTS sbtest" .. i )
   end
end

local function get_table_num()
   return sysbench.rand.uniform(1, sysbench.opt.tables)
end

local function get_id()
   return sysbench.rand.default(1, sysbench.opt.table_size)
end

function begin()
   stmt.begin:execute()
end

function commit()
   stmt.commit:execute()
end

function execute_selects()
   local tnum = sysbench.rand.uniform(1, sysbench.opt.tables)
   local template = stmt_defs.selects[sysbench.rand.uniform(1, #stmt_defs.selects)]

   -- Generate query with parameters
   local query = string.format(template[1], tnum)
   
   if #template == 2 then  -- 1-parameter query
      if template[2] == t.INT then
         query = query:gsub("%?", get_id())
      elseif type(template[2]) == "table" and template[2][1] == t.CHAR then
         if template[2][2] == 120 then  -- c column
            query = query:gsub("%?", get_c_value())
         elseif template[2][2] == 60 then  -- pad column
            query = query:gsub("%?", get_pad_value())
         end
      end
   elseif #template == 3 then  -- 2-parameter query
      local id = get_id()
      if template[2] == t.INT then
         query = query:gsub("%?", id, 1)
      elseif type(template[2]) == "table" and template[2][1] == t.CHAR then
         if template[2][2] == 120 then  -- c column
            query = query:gsub("%?", get_c_value(), 1)
         elseif template[2][2] == 60 then  -- pad column
            query = query:gsub("%?", get_pad_value(), 1)
         end
      end
      
      if template[3] == t.INT then
         query = query:gsub("%?", id + sysbench.opt.range_size - 1)
      elseif type(template[3]) == "table" and template[3][1] == t.CHAR then
         if template[3][2] == 120 then  -- c column
            query = query:gsub("%?", get_c_value())
         elseif template[3][2] == 60 then  -- pad column
            query = query:gsub("%?", get_pad_value())
         end
      end
   end

   con:query(query)
end

function execute_point_selects()
   local tnum = get_table_num()
   local i

   for i = 1, sysbench.opt.point_selects do
      param[tnum].point_selects[1]:set(get_id())

      stmt[tnum].point_selects:execute()
   end
end

local function execute_range(key)
   local tnum = get_table_num()

   for i = 1, sysbench.opt[key] do
      local id = get_id()

      param[tnum][key][1]:set(id)
      param[tnum][key][2]:set(id + sysbench.opt.range_size - 1)

      stmt[tnum][key]:execute()
   end
end

function execute_simple_ranges()
   execute_range("simple_ranges")
end

function execute_sum_ranges()
   execute_range("sum_ranges")
end

function execute_order_ranges()
   execute_range("order_ranges")
end

function execute_distinct_ranges()
   execute_range("distinct_ranges")
end

function execute_index_updates()
   local tnum = get_table_num()

   for i = 1, sysbench.opt.index_updates do
      param[tnum].index_updates[1]:set(get_id())

      stmt[tnum].index_updates:execute()
   end
end

function execute_non_index_updates()
   local tnum = get_table_num()
   for i = 1, sysbench.opt.non_index_updates do
      param[tnum].non_index_updates[1]:set_rand_str(c_value_template)
      param[tnum].non_index_updates[2]:set(get_id())

      stmt[tnum].non_index_updates:execute()
   end
end

function execute_delete_inserts()
   local tnum = get_table_num()

   for i = 1, sysbench.opt.delete_inserts do
      local id = get_id()
      local k = get_id()

      param[tnum].deletes[1]:set(id)

      param[tnum].inserts[1]:set(id)
      param[tnum].inserts[2]:set(k)
      param[tnum].inserts[3]:set_rand_str(c_value_template)
      param[tnum].inserts[4]:set_rand_str(pad_value_template)

      stmt[tnum].deletes:execute()
      stmt[tnum].inserts:execute()
   end
end

-- Re-prepare statements if we have reconnected, which is possible when some of
-- the listed error codes are in the --mysql-ignore-errors list
function sysbench.hooks.before_restart_event(errdesc)
   if errdesc.sql_errno == 2013 or -- CR_SERVER_LOST
      errdesc.sql_errno == 2055 or -- CR_SERVER_LOST_EXTENDED
      errdesc.sql_errno == 2006 or -- CR_SERVER_GONE_ERROR
      errdesc.sql_errno == 2011    -- CR_TCP_CONNECTION
   then
      close_statements()
      prepare_statements()
   end
end

function check_reconnect()
   if sysbench.opt.reconnect > 0 then
      transactions = (transactions or 0) + 1
      if transactions % sysbench.opt.reconnect == 0 then
         close_statements()
         con:reconnect()
         prepare_statements()
      end
   end
end


-- function create_table_tpch(drv, con, table_num)
--    local id_index_def, id_def
--    local engine_def = ""
--    local extra_table_options = ""
--    local query

   -- if sysbench.opt.secondary then
   --   id_index_def = "KEY xid"
   -- else
   --   id_index_def = "PRIMARY KEY"
   -- end

   -- if drv:name() == "mysql" or drv:name() == "cmp"
   -- then
   --    if sysbench.opt.auto_inc then
   --       id_def = "INTEGER NOT NULL AUTO_INCREMENT"
   --    else
   --       id_def = "INTEGER NOT NULL"
   --    end
   --    engine_def = "/*! ENGINE = " .. sysbench.opt.mysql_storage_engine .. " */"
   -- elseif drv:name() == "pgsql"
   -- then
   --    if not sysbench.opt.auto_inc then
   --       id_def = "INTEGER NOT NULL"
   --    elseif pgsql_variant == 'redshift' then
   --      id_def = "INTEGER IDENTITY(1,1)"
   --    else
   --      id_def = "SERIAL"
   --    end
   -- else
   --    error("Unsupported database driver:" .. drv:name())
   -- end

--    print(string.format("Creating table 'sbtest%d'...", table_num))

--    query = string.format([[
--       CREATE TABLE PART%d (
--       P_PARTKEY		SERIAL,
--       P_NAME			VARCHAR(55),
--       P_MFGR			CHAR(25),
--       P_BRAND			CHAR(10),
--       P_TYPE			VARCHAR(25),
--       P_SIZE			INTEGER,
--       P_CONTAINER		CHAR(10),
--       P_RETAILPRICE	DECIMAL,
--       P_COMMENT		VARCHAR(23)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE SUPPLIER%d (
--          S_SUPPKEY		SERIAL,
--          S_NAME			CHAR(25),
--          S_ADDRESS		VARCHAR(40),
--          S_NATIONKEY		INTEGER NOT NULL, 
--          S_PHONE			CHAR(15),
--          S_ACCTBAL		DECIMAL,
--          S_COMMENT		VARCHAR(101)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE PARTSUPP%d (
--          PS_PARTKEY		INTEGER NOT NULL, 
--          PS_SUPPKEY		INTEGER NOT NULL,
--          PS_AVAILQTY		INTEGER,
--          PS_SUPPLYCOST	DECIMAL,
--          PS_COMMENT		VARCHAR(199)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE CUSTOMER (
--          C_CUSTKEY		SERIAL,
--          C_NAME			VARCHAR(25),
--          C_ADDRESS		VARCHAR(40),
--          C_NATIONKEY		INTEGER NOT NULL, -- references N_NATIONKEY
--          C_PHONE			CHAR(15),
--          C_ACCTBAL		DECIMAL,
--          C_MKTSEGMENT	CHAR(10),
--          C_COMMENT		VARCHAR(117)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE ORDERS (
--          O_ORDERKEY		SERIAL,
--          O_CUSTKEY		INTEGER NOT NULL, 
--          O_ORDERSTATUS	CHAR(1),
--          O_TOTALPRICE	DECIMAL,
--          O_ORDERDATE		DATE,
--          O_ORDERPRIORITY	CHAR(15),
--          O_CLERK			CHAR(15),
--          O_SHIPPRIORITY	INTEGER,
--          O_COMMENT		VARCHAR(79)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE LINEITEM (
--          L_ORDERKEY		INTEGER NOT NULL, 
--          L_PARTKEY		INTEGER NOT NULL, 
--          L_SUPPKEY		INTEGER NOT NULL, 
--          L_LINENUMBER	INTEGER,
--          L_QUANTITY		DECIMAL,
--          L_EXTENDEDPRICE	DECIMAL,
--          L_DISCOUNT		DECIMAL,
--          L_TAX			DECIMAL,
--          L_RETURNFLAG	CHAR(1),
--          L_LINESTATUS	CHAR(1),
--          L_SHIPDATE		DATE,
--          L_COMMITDATE	DATE,
--          L_RECEIPTDATE	DATE,
--          L_SHIPINSTRUCT	CHAR(25),
--          L_SHIPMODE		CHAR(10),
--          L_COMMENT		VARCHAR(44)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE NATION (
--          N_NATIONKEY		SERIAL,
--          N_NAME			CHAR(25),
--          N_REGIONKEY		INTEGER NOT NULL,  -- references R_REGIONKEY
--          N_COMMENT		VARCHAR(152)
--    )]],table_num)
--    con:query(query)

--    query = string.format([[
--       CREATE TABLE REGION (
--          R_REGIONKEY	SERIAL,
--          R_NAME		CHAR(25),
--          R_COMMENT	VARCHAR(152)
--    )]],table_num)
--    con:query(query)

--    if (sysbench.opt.table_size > 0) then
--       print(string.format("Inserting %d records into 'sbtest%d'",
--                           sysbench.opt.table_size, table_num))
--    end

--    con:query("ALTER TABLE PART"..table_num.." ADD PRIMARY KEY (P_PARTKEY)")
--    con:query("ALTER TABLE SUPPLIER"..table_num.." ADD PRIMARY KEY (S_SUPPKEY)")
--    con:query("ALTER TABLE PARTSUPP"..table_num.." ADD PRIMARY KEY (PS_PARTKEY, PS_SUPPKEY)")
--    con:query("ALTER TABLE CUSTOMER"..table_num.." ADD PRIMARY KEY (C_CUSTKEY)")
--    con:query("ALTER TABLE ORDERS"..table_num.." ADD PRIMARY KEY (O_ORDERKEY)")
--    con:query("ALTER TABLE LINEITEM"..table_num.." ADD PRIMARY KEY (L_ORDERKEY, L_LINENUMBER)")
--    con:query("ALTER TABLE NATION"..table_num.." ADD PRIMARY KEY (N_NATIONKEY)")
--    con:query("ALTER TABLE REGION"..table_num.." ADD PRIMARY KEY (R_REGIONKEY)")

--    if sysbench.opt.auto_inc then
--       query = "INSERT INTO sbtest" .. table_num .. "(k, c, pad) VALUES"
--    else
--       query = "INSERT INTO sbtest" .. table_num .. "(id, k, c, pad) VALUES"
--    end

--    con:bulk_insert_init(query)

--    local c_val
--    local pad_val

--    for i = 1, sysbench.opt.table_size do

--       c_val = get_c_value()
--       pad_val = get_pad_value()

--       if (sysbench.opt.auto_inc) then
--          query = string.format("(%d, '%s', '%s')",
--                                sysbench.rand.default(1, sysbench.opt.table_size),
--                                c_val, pad_val)
--       else
--          query = string.format("(%d, %d, '%s', '%s')",
--                                i,
--                                sysbench.rand.default(1, sysbench.opt.table_size),
--                                c_val, pad_val)
--       end

--       con:bulk_insert_next(query)
--    end

--    con:bulk_insert_done()

--    if sysbench.opt.create_secondary then
--       print(string.format("Creating a secondary index on 'sbtest%d'...",
--                           table_num))
--       con:query(string.format("CREATE INDEX k_%d ON sbtest%d(k)",
--                               table_num, table_num))
--    end
-- end
