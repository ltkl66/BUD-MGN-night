-- ============================================================
-- 黑金之夜 SPR · 看板改数 v7：允许管理员修改「活动日期」
-- 2026-10-19
--
-- 前置：supabase_store_admin.sql 已执行（依赖 assert_admin_pin）
-- 作用：在看板「修改数据」弹窗里，除了门店名，活动日期也能改。
--       门店名与日期共同构成主键，改任一项 = 把这条记录搬到新主键下。
--
-- 冲突处理（与 v2 改门店名一致）：
--   p_on_conflict = 'error'   → 目标「门店+日期」已有记录时报错，前端弹窗询问是否覆盖
--   p_on_conflict = 'replace' → 删掉目标那条，把当前这条搬过去
--
-- 旧函数 update_spr_record / update_spr_record2 全部保留，不受影响。
-- ============================================================

create or replace function public.update_spr_record3(
  p_pin                text,
  p_old_store_name     text,
  p_old_activity_date  date,
  p_new_store_name     text,
  p_new_activity_date  date,
  p_on_conflict        text,
  p_m3                 text,
  p_spr_name           text,
  p_mechanism1         integer,
  p_mechanism2         integer,
  p_mechanism3         integer,
  p_mechanism4         integer,
  p_bud_classic_gold   integer,
  p_blackgold_1l       integer,
  p_blackgold_500      integer,
  p_blackgold_600      integer,
  p_blackgold_330      integer,
  p_blackgold_250      integer,
  p_other_abi          integer,
  p_key_competitor     integer,
  p_other_competitor   integer
) returns public.spr_records
language plpgsql
security definer
set search_path = public
as $$
declare
  r             public.spr_records;
  v_old_store   text := btrim(coalesce(p_old_store_name, ''));
  v_new_store   text := btrim(coalesce(p_new_store_name, ''));
  v_old_date    date := p_old_activity_date;
  v_new_date    date := coalesce(p_new_activity_date, p_old_activity_date);
  v_mode        text := coalesce(nullif(btrim(coalesce(p_on_conflict, '')), ''), 'error');
  v_key_changed boolean;
  v_gift        integer;
  v_bg          integer;
  v_abi         integer;
  v_comp        integer;
begin
  perform public.assert_admin_pin(p_pin);

  if v_old_store = '' then
    raise exception '原门店名不能为空';
  end if;
  if v_old_date is null then
    raise exception '原活动日期不能为空';
  end if;
  if v_new_store = '' then
    v_new_store := v_old_store;           -- 没传新名字就当作不改
  end if;
  if v_new_date is null then
    v_new_date := v_old_date;             -- 没传新日期就当作不改
  end if;
  if v_mode not in ('error', 'replace') then
    raise exception 'p_on_conflict 必须是 error 或 replace';
  end if;

  -- 原记录必须存在
  if not exists (
       select 1 from public.spr_records
        where store_name = v_old_store and activity_date = v_old_date
     ) then
    raise exception '记录不存在：% / %', v_old_store, v_old_date;
  end if;

  v_key_changed := (v_new_store <> v_old_store) or (v_new_date <> v_old_date);

  -- 主键冲突检查：目标「门店 + 日期」已被占用
  if v_key_changed and exists (
       select 1 from public.spr_records
        where store_name = v_new_store and activity_date = v_new_date
     ) then
    if v_mode = 'replace' then
      delete from public.spr_records
       where store_name = v_new_store and activity_date = v_new_date;
    else
      raise exception 'KEY_CONFLICT 目标「%」在 % 已有一条记录', v_new_store, v_new_date;
    end if;
  end if;

  v_gift := coalesce(p_mechanism1,0) + coalesce(p_mechanism2,0) + coalesce(p_mechanism3,0) + coalesce(p_mechanism4,0);
  v_bg   := coalesce(p_blackgold_1l,0) + coalesce(p_blackgold_500,0) + coalesce(p_blackgold_600,0) + coalesce(p_blackgold_330,0) + coalesce(p_blackgold_250,0);
  v_abi  := coalesce(p_bud_classic_gold,0) + v_bg + coalesce(p_other_abi,0);
  v_comp := coalesce(p_key_competitor,0) + coalesce(p_other_competitor,0);

  update public.spr_records set
    store_name        = v_new_store,
    activity_date     = v_new_date,
    m3                = coalesce(p_m3, m3),
    spr_name          = coalesce(p_spr_name, spr_name),
    mechanism1        = coalesce(p_mechanism1, mechanism1),
    mechanism2        = coalesce(p_mechanism2, mechanism2),
    mechanism3        = coalesce(p_mechanism3, mechanism3),
    mechanism4        = coalesce(p_mechanism4, mechanism4),
    gift_255_cans     = v_gift,
    bud_classic_gold  = coalesce(p_bud_classic_gold, bud_classic_gold),
    blackgold_1l      = coalesce(p_blackgold_1l, blackgold_1l),
    blackgold_500     = coalesce(p_blackgold_500, blackgold_500),
    blackgold_600     = coalesce(p_blackgold_600, blackgold_600),
    blackgold_330     = coalesce(p_blackgold_330, blackgold_330),
    blackgold_250     = coalesce(p_blackgold_250, blackgold_250),
    blackgold_total   = v_bg,
    other_abi         = coalesce(p_other_abi, other_abi),
    abi_total         = v_abi,
    key_competitor    = coalesce(p_key_competitor, key_competitor),
    other_competitor  = coalesce(p_other_competitor, other_competitor),
    competitor_total  = v_comp,
    beer_total        = v_abi + v_comp,
    updated_at        = now()
  where store_name = v_old_store and activity_date = v_old_date
  returning * into r;

  if not found then
    raise exception '记录不存在：% / %', v_old_store, v_old_date;
  end if;

  return r;
end;
$$;

-- 允许网页（anon 密钥）调用；参数类型顺序必须与上面完全一致
grant execute on function public.update_spr_record3(
  text, text, date, text, date, text, text, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer, integer,
  integer, integer, integer, integer
) to anon;

-- 完成提示
select
  '升级成功：看板「修改数据」现在可以改活动日期了' as 提示,
  (select count(*) from public.spr_records) as 当前记录数;
