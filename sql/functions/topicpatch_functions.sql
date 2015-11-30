

--TODO unit test
drop function remove_officer(UUID,UUID);
CREATE OR REPLACE FUNCTION remove_officer(in_topic_id UUID,in_user_id UUID) 
RETURNS void AS $$
BEGIN
  delete from topic_authority where topic_id = in_topic_id AND user_id = in_user_id AND kind = 'OFFICER';
END;
$$ LANGUAGE plpgsql;


--TODO unit test
drop function remove_assistant(UUID,UUID);
CREATE OR REPLACE FUNCTION remove_assistant(in_topic_id UUID,in_user_id UUID) 
RETURNS void AS $$
BEGIN
  delete from topic_authority where topic_id = in_topic_id AND user_id = in_user_id AND kind = 'ASSISTANT';
END;
$$ LANGUAGE plpgsql;


--TODO unit test
drop function add_assistant(UUID,UUID);
CREATE OR REPLACE FUNCTION add_assistant(in_topic_id UUID,in_user_id UUID) 
RETURNS void AS $$
BEGIN
  insert into topic_authority(topic_id,user_id,kind) values(in_topic_id,in_topic_id,'ASSISTANT');
END;
$$ LANGUAGE plpgsql;


--TODO unit test
drop function add_officer(UUID,UUID);
CREATE OR REPLACE FUNCTION add_officer(in_topic_id UUID,in_user_id UUID) 
RETURNS void AS $$
BEGIN
  insert into topic_authority(topic_id,user_id,kind) values(in_topic_id,in_topic_id,'OFFICER');
END;
$$ LANGUAGE plpgsql;


--TODO unit test
drop function replace_topic_description(UUID,text);
CREATE OR REPLACE FUNCTION replace_topic_description(in_topic_id UUID,in_new_description text) 
RETURNS void AS $$
BEGIN
  UPDATE topics set description = in_new_description where id = in_topic_id;
END;
$$ LANGUAGE plpgsql;



drop function move_module(UUID,UUID,UUID[]);
CREATE OR REPLACE FUNCTION move_module(in_context_id UUID,in_module_id UUID, in_in_new_parent_ids VARIADIC UUID[]) 
RETURNS void AS $$
DECLARE 
old_parent UUID;
root_siblings UUID[];
old_root_id UUID;
new_root_id UUID;
new_parent_id UUID;
BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM check_topic_context(in_context_id,in_module_id);

  select module_parents.parent_id into old_parent from module_parents where child_id = in_module_id;
  if old_parent is null then --this means, the moving module is currently the root module.
    select array_agg(child_id::UUID) into root_siblings from module_parents where parent_id = in_module_id;
    -- this is an edge case where the moving module is the root module and it has more than one direct descendant.
    if array_length(root_siblings,1) > 1 then
      --there can only be one root module. this update makes all siblings of the new root module to its descendants.    
      update module_parents set parent_id = root_siblings[1] where parent_id = in_module_id and child_id <> root_siblings[1]; --array index starts at 1...
    end if;
    -- after that we promote the remaining module to the new root.
    delete from module_parents where parent_id = in_module_id;
    --TODO create smarter sql statement to avoid loop
    foreach new_parent_id in ARRAY in_in_new_parent_ids
    loop
      insert into module_parents values(in_module_id, new_parent_id);
    end loop;
  else
    update module_parents set parent_id = old_parent where parent_id = in_module_id;
    delete from module_parents where child_id = in_module_id;
    if array_length(in_in_new_parent_ids,1) = 0 then -- the moving module should be the new root.
      select module_trees.id into old_root_id from module_trees where topic_id = (select topic_id from modules where id = in_module_id) AND level = 0;
      insert into module_parents values(old_root_id, in_module_id); -- the old root is now its first child.
    else
      --TODO create smarter sql statement to avoid loop
      foreach new_parent_id in ARRAY in_in_new_parent_ids
      loop
        insert into module_parents values(in_module_id, new_parent_id);
      end loop;
    end if;
  end if;
END;
$$ LANGUAGE plpgsql;

drop function check_topic_context(UUID,UUID);
CREATE OR REPLACE FUNCTION check_topic_context(in_context_id UUID, in_module_id UUID) 
RETURNS void AS $$
BEGIN
  if NOT exists(select 1 from modules m where m.id = in_module_id AND m.topic_id = in_context_id) then
    RAISE EXCEPTION 'Operation out of scope.';
  end if;
END;
$$ LANGUAGE plpgsql;




