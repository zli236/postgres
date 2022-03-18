-- predictability
SET synchronous_commit = on;
-- turn on logical ddl message logging
CREATE publication mypub FOR ALL TABLES with (ddl = 'database');

-- SET USER
CREATE ROLE ddl_replication_user LOGIN SUPERUSER;
SET SESSION AUTHORIZATION 'ddl_replication_user';

SELECT 'init' FROM pg_create_logical_replication_slot('regression_slot', 'test_decoding');

CREATE TABLE test_ddlmessage (id serial unique, data int);
ALTER TABLE test_ddlmessage add c3 varchar;
ALTER TABLE test_ddlmessage drop c3;
DROP TABLE test_ddlmessage;

BEGIN;
CREATE TABLE test_ddlmessage (id serial unique, data int);
ALTER TABLE test_ddlmessage add c3 varchar;
ROLLBACK;

BEGIN;
CREATE TABLE test_ddlmessage (id serial unique, data int);
ALTER TABLE test_ddlmessage add c3 varchar;
COMMIT;

SELECT data FROM pg_logical_slot_get_changes('regression_slot', NULL, NULL, 'include-xids', '0', 'skip-empty-xacts', '1');
SELECT pg_drop_replication_slot('regression_slot');
DROP TABLE test_ddlmessage;
DROP publication mypub;

