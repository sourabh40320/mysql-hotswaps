-- hot swap for data archival in mysql
-- requirement - auto update time column should be present in table.
-- example table -
-- CREATE TABLE IF NOT EXISTS temp.`event` (
--   `id` bigint(20) NOT NULL AUTO_INCREMENT,
--   `customer_id` int(11) NOT NULL,
--   `unique_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
--   `event_time` datetime NOT NULL,
--   `auto_update_time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
--   PRIMARY KEY (`id`),
--   UNIQUE KEY `event` (`customer_id`,`unique_id`),
--   KEY `auto_update_time_idx` (`auto_update_time`)
-- ) ;
-- set the min_id below which all the records will be archived.
-- all the records including min_id would be present in table.
-- lock table statement will introduce slight downtime to copy records inserted since script started.

set @min_id=2;

create table if not exists temp.temp_table like temp.event;

TRUNCATE temp.`temp_table`;

set @max_id = 0;
select max(id) into @max_id from temp.event;

INSERT into temp.`temp_table` (id, customer_id, unique_id, event_time, auto_update_time) 
select id, customer_id, unique_id, event_time, auto_update_time 
from temp.event where id>=@min_id and id<=@max_id;

lock tables temp.event e WRITE, temp.event WRITE, temp.temp_table WRITE;

insert into temp.temp_table (id, customer_id, unique_id, event_time, auto_update_time) 
select id, customer_id, unique_id, event_time, auto_update_time 
from temp.event e 
where e.id > @max_id;

ALTER TABLE temp.event RENAME TO temp.event_old;
ALTER TABLE temp.temp_table RENAME TO temp.event;

unlock tables;

update temp.event t 
join temp.event_old e 
on t.id = e.id 
set t.auto_update_time = e.auto_update_time 
where t.auto_update_time < e.auto_update_time;
