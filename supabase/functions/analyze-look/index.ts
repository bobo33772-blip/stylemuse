import { withSupabase } from "@supabase/server";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const SERPAPI_KEY = Deno.env.get("SERPAPI_KEY");

// 검색어에 색상·소재·핏을 반드시 싣는다. 이 정보가 빠지면 카테고리만 맞고
// 색이 전혀 다른 상품이 매칭된다(예: 밝은 회색 아노락 -> "네이비 블랙" 제품).
// 검색어에 색상·소재·핏을 반드시 싣되, 어휘는 아래 목록으로 통제한다.
// 자유 문장으로 두면 같은 옷을 매번 다르게 불러("블랙 트레일 러닝화" vs "검은색 트레일 러닝화")
// 검색어 캐시가 전혀 적중하지 않는다.
const COLORS = [
  "블랙", "화이트", "아이보리", "그레이", "차콜", "네이비", "블루", "카키",
  "올리브", "베이지", "브라운", "그린", "레드", "퍼플", "핑크", "옐로우",
];

const CATEGORIES = [
  "후드 아노락", "바람막이", "코치 자켓", "블루종", "패딩", "코트", "가디건",
  "셔츠", "티셔츠", "맨투맨", "후드티", "니트",
  "카고 팬츠", "치노 팬츠", "데님 팬츠", "트레이닝 팬츠", "슬랙스", "숏팬츠", "스커트",
  "스니커즈", "트레일 러닝화", "러닝화", "로퍼", "부츠", "샌들",
  "백팩", "크로스백", "토트백", "캡모자", "비니",
];

const SYSTEM_PROMPT =
  '너는 전문 패션 코디네이터다. 사진 속 코디의 핵심 아이템을 최대 3가지 뽑아 JSON으로만 응답해라. ' +
  '형식: { "items": [ { "name": "한국어 상품명", "color": "색상", "category": "품목", ' +
  '"fit": "실루엣·핏(없으면 빈 문자열)", "colors": ["색상 표기 후보"], "categories": ["품목 표기 후보"] } ] } ' +
  `color 는 반드시 다음 중 하나를 그대로 골라라: ${COLORS.join(", ")}. ` +
  `category 도 반드시 다음 중 하나를 그대로 골라라: ${CATEGORIES.join(", ")}. ` +
  '목록에 없으면 가장 가까운 것을 골라라. 새 표현을 지어내지 마라. ' +
  'fit 은 "와이드", "오버사이즈", "슬림", "크롭" 같은 한 단어이며 해당 없으면 빈 문자열이다. ' +
  'colors 는 그 색을 쇼핑몰이 표기할 법한 말을 2~4개 담은 배열이다. ' +
  '예) 밝은 회백색이면 ["아이보리","오프화이트","화이트","라이트그레이"]. ' +
  'categories 는 그 품목을 쇼핑몰이 부를 법한 말을 2~4개 담은 배열이다. ' +
  '예) 후드 달린 바람막이면 ["아노락","윈드브레이커","바람막이","후드 자켓"]. ' +
  '사람·배경·소품은 제외하고 실제로 구매 가능한 의류·신발·가방만 포함해라.';

/** GPT-4o Vision 으로 코디 사진에서 아이템 후보를 뽑는다. */
async function extractItems(imageUrl: string) {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            { type: "text", text: "이 코디의 핵심 아이템을 분석해줘." },
            { type: "image_url", image_url: { url: imageUrl } },
          ],
        },
      ],
      // 같은 사진이면 같은 검색어가 나와야 캐시가 적중한다.
      temperature: 0,
      response_format: { type: "json_object" },
    }),
  });

  if (!res.ok) {
    throw new Error(`OpenAI 호출 실패 (${res.status}): ${await res.text()}`);
  }

  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content;
  if (!content) throw new Error("OpenAI 응답에 분석 결과가 없습니다.");

  const parsed = JSON.parse(content);
  const raw = Array.isArray(parsed?.items) ? parsed.items : [];

  // 통제 어휘를 정해진 순서로 조립해 검색어를 만든다. 같은 옷이면 항상 같은 문자열이 된다.
  return raw
    .filter((i: { color?: string; category?: string }) => i?.color && i?.category)
    .map((i: {
      name?: string;
      color: string;
      category: string;
      fit?: string;
      colors?: string[];
      categories?: string[];
    }) => ({
      name: i.name,
      query: [i.color, i.fit, i.category].filter(Boolean).join(" ").trim(),
      fallback: i.category,
      colors: Array.isArray(i.colors) ? i.colors : [i.color],
      categories: Array.isArray(i.categories) ? i.categories : [i.category],
    }));
}

