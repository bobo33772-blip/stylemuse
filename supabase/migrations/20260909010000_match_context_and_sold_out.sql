-- 매칭 근거(original_type, match_reason)와 상품 품절 여부(sold_out)를 추가한다.
--
-- original_type / match_reason 을 musinsa_items 가 아니라 연결 테이블에 두는 이유:
-- 같은 상품이 여러 코디에 매칭될 수 있고, 그때 원본 아이템과 매칭 근거는 코디마다 달라진다.
-- 즉 이 두 값은 "상품"의 속성이 아니라 "코디-상품 관계"의 속성이다.

-- ---------------------------------------------------------------
-- 1. 코디-상품 매칭에 원본 아이템 유형과 매칭 근거를 남긴다.
--    기존 행은 두 컬럼이 NULL 로 남는다(프론트에서 NULL 이면 해당 영역을 그리지 않는다).
-- ---------------------------------------------------------------
alter table looks_items_match
  add column if not exists original_type text,
  add column if not exists match_reason  text;

comment on column looks_items_match.original_type is
  '원본 코디 속 아이템의 유형. 브랜드명은 넣지 않는다. 예: "스트라이프 카라 반팔티"';

comment on column looks_items_match.match_reason is
  '이 상품을 고른 근거 한 줄. 예: "스트라이프 간격과 카라 형태가 유사"';

-- ---------------------------------------------------------------
-- 2. 상품 품절 여부.
--    기본값이 있으므로 기존 행은 모두 false 로 채워진다.
--    NOT NULL 로 두어 프론트가 true/false 두 가지만 다루면 되게 한다.
-- ---------------------------------------------------------------
alter table musinsa_items
  add column if not exists sold_out boolean not null default false;

comment on column musinsa_items.sold_out is '품절 여부';
