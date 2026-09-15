# StyleMuse

핀터레스트 해외 코디 사진을 국내(무신사) 구매 가능한 아이템으로 매칭해주는 웹 서비스 프로토타입.

---

## ⚠️ 배포 전 필수 조치

> **2026.09.15 — 해소 완료.** 서비스 성격을 "실제 서비스"로 바꾸면서
> 기존 보류 근거("학습 목적 개인 프로젝트, 외부 배포 계획 없음")가 무효가 되었고,
> 같은 날 조치를 끝냈다.

### 완료

- [x] `pinterest_looks`, `looks_items_match`, `musinsa_items`에 RLS 적용
- [x] anon 키는 SELECT만 허용 (INSERT·UPDATE·DELETE 전면 차단)
- [x] `/admin`에 Supabase Auth 기반 인증 추가
- [x] 쓰기 작업은 운영자로 제한
- [x] `analyze-look` Edge Function 호출도 운영자로 제한
- [x] 유저 테이블 RLS (`user_profiles`, `saved_looks`, `user_agreements`)

### 남은 항목

- [ ] **데모 계정 삭제** — `stylemuse.demo@gmail.com` (발표 시연용). 시연이 끝나면 지운다
- [ ] **HTTPS 확인** — 배포 후 실제 도메인에서 확인
- [ ] 내부 관리계획 문서 수립, 접근권한 정기 점검 절차

### 현재 RLS 상태

| 테이블 | 개인정보 | RLS | 읽기 | 쓰기 |
|---|---|---|---|---|
| `user_profiles` | ✅ | ✅ | 본인만 | 본인만 |
| `saved_looks` | ✅ | ✅ | 본인만 | 본인만 |
| `user_agreements` | ✅ | ✅ | 본인만 | 본인만 |
| `pinterest_looks` | ❌ | ✅ | 공개 코디 + 운영자 | 운영자만 |
| `looks_items_match` | ❌ | ✅ | 공개 코디의 매칭만 | 운영자만 |
| `musinsa_items` | ❌ | ✅ | 전체 | 운영자만 |
| `admin_users` | ❌ | ✅ | 정책 없음 = API 접근 불가 | SQL로만 |
| `search_cache` · `look_save_stats` | ❌ | ✅ | 정책 없음 = 서버 전용 | 서버 전용 |

**RLS 가 꺼진 테이블은 없다.**

### 관리자 권한

운영자는 `admin_users` 테이블로 관리한다. 이 테이블은 RLS 를 켜고 **정책을 하나도 두지 않아** API 로는 조회·추가·삭제가 모두 막혀 있다. 관리자 지정은 SQL 로만 가능하다.

`user_profiles.is_admin` 컬럼을 쓰지 않은 이유: 그 테이블에는 "본인 행은 본인이 수정한다" 정책이 있어 **이용자가 스스로를 운영자로 올릴 수 있다.** 컬럼 단위 권한 회수로 막을 수는 있으나, 보호막이 정책과 다른 곳에 숨어 나중에 `grant` 한 줄로 조용히 열릴 수 있다.

```bash
# 운영자 지정 (SQL 로만 가능)
.\.tools\supabase.exe db query --linked   "insert into admin_users (user_id, note) select id, '운영자' from auth.users where email = '<주소>'"
```

---

## ⚖️ 법률 문서

`/terms`(이용약관), `/privacy`(개인정보처리방침) — 각 v1.0, 2026.09.15 시행.

> **이 문서들은 법률 전문가의 검토를 받지 않은 초안입니다.**
> 실제 서비스 운영 전 전문가 검토를 권장합니다.
> 본문에서 확인이 필요한 부분은 `[확인 필요]`로 표시해 두었습니다.

작성 시 지킨 것:

- 수집 항목은 **실제 테이블 컬럼과 코드를 확인해** 작성했다. 추측하지 않았다
- 미구현 기능(전신 사진 업로드, Vertex AI 이전)은 **"도입 예정"으로 명시**하고 현재 수집·전송하지 않음을 밝혔다
- 안전성 확보조치는 **현재 상태를 있는 그대로** 적었다. 적용되지 않은 사항도 함께 기재했다

---

