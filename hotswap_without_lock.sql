-- hot swap for data archival in mysql with no downtime
-- requirement - auto update time column should be present in table to capture the updates since script started.
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
-- n_copy_iterations = number of times to copy from table to temp table.
-- auto_inc_increase = increase in auto increment of table to prevent data overwrite.

set @min_id=20000000;
set @n_copy_iterations=3;
set @auto_inc_increase=1000000;

create table if not exists temp.temp_table like temp.event;

TRUNCATE temp.`temp_table`;

set @max_id = 0;

select max(id) into @max_id from temp.event;

INSERT into temp.`temp_table` (id, customer_id, unique_id, event_time, auto_update_time) 
select id, customer_id, unique_id, event_time, auto_update_time 
from temp.event where id>=@min_id and id<=@max_id;

drop procedure temp.copy_data_temp;
delimiter #
create procedure temp.copy_data_temp()
begin
  set @i=0;
  while @i < @n_copy_iterations do

    set @min_id=@max_id;

    select max(id) into @max_id from temp.event;

    SET @SQL1 = 'INSERT into temp.`temp_table` (id, customer_id, unique_id, event_time, auto_update_time) 
                select id, customer_id, unique_id, event_time, auto_update_time 
                from temp.event where id>@min_id and id<=@max_id;';
    
    PREPARE stmt1 FROM @SQL1;
    EXECUTE stmt1;
    DEALLOCATE PREPARE stmt1;

    set @i=@i+1;
  end while;
end #

delimiter ;

call temp.copy_data_temp();

set @new_auto_increment=@max_id+@auto_inc_increase;
SET @sql = CONCAT('ALTER TABLE temp.`temp_table` AUTO_INCREMENT = ', @new_auto_increment);
PREPARE st FROM @sql;
EXECUTE st;

RENAME TABLE temp.event TO temp.event_old, temp.temp_table TO temp.event;

insert into temp.event (id, customer_id, unique_id, event_time, auto_update_time) 
select id, customer_id, unique_id, event_time, auto_update_time  
from temp.event_old e 
where e.id > @max_id;

update temp.event t 
join temp.event_old e 
on t.id = e.id 
set t.auto_update_time = e.auto_update_time 
where t.auto_update_time < e.auto_update_time;

drop procedure temp.copy_data_temp;
