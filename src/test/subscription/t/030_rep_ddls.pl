
# Copyright (c) 2022, PostgreSQL Global Development Group

# Regression tests for logical replication of DDLs
use strict;
use warnings;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node_publisher = PostgreSQL::Test::Cluster->new('publisher');
$node_publisher->init(allows_streaming => 'logical');
$node_publisher->append_conf('postgresql.conf', 'autovacuum = off');
$node_publisher->start;

my $node_subscriber = PostgreSQL::Test::Cluster->new('subscriber');
$node_subscriber->init(allows_streaming => 'logical');
$node_subscriber->append_conf('postgresql.conf', 'autovacuum = off');
$node_subscriber->start;

my $node_subscriber2 = PostgreSQL::Test::Cluster->new('subscriber2');
$node_subscriber2->init(allows_streaming => 'logical');
$node_subscriber2->append_conf('postgresql.conf', 'autovacuum = off');
$node_subscriber2->start;

my $ddl = "CREATE TABLE test_rep(id int primary key, name varchar);";
$node_publisher->safe_psql('postgres', $ddl);
$node_publisher->safe_psql('postgres', "INSERT INTO test_rep VALUES (1, 'data1');");
$node_subscriber->safe_psql('postgres', $ddl);
$node_subscriber2->safe_psql('postgres', $ddl);

my $publisher_connstr = $node_publisher->connstr . ' dbname=postgres';

# mypub has pubddl_database on
$node_publisher->safe_psql('postgres',
	"CREATE PUBLICATION mypub FOR ALL TABLES;");
$node_subscriber->safe_psql('postgres',
	"CREATE SUBSCRIPTION mysub CONNECTION '$publisher_connstr' PUBLICATION mypub;"
);
# mypub2 has pubddl_database off
$node_publisher->safe_psql('postgres',
	"CREATE PUBLICATION mypub2 FOR ALL TABLES with (ddl = '');");
$node_subscriber2->safe_psql('postgres',
	"CREATE SUBSCRIPTION mysub2 CONNECTION '$publisher_connstr' PUBLICATION mypub2;"
);

$node_publisher->wait_for_catchup('mysub');

# Test simple CREATE TABLE command is replicated to subscriber
# Test smae simple CREATE TABLE command is not replicated to subscriber2 (ddl off)
# Test ALTER TABLE command is replicated on table test_rep
# Test CREATE INDEX is replicated to subscriber
# Test CREATE FUNCTION command is replicated to subscriber
$node_publisher->safe_psql('postgres', "CREATE TABLE t1 (a int, b varchar);");
$node_publisher->safe_psql('postgres', "ALTER TABLE test_rep ADD c3 int;");
$node_publisher->safe_psql('postgres', "INSERT INTO test_rep VALUES (2, 'data2', 2);");
$node_publisher->safe_psql('postgres', "CREATE INDEX nameindex on test_rep (name)");
$node_publisher->safe_psql('postgres', qq{CREATE OR REPLACE FUNCTION totalRecords()
RETURNS integer AS \$total\$
declare
	total integer;
BEGIN
   SELECT count(*) into total FROM test_rep;
   RETURN total;
END;
\$total\$ LANGUAGE plpgsql;});

$node_publisher->wait_for_catchup('mysub');

my $result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from t1");
is($result, qq(0), 'CREATE of t1 replicated to subscriber');
$result = $node_subscriber2->safe_psql('postgres', "SELECT count(*) from pg_tables where tablename = 't1';");
is($result, qq(0), 'CREATE of t1 is not replicated to subscriber2');
$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM test_rep WHERE c3 =2;");
is($result, qq(1), 'ALTER test_rep ADD replicated');
$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM pg_class where relname = 'nameindex'");
is($result, qq(1), 'CREATE INDEX nameindex replicated');
$result = $node_subscriber->safe_psql('postgres', "SELECT totalRecords();");
is($result, qq(2), 'CREATE of function totalRecords replicated to subscriber');
$result = $node_subscriber2->safe_psql('postgres', "SELECT count(*) FROM pg_proc where proname = 'totalrecords';");
is($result, qq(0), 'CREATE FUNCTION totalrecords is not replicated to subscriber2');

