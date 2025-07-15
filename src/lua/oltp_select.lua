-- ----------------------------------------------------------------------
-- OLTP compare workload
-- ----------------------------------------------------------------------

require("oltp_common")

function prepare_statements()
end

function event()
    execute_selects()
    check_reconnect()
end
