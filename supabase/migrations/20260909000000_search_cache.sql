-- 1단계: 검색 결과 재사용
--  - musinsa_items 에 상품 식별키(product_key)를 두어 같은 상품이 중복 저장되지 않게 한다.
--    purchase_url 에는 요청마다 바뀌는 추적 파라미터(srsltid)가 붙어 URL 자체로는 식별이 안 된다.
--  - search_cache 로 "검색어 -> 상품" 을 기억해 같은 검색어의 SerpApi 재호출을 없앤다.

-- ---------------------------------------------------------------
-- 1. 상품 식별키
-- ---------------------------------------------------------------
alter table musinsa_items add column if not exists product_key text;

update musinsa_items
set product_key = coalesce(
      'musinsa:' || substring(purchase_url from '(?:goods|products)/([0-9]+)'),
      split_part(purchase_url, '?', 1)
    )
where product_key is null
  and purchase_url is not null;

-- ---------------------------------------------------------------
-- 2. 기존 중복 상품 병합 (유니크 인덱스를 걸기 전에 정리)
--    같은 product_key 중 가장 작은 id 로 매칭을 몰아주고 나머지 행을 지운다.
-- ---------------------------------------------------------------
update looks_items_match m
set item_id = k.keep_id
from (
  select id, min(id) over (partition by product_key) as keep_id
  from musinsa_items
  where product_key is not null
) k
where m.item_id = k.id
  and k.id <> k.keep_id;

-- 병합 과정에서 (look_id, item_id) 가 겹치면 한 행만 남긴다.
delete from looks_items_match a
using looks_items_match b
where a.look_id = b.look_id
  and a.item_id = b.item_id
  and a.id > b.id;

delete from musinsa_items a
using (
  select id, min(id) over (partition by product_key) as keep_id
  from musinsa_items
  where product_key is not null
) k
where a.id = k.id
  and k.id <> k.keep_id;

-- 부분 인덱스(where ...)는 upsert 의 ON CONFLICT 와 맞물리지 않으므로 전체 인덱스로 만든다.
-- NULL 은 유니크 제약에서 서로 충돌하지 않으므로 그대로 두어도 안전하다.
create unique index if not exists musinsa_items_product_key_uidx
  on musinsa_items (product_key);

-- 같은 코디에 같은 상품이 두 번 붙지 않도록 한다.
create unique index if not exists looks_items_match_look_item_uidx
  on looks_items_match (look_id, item_id);

-- ---------------------------------------------------------------
-- 3. 검색어 캐시
--    Edge Function(service role)만 사용한다. RLS 를 켜되 정책을 두지 않아
--    anon/publishable 키로는 접근할 수 없게 한다.
-- ---------------------------------------------------------------
create table if not exists search_cache (
  query      text primary key,
  item_id    bigint not null references musinsa_items (id) on delete cascade,
  hit_count  integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists search_cache_item_id_idx on search_cache (item_id);

alter table search_cache enable row level security;
