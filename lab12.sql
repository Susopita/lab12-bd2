SELECT version(); 
SET max_parallel_workers_per_gather = 0;
SET jit = off;
SET enable_partition_pruning = on;

CREATE TABLE employees (
emp_no int,
birth_date date,
first_name varchar(14),
last_name varchar(16),
gender character(1),
hire_date date,
dept_no varchar(5),
from_date date
);

CREATE TABLE salaries (
emp_no int,
salary int ,
from_date date,
to_date date
);

VACUUM ANALYZE employees;
VACUUM ANALYZE salaries;

SELECT pg_size_pretty(pg_relation_size('employees'));
SELECT relpages FROM pg_class WHERE relname = 'employees';

CREATE EXTENSION pgstattuple;
SELECT * FROM pgstattuple('employees');

-- Parte 1
SELECT dept_no, COUNT(*) as total_filas 
FROM employees
GROUP BY dept_no 
ORDER BY total_filas DESC;

-- 1) Tabla particionada por LIST en dept_no
CREATE TABLE employees1 (
  emp_no int,
  birth_date date,
  first_name varchar(14),
  last_name varchar(16),
  gender character(1),
  hire_date date,
  dept_no varchar(5),
  from_date date
) PARTITION BY LIST (dept_no);

-- 2) Fragmentos
CREATE TABLE employees1_p1 PARTITION OF employees1 FOR VALUES IN ('d005','d009');
CREATE TABLE employees1_p2 PARTITION OF employees1 FOR VALUES IN ('d004','d008','d001');
CREATE TABLE employees1_p3 PARTITION OF employees1 FOR VALUES IN ('d007','d006','d003','d002');

-- 3) Carga de datos
INSERT INTO employees1 SELECT * FROM employees;

-- 4) VACUUM ANALYZE
VACUUM ANALYZE employees1;

-- Q1
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees WHERE dept_no = 'd009';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees1 WHERE dept_no = 'd009';

-- Q2
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees WHERE dept_no IN ('d009', 'd001');
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees1 WHERE dept_no IN ('d009', 'd001');

-- Q3
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees WHERE last_name = 'Facello';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees1 WHERE last_name = 'Facello';

-- Q4
SET enable_partition_pruning = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees WHERE dept_no = 'd009';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees1 WHERE dept_no = 'd009';
SET enable_partition_pruning = on;

-- Q5
CREATE TABLE employees1_default PARTITION OF employees1 DEFAULT;

INSERT INTO employees1 (emp_no, birth_date, first_name, last_name, gender, hire_date, dept_no, from_date)
VALUES (500000, '1945-04-03', 'xd', 'dx', 'M', '1944-03-25', 'd010', '1945-03-23');

SELECT tableoid::regclass AS particion_destino, emp_no, first_name, last_name, dept_no FROM employees1 WHERE emp_no = 500000;
SELECT tableoid::regclass AS particion, COUNT(*) AS filas FROM employees1 GROUP BY tableoid ORDER BY particion;
EXPLAIN SELECT * FROM employees1 WHERE dept_no = 'd010';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM employees1 WHERE dept_no = 'd010';
SELECT c.relname AS particion, pg_get_expr(c.relpartbound, c.oid) AS bounds FROM pg_class c JOIN pg_inherits i ON i.inhrelid = c.oid WHERE i.inhparent = 'employees1'::regclass ORDER BY c.relname;

-- Distribucion de Particiones
SELECT tableoid::regclass AS particion, COUNT(*) AS total_filas FROM employees1 GROUP BY tableoid ORDER BY total_filas DESC;

-- ===== employees1_mal: particionado LIST deliberadamente desbalanceado =====
DROP TABLE IF EXISTS employees1_mal;

CREATE TABLE employees1_mal (
  emp_no int,
  birth_date date,
  first_name varchar(14),
  last_name varchar(16),
  gender character(1),
  hire_date date,
  dept_no varchar(5),
  from_date date
) PARTITION BY LIST (dept_no);

-- fragmento GRANDE: 6 departamentos (276,354 filas)
CREATE TABLE frag_grande PARTITION OF employees1_mal
  FOR VALUES IN ('d005','d004','d007','d009','d008','d001');

-- fragmentos PEQUEÑOS: 1 y 2 departamentos
CREATE TABLE frag_peq1 PARTITION OF employees1_mal
  FOR VALUES IN ('d006');                                   -- 20,117 filas

CREATE TABLE frag_peq2 PARTITION OF employees1_mal
  FOR VALUES IN ('d003','d002');                            -- 35,132 filas

INSERT INTO employees1_mal SELECT * FROM employees;

VACUUM ANALYZE employees1_mal;

-- Rebalanceo
BEGIN;

-- 1) Separar el fragmento grande (6 deptos) en dos
ALTER TABLE employees1_mal DETACH PARTITION frag_grande;
CREATE TABLE frag_grande_a PARTITION OF employees1_mal FOR VALUES IN ('d005','d009','d001');
CREATE TABLE frag_grande_b PARTITION OF employees1_mal FOR VALUES IN ('d004','d007','d008');
INSERT INTO employees1_mal SELECT * FROM frag_grande;
DROP TABLE frag_grande;

-- 2) Combinar los dos fragmentos pequeños (1 y 2 deptos) en uno
ALTER TABLE employees1_mal DETACH PARTITION frag_peq1;
ALTER TABLE employees1_mal DETACH PARTITION frag_peq2;
CREATE TABLE frag_peq PARTITION OF employees1_mal FOR VALUES IN ('d006','d003','d002');
INSERT INTO employees1_mal SELECT * FROM frag_peq1;
INSERT INTO employees1_mal SELECT * FROM frag_peq2;
DROP TABLE frag_peq1;
DROP TABLE frag_peq2;

COMMIT;

VACUUM ANALYZE employees1_mal;

-- Rebalanceo con sleep

BEGIN;
ALTER TABLE employees1_mal DETACH PARTITION frag_grande;
SELECT pg_sleep(20);
CREATE TABLE frag_grande_a PARTITION OF employees1_mal FOR VALUES IN ('d005','d009','d001');
CREATE TABLE frag_grande_b PARTITION OF employees1_mal FOR VALUES IN ('d004','d007','d008');
INSERT INTO employees1_mal SELECT * FROM frag_grande;
DROP TABLE frag_grande;
ALTER TABLE employees1_mal DETACH PARTITION frag_peq1;
ALTER TABLE employees1_mal DETACH PARTITION frag_peq2;
CREATE TABLE frag_peq PARTITION OF employees1_mal FOR VALUES IN ('d006','d003','d002');
INSERT INTO employees1_mal SELECT * FROM frag_peq1;
INSERT INTO employees1_mal SELECT * FROM frag_peq2;
DROP TABLE frag_peq1;
DROP TABLE frag_peq2;
COMMIT;
