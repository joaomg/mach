-- drop schema if it exists 
drop schema if exists mach_test;

-- create empty schema
create schema mach_test;

-- move session to schema
use mach_test;

-- create schema tables
drop table if exists tenant;
create table tenant (
 id smallint unsigned not null auto_increment
,hash char(40) not null
,name varchar(16) not null
,primary key (id)
,unique key (hash)
,unique key (name)
) engine=innodb;