async function serpFetch(url: string) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`SerpApi 호출 실패 (${res.status})`);
  return await res.json();
}

const toPrice = (v: unknown) => (typeof v === "number" ? Math.round(v) : null);

/**
 * SerpApi 로 실제 판매 상품을 찾는다.
 * 1) google_shopping 으로 상품 후보(가격·썸네일)를 얻고
 * 2) immersive product API 로 판매처 직링크를 얻는다 (무신사 우선).
 *    google_shopping 의 product_link 는 구글 쇼핑 페이지라 구매 링크로 쓰기 부적합하다.
 * 위 경로가 안 되면 쇼핑 링크 → 일반 검색 순으로 폴백한다.
 */
async function findProduct(
  query: string,
  fallbackQuery?: string,
  colors: string[] = [],
  categories: string[] = [],
) {
  const search = (engine: string, q: string) =>
    serpFetch(
      `https://serpapi.com/search.json?engine=${engine}` +
        `&q=${encodeURIComponent(`무신사 ${q}`)}&gl=kr&hl=ko&api_key=${SERPAPI_KEY}`,
    );

  // 상세 검색어가 너무 좁아 0건이면 짧은 검색어로 한 번 더 시도한다.
  let shopping = await search("google_shopping", query);
  if (!(shopping?.shopping_results ?? []).length && fallbackQuery && fallbackQuery !== query) {
    console.log(`상세 검색어 0건, 폴백으로 재시도: "${query}" -> "${fallbackQuery}"`);
    shopping = await search("google_shopping", fallbackQuery);
  }

  const results = shopping?.shopping_results ?? [];

  // 구글은 쿼리의 색·품목을 강하게 반영하지 않으므로 결과를 직접 채점해 고른다.
  // 품목(2점)을 색(1점)보다 무겁게 둔다: 색 맞은 "체크 셔츠"보다
  // 색 틀린 "체크 아노락"이 낫다. 품목이 어긋나면 아예 다른 옷이 된다.
  const hits = (title: string, words: string[]) =>
    words.length > 0 && words.some((w) => title.includes(w));

  const score = (r: { title?: string }) => {
    const title = r.title ?? "";
    return (hits(title, categories) ? 2 : 0) + (hits(title, colors) ? 1 : 0);
  };

  // 무신사 판매 결과가 하나라도 있으면 그 안에서만 고른다.
  // 이 앱은 무신사 상품을 전제로 하므로(musinsa_items), 점수가 높아도
  // 다른 쇼핑몰 상품이 섞이면 안 된다.
  const musinsaResults = results.filter((r: { source?: string }) =>
    (r.source ?? "").includes("무신사")
  );
  const pool = musinsaResults.length > 0 ? musinsaResults : results;

  // 동점이면 구글이 매긴 원래 순위를 존중한다(안정 정렬).
  const candidate = pool.length > 0
    ? pool.reduce((best, r) => (score(r) > score(best) ? r : best), pool[0])
    : undefined;

  if (candidate) {
    // 2) 판매처 직링크 시도 — 실패해도 쇼핑 링크로 진행한다.
    if (candidate.serpapi_immersive_product_api) {
      try {
        const detail = await serpFetch(
          `${candidate.serpapi_immersive_product_api}&api_key=${SERPAPI_KEY}`,
        );
        const stores = detail?.product_results?.stores ?? [];
        const store = stores.find((s: { name?: string }) => (s.name ?? "").includes("무신사")) ??
          stores[0];

        if (store?.link) {
          return {
            product_name: store.title ?? candidate.title,
            image_url: candidate.thumbnail ?? null,
            purchase_url: store.link,
            price: toPrice(store.extracted_price) ?? toPrice(candidate.extracted_price),
          };
        }
      } catch (err) {
        console.error("판매처 직링크 조회 실패, 쇼핑 링크로 대체", err);
      }
    }

    return {
      product_name: candidate.title,
      image_url: candidate.thumbnail ?? null,
      purchase_url: candidate.product_link ?? null,
      price: toPrice(candidate.extracted_price),
    };
  }

  const organic = await search("google", fallbackQuery ?? query);
  const fallback = organic?.organic_results?.[0];
  if (!fallback) return null;

  return {
    product_name: fallback.title,
    image_url: fallback.thumbnail ?? null,
    purchase_url: fallback.link ?? null,
    price: null,
  };
}

