-- 코디 공개 상태.
--
-- 자동 삭제를 하지 않는다는 원칙(DECISIONS.md)에 따라, 노출하지 않을 코디도 지우지 않고
-- 상태만 바꾼다. 유저 화면은 is_public = true 만 조회하고, 운영 화면은 전부 조회한다.

alter table pinterest_looks
  add column if not exists is_public boolean not null default true;

comment on column pinterest_looks.is_public is
  '공개 여부. false 면 유저 화면에서 조회하지 않는다. 데이터는 보존한다';

-- 고프코어 5건 비공개 전환.
-- 사유: AI 자동 매칭 결과가 원본과 일치하지 않아(13건 중 정확 0건) 유저에게 노출할 수준이 아니다.
--       다만 AI 매칭의 현재 한계를 보여주는 유일한 실측 근거이므로 데이터는 보존한다.
update pinterest_looks
set is_public = false
where style_tag = '고프코어';
