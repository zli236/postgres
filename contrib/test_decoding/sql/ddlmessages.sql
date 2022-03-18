-- predictability
SET synchronous_commit = on;
-- turn on logical ddl message logging
CREATE publication mypub FOR ALL TABLES with (ddl = 'database');

SELECT 'init' FROM pg_create_logical_replication_slot('regression_slot', 'test_decoding');

CREATE TABLE tab1 (id serial unique, data int);
ALTER TABLE tab1 add c3 varchar;
ALTER TABLE tab1 drop c3;
DROP TABLE tab1;

BEGIN;
CREATE TABLE tab1 (id serial unique, data int);
ALTER TABLE tab1 add c3 varchar;
ROLLBACK;

BEGIN;
CREATE TABLE tab1 (id serial unique, data int);
ALTER TABLE tab1 add c3 varchar;
COMMIT;

\o | sed 's/role.*search_path/role: redacted, search_path/g'
SELECT data FROM pg_logical_slot_get_changes('regression_slot', NULL, NULL, 'include-xids', '0', 'skip-empty-xacts', '1');
SELECT pg_drop_replication_slot('regression_slot');
DROP TABLE tab1;
DROP publication mypub;

