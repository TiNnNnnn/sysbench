# Copyright (C) 2004 MySQL AB
# Copyright (C) 2004-2017 Alexey Kopytov <akopytov@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

SUBDIRS = drivers tests lua .

AM_CPPFLAGS += -DDATADIR=\"$(pkgdatadir)\" -DLIBDIR=\"$(pkglibdir)\"

bin_PROGRAMS = sysbench

# The following check will be extended as new database drivers will be added
if USE_MYSQL
mysql_ldadd = drivers/mysql/libsbmysql.a $(MYSQL_LIBS)
endif

if USE_CMP
mysql_ldadd = drivers/compare/libscmp.a $(MYSQL_LIBS)
endif

if USE_PGSQL
pgsql_ldadd = drivers/pgsql/libsbpgsql.a $(PGSQL_LIBS)
endif

sysbench_SOURCES = sysbench.c sysbench.h sb_timer.c sb_timer.h \
sb_options.c sb_options.h sb_logger.c sb_logger.h sb_list.h db_driver.h \
db_driver.c sb_histogram.c sb_histogram.h sb_rand.c sb_rand.h \
sb_thread.c sb_thread.h sb_barrier.c sb_barrier.h sb_lua.c \
sb_ck_pr.h \
sb_lua.h sb_util.h sb_util.c sb_counter.h sb_counter.c \
lua/internal/sysbench.lua.h lua/internal/sysbench.sql.lua.h \
lua/internal/sysbench.rand.lua.h lua/internal/sysbench.cmdline.lua.h  \
lua/internal/sysbench.histogram.lua.h \
xoroshiro128plus.h

sysbench_LDADD = tests/fileio/libsbfileio.a tests/threads/libsbthreads.a \
    tests/memory/libsbmemory.a tests/cpu/libsbcpu.a \
    tests/mutex/libsbmutex.a \
    $(mysql_ldadd) $(pgsql_ldadd) \
    $(LUAJIT_LIBS) $(CK_LIBS)

sysbench_LDFLAGS = $(mysql_ldflags) \
    $(pgsql_ldflags) $(LUAJIT_LDFLAGS)
