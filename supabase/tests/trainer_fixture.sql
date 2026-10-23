-- One-time isolated QA points; never reset real point HP or account cooldowns.
insert into public.game_spots(id,name,latitude,longitude,hp,max_hp,is_test) values
 ('qa-trainer-perfect-20261022','QA trainer perfect',0,0,100,100,true),
 ('qa-trainer-capture-20261022','QA trainer capture',0,0,25,100,true),
 ('qa-trainer-mixed-20261022','QA trainer mixed',0,0,100,100,true),
 ('qa-trainer-early-20261022','QA trainer early capture',0,0,6.25,100,true);
