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