# Test ALTER TABLE DROP
# Test DROP INDEX
# Test DROP FUNCTION
$node_publisher->safe_psql('postgres', "ALTER TABLE test_rep DROP c3;");
$node_publisher->safe_psql('postgres', "DELETE FROM test_rep where id = 2;");
$node_publisher->safe_psql('postgres', "DROP INDEX nameindex;");
$node_publisher->safe_psql('postgres', "DROP FUNCTION totalRecords;");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from test_rep;");
is($result, qq(1), 'ALTER test_rep DROP replicated');
$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM pg_class where relname = 'nameindex'");
is($result, qq(0), 'DROP INDEX nameindex replicated');
$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM pg_proc where proname = 'totalrecords';");
is($result, qq(0), 'DROP FUNCTION totalrecords replicated');


# TODO figure out how to set ON_ERROR_STOP = 0 in this test
# Test failed CREATE/ALTER TABLE on publisher doesn't break replication
# Table t1 already exits so expect the command to fail
#$node_publisher->safe_psql('postgres', "CREATE TABLE t1 (a int, b varchar);");
#$node_publisher->safe_psql('postgres', "ALTER TABLE test_rep DROP c3;");
#$node_publisher->safe_psql('postgres', "INSERT INTO test_rep VALUES (103, 'data103', 1013);");

#$node_publisher->wait_for_catchup('mysub');
# Verify replication still works
#$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from test_rep;");
#is($result, qq(1), 'DELETE from test_rep replicated');

# Test DDLs inside txn block
$node_publisher->safe_psql(
	'postgres', q{
BEGIN;
CREATE TABLE t2 (a int, b varchar);
ALTER TABLE test_rep ADD c3 int;
INSERT INTO test_rep VALUES (3, 'data3', 3);
COMMIT;});

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from t2;");
is($result, qq(0), 'CREATE t2 replicated');
$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM test_rep;");
is($result, qq(2), 'ALTER test_rep ADD replicated');

# Test toggling pubddl_database option off
$node_publisher->safe_psql('postgres', "ALTER PUBLICATION mypub set (ddl = '');");
$result = $node_publisher->safe_psql('postgres', "SELECT pubddl_database, pubddl_table from pg_publication where pubname = 'mypub';");
is($result, qq(f|f), 'pubddl_database turned off on mypub');
$node_publisher->safe_psql('postgres', "CREATE TABLE t3 (a int, b varchar);");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from pg_tables where tablename = 't3';");
is($result, qq(0), 'CREATE t3 is not replicated');

# Test toggling pubddl_database option on
$node_publisher->safe_psql('postgres', "ALTER PUBLICATION mypub set (ddl = 'database');");
$result = $node_publisher->safe_psql('postgres', "SELECT pubddl_database, pubddl_table from pg_publication where pubname = 'mypub';");
is($result, qq(t|t), 'pubddl_database turned on on mypub');

$node_publisher->safe_psql('postgres', "CREATE TABLE t4 (a int, b varchar);");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from pg_tables where tablename = 't4';");
is($result, qq(1), 'CREATE t4 is replicated');

# Test DML changes on the new table t4 are replicated
$node_publisher->safe_psql('postgres', "INSERT INTO t4 values (1, 'a')");
$node_publisher->safe_psql('postgres', "INSERT INTO t4 values (2, 'b')");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from t4;");
is($result, qq(2), 'DML Changes to t4 are replicated');

# A somewhat complicated test in plpgsql block with trigger
$node_publisher->safe_psql(
	'postgres', q{
BEGIN;
CREATE TABLE foo (a int);
CREATE INDEX foo_idx ON foo (a);
ALTER TABLE foo ADD COLUMN b timestamptz;
CREATE FUNCTION foo_ts()
RETURNS trigger AS $$
BEGIN
NEW.b := current_timestamp;
RETURN NEW;
END;
$$
LANGUAGE plpgsql;
CREATE TRIGGER foo_ts BEFORE INSERT OR UPDATE ON foo
FOR EACH ROW EXECUTE FUNCTION foo_ts();
INSERT INTO foo VALUES (1);
COMMIT;});
$result = $node_publisher->safe_psql('postgres', "SELECT b from foo where a = 1;");

$node_publisher->wait_for_catchup('mysub');

my $result_sub = $node_subscriber->safe_psql('postgres', "SELECT b from foo where a = 1;");
is($result, qq($result_sub), 'timestamp of insert matches');