/** 같은 상품을 같은 값으로 식별한다. purchase_url 에는 매번 바뀌는 추적 파라미터가 붙는다. */
function productKey(url: string) {
  const m = url.match(/(?:goods|products)\/(\d+)/);
  return m ? `musinsa:${m[1]}` : url.split("?")[0];
}

/** 캐시 적중률을 높이기 위한 검색어 정규화. */
const normalizeQuery = (q: string) => q.trim().toLowerCase().replace(/\s+/g, " ");

/**
 * 검색어 하나를 상품 행으로 바꾼다.
 * 같은 검색어가 이미 해결된 적 있으면 SerpApi 를 부르지 않고 DB 에서 재사용한다.
 */
async function resolveItem(
  // deno-lint-ignore no-explicit-any
  admin: any,
  candidate: {
    name?: string;
    query: string;
    fallback?: string;
    colors?: string[];
    categories?: string[];
  },
) {
  const key = normalizeQuery(candidate.query);
  const notes: string[] = [];

  // 1) 캐시 조회 — 조인 임베드에 의존하지 않도록 두 단계로 읽는다.
  const { data: hit, error: hitError } = await admin
    .from("search_cache")
    .select("item_id, hit_count")
    .eq("query", key)
    .maybeSingle();

  if (hitError) notes.push(`캐시 조회 오류: ${hitError.message}`);

  if (hit?.item_id) {
    const { data: cachedItem, error: itemReadError } = await admin
      .from("musinsa_items")
      .select("*")
      .eq("id", hit.item_id)
      .maybeSingle();

    if (itemReadError) notes.push(`캐시 상품 조회 오류: ${itemReadError.message}`);

    if (cachedItem) {
      await admin
        .from("search_cache")
        .update({ hit_count: (hit.hit_count ?? 0) + 1, updated_at: new Date().toISOString() })
        .eq("query", key);
      return { item: cachedItem, fromCache: true, key, notes };
    }
  }

  // 2) 캐시에 없으면 검색
  const product = await findProduct(
    candidate.query,
    candidate.fallback,
    Array.isArray(candidate.colors) ? candidate.colors : [],
    Array.isArray(candidate.categories) ? candidate.categories : [],
  );
  if (!product?.purchase_url) {
    notes.push("검색 결과 없음");
    return { item: null, fromCache: false, key, notes };
  }

  // 3) 상품 저장 — 이미 있는 상품이면 그 행을 재사용한다.
  const { data: item, error: itemError } = await admin
    .from("musinsa_items")
    .upsert({
      ...product,
      product_name: product.product_name ?? candidate.name,
      product_key: productKey(product.purchase_url),
    }, { onConflict: "product_key" })
    .select()
    .single();

  if (itemError || !item) {
    notes.push(`상품 저장 실패: ${itemError?.message ?? "알 수 없음"}`);
    console.error("musinsa_items upsert 실패", itemError);
    return { item: null, fromCache: false, key, notes };
  }

  // 4) 검색어 -> 상품 기억
  const { error: cacheError } = await admin
    .from("search_cache")
    .upsert({ query: key, item_id: item.id, updated_at: new Date().toISOString() }, {
      onConflict: "query",
    });
  if (cacheError) {
    notes.push(`캐시 저장 실패: ${cacheError.message}`);
    console.error("search_cache upsert 실패", cacheError);
  }

  return { item, fromCache: false, key, notes };
}

/**
 * 호출자가 운영자인지 확인한다.
 * Authorization 헤더의 사용자 토큰으로 admin_users 를 조회한다.
 * 그 테이블은 RLS 로 잠겨 있으므로 service role 로 확인한다.
 */
// deno-lint-ignore no-explicit-any
async function isAdminRequest(ctx: any, req: Request): Promise<boolean> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return false;

  const { data, error } = await ctx.supabaseAdmin.auth.getUser(token);
  if (error || !data?.user) return false;

  const { data: row } = await ctx.supabaseAdmin
    .from("admin_users")
    .select("user_id")
    .eq("user_id", data.user.id)
    .maybeSingle();

  return !!row;
}

