-- create schema
create schema if not exists mach_dev;

-- create user 
create user if not exists mach_dev identified by 'mach_dev123';

-- grant user full access to schema
grant all on mach_dev.* to 'mach_dev';
grant all on mach_test.* to 'mach_dev';