# Test CREATE SCHEMA stmt is replicated
$node_publisher->safe_psql('postgres', "CREATE SCHEMA s1");
$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM pg_catalog.pg_namespace WHERE nspname = 's1';");
is($result, qq(1), 'CREATE SCHEMA s1 is replicated');

# Test CREATE TABLE in new schema s1 followed by insert
$node_publisher->safe_psql('postgres', "CREATE TABLE s1.t1 (a int, b varchar);");
$node_publisher->safe_psql('postgres', "INSERT INTO s1.t1 VALUES (1, 'a');");
$node_publisher->safe_psql('postgres', "INSERT INTO s1.t1 VALUES (2, 'b');");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM s1.t1;");
is($result, qq(2), 'CREATE TABLE s1.t1 is replicated');

# Test replication works as expected with mismatched search_path on publisher and subscriber
$node_publisher->append_conf('postgresql.conf', 'search_path = \'s1, public\'');
$node_publisher->restart;
# CREATE unqualified table t2, it is s1.t2 under the modified search_path
$node_publisher->safe_psql('postgres', "CREATE TABLE t2 (a int, b varchar);");
$node_publisher->safe_psql('postgres', "INSERT INTO t2 VALUES (1, 'a');");
$node_publisher->safe_psql('postgres', "INSERT INTO t2 VALUES (2, 'b');");
$node_publisher->safe_psql('postgres', "INSERT INTO t2 VALUES (3, 'c');");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) FROM s1.t2;");
is($result, qq(3), 'CREATE TABLE s1.t2 is replicated');

# Test owner of new table on subscriber matches the owner on publisher
$node_publisher->safe_psql('postgres', "CREATE ROLE ddl_replication_user LOGIN SUPERUSER;");

$node_subscriber->safe_psql('postgres', "CREATE ROLE ddl_replication_user LOGIN SUPERUSER;");

$node_publisher->safe_psql('postgres', "SET SESSION AUTHORIZATION 'ddl_replication_user'; CREATE TABLE t5 (a int, b varchar);");
$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT tableowner from pg_catalog.pg_tables where tablename = 't5';");
is($result, qq(ddl_replication_user), 'Owner of t5 is correct');

# Test CREATE MATERIALIZED VIEW stmt is replicated
$node_publisher->safe_psql('postgres', "CREATE MATERIALIZED VIEW s1.matview1 AS SELECT a, b from s1.t1;");
$result = $node_publisher->safe_psql('postgres', "SELECT count(*) from s1.matview1;");

$node_publisher->wait_for_catchup('mysub');

$result_sub = $node_subscriber->safe_psql('postgres', "SELECT count(*) from s1.matview1;");
is($result, qq($result_sub), 'CREATE of s1.matview1 is replicated');

# Test CREATE VIEW stmt is replicated
$node_publisher->safe_psql('postgres', "CREATE VIEW s1.view1 AS SELECT a, b from s1.t1;");
$result = $node_publisher->safe_psql('postgres', "SELECT count(*) from s1.view1;");

$node_publisher->wait_for_catchup('mysub');

$result_sub = $node_subscriber->safe_psql('postgres', "SELECT count(*) from s1.view1;");
is($result, qq($result_sub), 'CREATE of s1.view1 is replicated');

# TEST CREATE TABLE AS stmt
$node_publisher->safe_psql('postgres', "CREATE TABLE s1.t3 AS SELECT a, b from s1.t1;");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from s1.t3;");
is($result, qq(2), 'CREATE TABLE s1.t3 AS is replicated with data');

# TEST CREATE TABLE AS stmt ... WITH NO DATA
$node_publisher->safe_psql('postgres', "CREATE TABLE s1.t4 AS SELECT a, b from s1.t1 WITH NO DATA;");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from s1.t4;");
is($result, qq(0), 'CREATE TABLE s1.t4 AS is replicated with no data');

# TEST SELECT INTO stmt
$node_publisher->safe_psql('postgres', "SELECT b into s1.t6 from s1.t1 where a > 1");

$node_publisher->wait_for_catchup('mysub');

$result = $node_subscriber->safe_psql('postgres', "SELECT count(*) from s1.t6;");
is($result, qq(1), 'SELECT INTO s1.t6 is replicated with data');

#TODO TEST certain DDLs are not replicated

pass "DDL replication tests passed!";

$node_subscriber->stop;
$node_subscriber2->stop;
$node_publisher->stop;

done_testing();