## 실행

```bash
python app.py          # http://127.0.0.1:5000
```

| 경로 | 화면 |
|---|---|
| `/` | 코디 피드 + 상세 |
| `/admin` | 코디 업로드·AI 분석 + 매칭 근거 큐레이션 |
| `/notices` | 공지사항 (정적) |

Flask는 HTML만 서빙한다. API 엔드포인트가 없고 DB에도 접근하지 않는다.
데이터 조회·쓰기는 브라우저가 Supabase로 직접 한다.

---

## 구조

```
app.py                              Flask 라우트 3개 (HTML 서빙만)
static/config.js                    SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY (공개값만)
templates/
  index.html                        피드 + 상세 (라우팅 없이 show/hide)
  admin_upload.html                 업로드·분석 + 매칭 근거 큐레이션
  notice.html
supabase/
  functions/analyze-look/index.ts   Edge Function (Deno)
  migrations/*.sql
.tools/                             supabase.exe, deno.exe (gitignore 대상)
```

### 데이터 모델

```
pinterest_looks (id, image_url, style_tag)
      │
      │  looks_items_match (look_id, item_id, original_type, match_reason)
      │      original_type : 원본 코디 속 아이템 유형 (브랜드명 제외)
      │      match_reason  : 매칭 근거 한 줄
      │      ↑ 둘 다 코디-상품 "관계"의 속성이라 musinsa_items 가 아니라 여기에 둔다.
      ↓        같은 상품이라도 붙는 코디가 다르면 근거가 달라진다.
musinsa_items (id, product_name, price, purchase_url, image_url, product_key, sold_out)
      product_key : 'musinsa:5909913' — purchase_url 의 추적 파라미터(srsltid)를 제거한 식별자

search_cache (query PK, item_id) : 검색어 → 상품. SerpApi 재호출 방지
```

### AI 매칭 파이프라인 (`analyze-look`)

```
사진 → GPT-4o Vision → "{색상} {핏} {품목}" 검색어 (통제 어휘, temperature 0)
     → search_cache 조회 (적중 시 SerpApi 건너뜀)
     → SerpApi google_shopping → immersive product API → 무신사 직링크
     → musinsa_items upsert + looks_items_match 연결
```

브라우저는 OpenAI·SerpApi를 직접 호출하지 않는다. 키는 Supabase 시크릿에만 있다.

**`match_reason`·`original_type`은 AI가 생성하지 않는다.** 수동 큐레이션이 MVP의 전제이며,
사람이 쓴 근거가 이후 자동화의 정답 데이터가 된다. 입력은 `/admin`에서 한다.

---

## 개발 도구

```bash
.\.tools\supabase.exe db query --linked "select ..."     # 원격 DB 조회
.\.tools\supabase.exe db query --linked -f 마이그레이션.sql
.\.tools\supabase.exe functions deploy analyze-look
.\.tools\supabase.exe secrets set --env-file <키만 담은 파일>
```

시크릿(`OPENAI_API_KEY`, `SERPAPI_KEY`)은 `.env`가 아니라 Supabase에 등록된 값이 실제로 쓰인다.
`.env`는 CLI로 옮기기 위한 출발점일 뿐이며, 앱 코드는 `.env`를 읽지 않는다.

---

## 알려진 제약

- **SerpApi 무료 플랜 250회/월.** 신규 코디 1건 분석에 5~9회 소모. 캐시 적중 시 0회
- **상세 화면에 URL이 없다.** 새로고침·뒤로가기·링크 공유 불가 (라우팅 미도입)
- **무신사 직접 크롤링 불가.** `robots.txt`가 `User-agent: * → Disallow: /`.
  공식 상품 API도 입점 브랜드용(주문 연동)뿐이라 제3자 상품 수집 경로가 없다.
  현재의 구글 경유는 무신사가 `Googlebot`에 허용한 정당한 경로다
- **텍스트 검색의 정확도 한계.** 색·품목을 검색어에 싣고 결과를 채점해도,
  시각 정보를 텍스트로 옮기는 과정에서 손실이 생긴다.
  근본 해결은 이미지 임베딩 검색이며 상품 카탈로그 확보가 선결 과제