drop function move_module_tree(UUID,UUID,UUID[]);
CREATE OR REPLACE FUNCTION move_module_tree(in_context_id UUID, module_id UUID, in_new_parent_ids VARIADIC UUID[]) 
RETURNS void AS $$
DECLARE 
parent_level int;
module_level int;
old_root_id UUID;
new_parent_id UUID;
BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM check_topic_context(in_context_id,in_module_id);
  if array_length(in_new_parent_ids,1) = 0 then -- the moving module should be the new root.
    select module_trees.id into old_root_id from module_trees where topic_id = (select topic_id from modules where id = module_id) AND level = 0;
    insert into module_parents values(old_root_id, module_id); -- the old root is now its first child.
    delete from module_parents where child_id = module_id;
  else
    if exists( select 1 from (select unnest (paths) as paths from module_trees where id = new_parent_id )t where paths like '%'||module_id||'%') then
      raise notice 'found path';
      select module_trees.level into module_level from module_trees where id = module_id;
      foreach new_parent_id in ARRAY in_new_parent_ids
      loop
        select module_trees.level into parent_level from module_trees where id = new_parent_id;
        if parent_level > module_level then
          RAISE EXCEPTION 'Parent-Child cyclus. moduleID --> % parentID -->%', module_id, new_parent_id
          USING HINT = 'Please check the levels of module and new parent.';
        end if;
      end loop;
    end if;
    delete from module_parents where child_id = module_id;
    foreach new_parent_id in ARRAY in_new_parent_ids 
    loop
      insert into module_parents values(module_id,new_parent_id);
    end loop;
  end if;
END;
$$ LANGUAGE plpgsql;


drop function remove_module(UUID,UUID);
CREATE OR REPLACE FUNCTION remove_module(in_context_id UUID, in_module_id UUID) 
RETURNS void AS $$
DECLARE 
parent_level int;
module_level int;
old_root_id UUID;
old_parent UUID;
root_siblings UUID[];
BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM check_topic_context(in_context_id,in_module_id);
  select module_parents.parent_id into old_parent from module_parents where child_id = in_module_id;
  if old_parent is null then 
    select array_agg(child_id::UUID) into root_siblings from module_parents where parent_id = in_module_id;
    if array_length(root_siblings,1) > 1 then
      update module_parents set parent_id = root_siblings[1] where parent_id = module_id and child_id <> root_siblings[1];
    end if;
  else
    update module_parents set parent_id = old_parent where parent_id = in_module_id;
  end if;
  delete from modules where id = in_module_id;
END;
$$ LANGUAGE plpgsql;



drop function remove_module_tree(UUID,UUID);
CREATE OR REPLACE FUNCTION remove_module_tree(in_context_id UUID, in_module_id UUID) 
RETURNS void AS $$
DECLARE 
topic_id UUID;
BEGIN
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM check_topic_context(in_context_id,in_module_id);
  if NOT exists(select 1 from modules m where m.id = in_module_id AND m.topic_id = in_context_id) then
    RAISE EXCEPTION 'Operation out of scope.';
  end if;
  delete from modules where  id in (select id from (select id, unnest (paths) as paths from module_trees )t where paths like '%'||in_module_id||'%');
END;
$$ LANGUAGE plpgsql;



drop function add_module(UUID,UUID,text,UUID,UUID,UUID[]);
CREATE OR REPLACE FUNCTION add_module(id UUID, topic_id UUID, description text,  video_id UUID, script_id UUID,parent_ids VARIADIC UUID[]) 
RETURNS void AS $$
DECLARE
parent_id UUID;
BEGIN
  insert into modules (id,topic_id,description,video_id,script_id,version) values(id,topic_id,description,video_id,script_id,1);
  foreach parent_id in ARRAY parent_ids
  loop
    insert into module_parents(child_id, parent_id) values(id,parent_id);
  end loop;
END;
$$ LANGUAGE plpgsql;



drop function increment_version(UUID,varchar);
CREATE OR REPLACE FUNCTION increment_version(in_id UUID, version_table varchar) 
RETURNS void AS $$
DECLARE
stmt text; 
BEGIN
  stmt = 'UPDATE '||version_table||' set version = version + 1 where id = $1';
  EXECUTE stmt USING in_id;
END;
$$ LANGUAGE plpgsql;

drop function check_version(UUID,varchar,bigint);
CREATE OR REPLACE FUNCTION check_version(id UUID, version_table varchar, assumed_version bigint) 
RETURNS void AS $$
DECLARE 
real_version bigint;
stmt text; 
BEGIN
  stmt = 'SELECT version from '||version_table||' where id = $1';
  EXECUTE stmt into real_version USING id;
  if real_version > assumed_version then
    RAISE EXCEPTION 'record was modified';
  end if;
END;
$$ LANGUAGE plpgsql;

