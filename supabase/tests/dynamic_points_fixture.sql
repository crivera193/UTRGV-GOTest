-- Explicit isolated QA fixtures. Never reset an existing attack or real point.
begin;
insert into public.game_rule_sets(id,name,questions_total,question_seconds,max_damage_percent,cooldown_seconds) values
 ('qa-dynamic-custom','QA editable rules',7,120,30,180),
 ('qa-dynamic-native','QA native rules',3,15,30,180);
insert into public.game_spots(id,name,latitude,longitude,hp,max_hp,is_test,rule_set_id) values
 ('qa-dynamic-capture-20261022','QA dynamic standard capture',0,0,100,100,true,'standard'),
 ('qa-dynamic-custom-20261022','QA dynamic custom',0,0,120,120,true,'qa-dynamic-custom'),
 ('qa-dynamic-move-20261022','QA dynamic move',0,0,100,100,true,'standard'),
 ('qa-dynamic-disable-20261022','QA dynamic disable',0,0,100,100,true,'standard'),
 ('qa-dynamic-play-20261022','QA configurable free kick',0,0,100,100,true,'qa-dynamic-native'),
 ('qa-dynamic-map-20261022','QA map original',26.3067,-98.1740,100,100,true,'qa-dynamic-native');
select id,questions_total,question_seconds,max_damage_percent,cooldown_seconds from public.game_rule_sets where id in ('standard','qa-dynamic-custom','qa-dynamic-native');
commit;
