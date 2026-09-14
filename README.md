# StyleMuse

핀터레스트 해외 코디 사진을 국내(무신사) 구매 가능한 아이템으로 매칭해주는 웹 서비스 프로토타입.

---

## ⚠️ 배포 전 필수 조치

**아래 조치를 끝내기 전에는 외부 URL로 배포하지 않는다.**

- [x] **유저 테이블 RLS 적용 완료** — `user_profiles`, `saved_looks` (2026.09.14)
- [ ] **기존 3개 테이블 RLS 미적용** — `pinterest_looks`, `looks_items_match`, `musinsa_items`
- [ ] anon 키는 SELECT만 허용
- [ ] `/admin`에 Supabase Auth 기반 인증 추가
- [ ] 쓰기 작업은 인증된 사용자 또는 Edge Function으로 제한
- [ ] 데모 계정 삭제 (`auth.users`에 시연용 계정 1건이 남아 있다)

### 현재 상태

| 테이블 | RLS | 정책 | 비고 |
|---|---|---|---|
| `user_profiles` | ✅ on | 4 | `auth.uid() = user_id` — SELECT·INSERT·UPDATE·DELETE |
| `saved_looks` | ✅ on | 4 | `auth.uid() = user_id` — SELECT·INSERT·UPDATE·DELETE |
| `search_cache` | ✅ on | 0 | 정책 없음 = Edge Function 전용 |
| `pinterest_looks` | ❌ off | 0 | **조치 필요** |
| `looks_items_match` | ❌ off | 0 | **조치 필요** |
| `musinsa_items` | ❌ off | 0 | **조치 필요** |

**유저 데이터는 보호된다.** 만들 때부터 RLS를 켰고, 사용자 둘을 만들어 서로의 행이 보이지 않는 것과 남의 `user_id`로 쓰기가 거부되는 것을 실제로 확인했다.

**코디·상품·매칭 세 테이블은 여전히 publishable 키로 누구나 UPDATE·DELETE가 가능하다.** 그 키는 `static/config.js`에 담겨 모든 방문자 브라우저로 전송되고, `/admin`에도 인증이 없다.

2026.09.14에 Supabase Auth를 도입했으므로 `/admin` 인증에 쓸 기반은 생겼다. 남은 작업은 세 테이블에 읽기 전용 정책을 걸고 운영 화면의 쓰기 경로를 인증 뒤로 옮기는 것이다.

### 왜 미뤘는가 (2026-09-09 결정)

- 프로토타입 단계에서는 로컬 또는 화면 공유로만 시연한다
- 외부 URL 배포 계획이 없다
- 지금은 매칭 근거 데이터를 채우는 것이 우선순위다

의도적으로 미룬 것이며, 배포 계획이 생기는 시점에 **가장 먼저** 해소해야 한다.

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
