-- ============================================================
-- 黑金之夜 · 新增「黑金600瓶」销量字段（v3→v4 增量升级脚本）
-- 使用方法：登录 Supabase → 左侧 SQL Editor → 清空 → 全选复制粘贴 → 点 Run
-- 只跑这一次；已存在的旧数据 blackgold_600 自动补 0，合计列会被重新正确计算
-- ============================================================

-- 1) 表加字段（已存在则跳过）
alter table public.spr_records
  add column if not exists blackgold_600 integer not null default 0;

-- 2) 重建提交函数：新增 p_blackgold_600 参数，黑金合计自动=5个SKU之和
create or replace function public.submit_spr_record(
  p_store_name        text,
  p_m3                text,
  p_activity_date     date,
  p_spr_name          text,
  p_mechanism1        integer,
  p_mechanism2        integer,
  p_mechanism3        integer,
  p_mechanism4        integer,
  p_bud_classic_gold  integer,
  p_blackgold_1l      integer,
  p_blackgold_500     integer,
  p_blackgold_600     integer,
  p_blackgold_330     integer,
  p_blackgold_250     integer,
  p_other_abi         integer,
  p_key_competitor    integer,
  p_other_competitor  integer
) returns public.spr_records
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.spr_records;
  v_gift integer;
  v_bg   integer;
  v_abi  integer;
  v_comp integer;
begin
  v_gift := coalesce(p_mechanism1,0) + coalesce(p_mechanism2,0) + coalesce(p_mechanism3,0) + coalesce(p_mechanism4,0);
  v_bg   := coalesce(p_blackgold_1l,0) + coalesce(p_blackgold_500,0) + coalesce(p_blackgold_600,0) + coalesce(p_blackgold_330,0) + coalesce(p_blackgold_250,0);
  v_abi  := coalesce(p_bud_classic_gold,0) + v_bg + coalesce(p_other_abi,0);
  v_comp := coalesce(p_key_competitor,0) + coalesce(p_other_competitor,0);

  insert into public.spr_records as t (
    store_name, m3, activity_date, spr_name,
    mechanism1, mechanism2, mechanism3, mechanism4, gift_255_cans,
    bud_classic_gold, blackgold_1l, blackgold_500, blackgold_600, blackgold_330, blackgold_250, blackgold_total,
    other_abi, abi_total,
    key_competitor, other_competitor, competitor_total, beer_total
  ) values (
    p_store_name, p_m3, p_activity_date, p_spr_name,
    p_mechanism1, p_mechanism2, p_mechanism3, p_mechanism4, v_gift,
    p_bud_classic_gold, p_blackgold_1l, p_blackgold_500, p_blackgold_600, p_blackgold_330, p_blackgold_250, v_bg,
    p_other_abi, v_abi,
    p_key_competitor, p_other_competitor, v_comp, v_abi + v_comp
  )
  on conflict (store_name, activity_date) do update
    set spr_name          = excluded.spr_name,
        m3                = excluded.m3,
        mechanism1        = t.mechanism1        + excluded.mechanism1,
        mechanism2        = t.mechanism2        + excluded.mechanism2,
        mechanism3        = t.mechanism3        + excluded.mechanism3,
        mechanism4        = t.mechanism4        + excluded.mechanism4,
        gift_255_cans     = t.gift_255_cans     + excluded.gift_255_cans,
        bud_classic_gold  = t.bud_classic_gold  + excluded.bud_classic_gold,
        blackgold_1l      = t.blackgold_1l      + excluded.blackgold_1l,
        blackgold_500     = t.blackgold_500     + excluded.blackgold_500,
        blackgold_600     = t.blackgold_600     + excluded.blackgold_600,
        blackgold_330     = t.blackgold_330     + excluded.blackgold_330,
        blackgold_250     = t.blackgold_250     + excluded.blackgold_250,
        blackgold_total   = t.blackgold_total   + excluded.blackgold_total,
        other_abi         = t.other_abi         + excluded.other_abi,
        abi_total         = t.abi_total         + excluded.abi_total,
        key_competitor    = t.key_competitor    + excluded.key_competitor,
        other_competitor  = t.other_competitor  + excluded.other_competitor,
        competitor_total  = t.competitor_total  + excluded.competitor_total,
        beer_total        = t.beer_total        + excluded.beer_total,
        updated_at        = now()
  returning * into r;
  return r;
end;
$$;

-- 3) 重新授权网页（anon）调用新签名的函数
grant execute on function public.submit_spr_record(
  text, text, date, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer
) to anon;

-- 4) 完成提示
select '黑金600瓶字段添加成功！可以关闭本页面了。' as 提示;
