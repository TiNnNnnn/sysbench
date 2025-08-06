-- ----------------------------------------------------------------------
-- OLTP Join Select Benchmark 
-- ----------------------------------------------------------------------
require("oltp_common")

function prepare_statements()
    -- use 1 query per event, rather than sysbench.opt.point_selects which
    -- defaults to 10 in other OLTP scripts
    sysbench.opt.point_selects=1
    prepare_index_joins()   
end

function event()
    execute_index_join()
    check_reconnect()
end