export default {
  // publishable 키만으로도 여기까지는 들어온다. 그 뒤 운영자인지를 직접 확인한다.
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    if (!OPENAI_API_KEY || !SERPAPI_KEY) {
      return Response.json(
        { error: "OPENAI_API_KEY / SERPAPI_KEY 시크릿이 설정되지 않았습니다." },
        { status: 500 },
      );
    }

    // 이 함수는 OpenAI·SerpApi 를 호출하므로 호출 자체가 비용이다.
    // 키가 서버에 있어도 호출 경로가 열려 있으면 결과는 키가 새어나간 것과 같다.
    // secret 키로 온 서버 호출은 통과시키고, 그 외에는 운영자 여부를 확인한다.
    if (ctx.authMode !== "secret") {
      const allowed = await isAdminRequest(ctx, req);
      if (!allowed) {
        return Response.json(
          { error: "운영자만 사용할 수 있습니다." },
          { status: 403 },
        );
      }
    }

    let body: {
      imageUrl?: string;
      lookId?: string | number;
      styleTag?: string;
      force?: boolean;
    };
    try {
      body = await req.json();
    } catch {
      return Response.json({ error: "JSON 본문이 필요합니다." }, { status: 400 });
    }

    const { imageUrl, styleTag, force = false } = body;
    let lookId = body.lookId;

    if (!imageUrl) {
      return Response.json({ error: "imageUrl 은 필수입니다." }, { status: 400 });
    }

    try {
      // 0. 관리자 업로드처럼 lookId 없이 들어오면 코디 행을 먼저 만든다.
      if (lookId === undefined || lookId === null) {
        const { data: newLook, error: lookError } = await ctx.supabaseAdmin
          .from("pinterest_looks")
          .insert({ image_url: imageUrl, style_tag: styleTag ?? null })
          .select()
          .single();

        if (lookError || !newLook) {
          console.error("pinterest_looks insert 실패", lookError);
          return Response.json({ error: "코디 저장에 실패했습니다." }, { status: 500 });
        }
        lookId = newLook.id;
      }

      // 1. 이미 분석된 코디면 재분석하지 않고 저장된 결과를 돌려준다.
      const { data: existing } = await ctx.supabaseAdmin
        .from("looks_items_match")
        .select("musinsa_items (*)")
        .eq("look_id", lookId);

      if (!force && existing && existing.length > 0) {
        return Response.json({
          success: true,
          lookId,
          cached: true,
          items: existing.map((m: { musinsa_items: unknown }) => m.musinsa_items).filter(Boolean),
        });
      }

      // 재분석이면 이 코디의 매칭만 지운다.
      // 상품 행은 지우지 않는다. 어느 코디에도 안 붙은 상품은 쓰레기가 아니라
      // search_cache 가 재사용할 카탈로그이고, 지우면 캐시가 cascade 로 함께 날아간다.
      if (force) {
        await ctx.supabaseAdmin.from("looks_items_match").delete().eq("look_id", lookId);
      }

      // 2. AI 분석
      const candidates = await extractItems(imageUrl);
      if (candidates.length === 0) {
        return Response.json({ success: true, lookId, cached: false, items: [] });
      }

      // 3. 검색어 -> 상품 해결(캐시 우선) → 코디와 매칭
      const saved = [];
      const seen = new Set<number>();
      let cacheHits = 0;

      const debug: unknown[] = [];

      for (const candidate of candidates) {
        const resolved = await resolveItem(ctx.supabaseAdmin, candidate);
        debug.push({
          query: resolved.key,
          fromCache: resolved.fromCache,
          itemId: resolved.item?.id ?? null,
          notes: resolved.notes,
        });
        if (!resolved.item) continue;
        if (resolved.fromCache) cacheHits++;

        // 서로 다른 검색어가 같은 상품으로 수렴하면 한 번만 붙인다.
        if (seen.has(resolved.item.id)) continue;
        seen.add(resolved.item.id);

        const { error: matchError } = await ctx.supabaseAdmin
          .from("looks_items_match")
          .upsert({ look_id: lookId, item_id: resolved.item.id }, {
            onConflict: "look_id,item_id",
            ignoreDuplicates: true,
          });

        if (matchError) {
          console.error("looks_items_match upsert 실패", matchError);
          continue;
        }

        saved.push(resolved.item);
      }

      console.log(`검색어 ${candidates.length}건 중 캐시 적중 ${cacheHits}건`);
      return Response.json({
        success: true,
        lookId,
        cached: false,
        cacheHits,
        items: saved,
        debug,
      });
    } catch (err) {
      console.error("analyze-look 실패", err);
      return Response.json(
        { error: err instanceof Error ? err.message : "알 수 없는 오류" },
        { status: 500 },
      );
    }
  }),
};
