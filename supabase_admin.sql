-- ============================================================
-- 黑金之夜 · 数据修正升级脚本（v5：防错 + 后台直接改数）
-- 使用方法：登录 Supabase → 左侧 SQL Editor → 全部复制粘贴 → 点 Run
-- 运行一次即可。跑完之前，网页新功能会提示「请先执行升级脚本」，属正常现象。
--
-- 本脚本做两件事：
--   1) submit_spr_record2：提交时可选「追加(累加)」或「覆盖(以本次为准)」
--      —— 解决 SPR 重复提交导致数字翻倍的问题
--   2) update_spr_record：按「门店+日期」直接修改某条记录（需管理密码）
--      —— 看板里点一条数据就能改，不用再走 Excel 替换
-- 原有的 submit_spr_record 保持不变，旧逻辑不受影响。
-- ============================================================

-- ============================================================
-- ★★★ 管理密码：看板改数据时要输入，强烈建议改掉再点 Run ★★★
-- ============================================================
-- 注意：密码写在下面两个函数体里的 v_pin_expected 那一行（共 2 处，要一起改）。

-- ------------------------------------------------------------
-- 1) 提交函数 v2：p_mode = 'add'（追加，累加） / 'replace'（覆盖，重置为本次数字）
-- ------------------------------------------------------------
create or replace function public.submit_spr_record2(
  p_mode              text,
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
  v_pin_expected constant text := '9527';  -- ★ 改密码处 1/2（暂未用于提交，预留）
begin
  if p_mode not in ('add', 'replace') then
    raise exception 'p_mode 必须是 add（追加）或 replace（覆盖）';
  end if;

  v_gift := coalesce(p_mechanism1,0) + coalesce(p_mechanism2,0) + coalesce(p_mechanism3,0) + coalesce(p_mechanism4,0);
  v_bg   := coalesce(p_blackgold_1l,0) + coalesce(p_blackgold_500,0) + coalesce(p_blackgold_600,0) + coalesce(p_blackgold_330,0) + coalesce(p_blackgold_250,0);
  v_abi  := coalesce(p_bud_classic_gold,0) + v_bg + coalesce(p_other_abi,0);
  v_comp := coalesce(p_key_competitor,0) + coalesce(p_other_competitor,0);

  -- 覆盖模式：先把旧记录删掉，再写入本次数字（相当于重填）
  if p_mode = 'replace' then
    delete from public.spr_records
     where store_name = p_store_name and activity_date = p_activity_date;
  end if;

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

-- ------------------------------------------------------------
-- 2) 看板改数：按「门店 + 日期」修改一条记录（合计自动重算）
--    需要 p_pin = 管理密码
-- ------------------------------------------------------------
create or replace function public.update_spr_record(
  p_store_name        text,
  p_activity_date     date,
  p_pin               text,
  p_m3                text,
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
  v_pin_expected constant text := '9527';  -- ★ 改密码处 2/2（看板改数据时要输入这个）
begin
  if p_pin is null or p_pin <> v_pin_expected then
    raise exception '管理密码错误，无法修改数据';
  end if;

  v_gift := coalesce(p_mechanism1,0) + coalesce(p_mechanism2,0) + coalesce(p_mechanism3,0) + coalesce(p_mechanism4,0);
  v_bg   := coalesce(p_blackgold_1l,0) + coalesce(p_blackgold_500,0) + coalesce(p_blackgold_600,0) + coalesce(p_blackgold_330,0) + coalesce(p_blackgold_250,0);
  v_abi  := coalesce(p_bud_classic_gold,0) + v_bg + coalesce(p_other_abi,0);
  v_comp := coalesce(p_key_competitor,0) + coalesce(p_other_competitor,0);

  update public.spr_records set
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
  where store_name = p_store_name and activity_date = p_activity_date
  returning * into r;

  if not found then
    raise exception '记录不存在：% / %', p_store_name, p_activity_date;
  end if;
  return r;
end;
$$;

-- ------------------------------------------------------------
-- 3) 允许网页（anon 密钥）调用这两个新函数
-- ------------------------------------------------------------
grant execute on function public.submit_spr_record2(
  text, text, text, date, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer
) to anon;

grant execute on function public.update_spr_record(
  text, date, text, text, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer
) to anon;

-- 4) 完成提示
select
  '升级成功！记得把两个函数里的管理密码 9527 改成自己的（不改也能用）。' as 提示,
  '网页端无需其他配置，刷新即可使用新功能。' as 下一步;
