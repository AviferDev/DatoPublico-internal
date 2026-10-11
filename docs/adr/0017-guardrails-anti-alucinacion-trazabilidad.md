# ADR 0017: Guardrails anti-alucinación offline y deterministas (fuente estructural + grounding léxico) antes de publicar

## Estado

Aceptado (2026-10-11). Decisión del dueño para FT00022
(`guardrails-anti-alucinacion`).

## Contexto

La generación del resumen ciudadano existe como **librería sin wiring** (FT00020,
ADR 0015) y su **contrato** se valida en `:shared` (FT00019, ADR 0014): estructura,
presencia de la fuente, secciones no vacías y plazo en empleo/beca. Pero el contrato
**no comprueba veracidad**: no hay ninguna noción de

- que la fuente oficial sea un enlace **oficial del BOE** y **coincida** con la
  publicación de origen (trazabilidad),
- que las afirmaciones del resumen («¿Qué cambia?», «¿A quién afecta?» y «Cifras
  clave») estén **sustentadas por el contexto recuperado**,
- una **decisión** explícita de publicar, enviar a revisión o descartar, ni una
  **señal de confianza** para la cola de revisión (FT00023).

La regla del producto es dura: **nunca** publicar una alucinación ni un resumen sin
trazabilidad. Hacía falta una pieza **offline, determinista y sustituible por
dobles** que se ejecutara **después** de generar y **antes** de publicar, sin
anticipar la cola de revisión ni la persistencia.

## Decisión

Añadir en `:backend`, como **librería sin wiring**, el paquete
`rag/guardrails/` con:

- **Validez estructural de la fuente** (`OfficialSourceValidator`): `isOfficial`
  exige `https://`, host en la lista blanca oficial (`www.boe.es`, `boe.es`) e
  **igualdad exacta** con `Publicacion.urlOficial` (la igualdad da la trazabilidad;
  en FT00020 la fuente se inyecta desde la publicación). **No** comprueba
  alcanzabilidad.
- **Grounding léxico por afirmación** (`SummaryGroundingChecker` +
  `SummaryTextNormalizer`): las afirmaciones son las oraciones de «¿Qué cambia?» y
  «¿A quién afecta?» más cada cifra clave; una afirmación está sustentada si
  **todas** sus cifras aparecen en el contexto y ≥ `MIN_CLAIM_SUPPORT` (= 0.6) de
  sus términos de contenido (sin acentos, sin palabras vacías) están en el contexto;
  `score` = sustentadas / total. Es **conservador**: un falso negativo lleva a
  revisión o descarte, nunca a publicar.
- **Puerto de alcanzabilidad opcional** (`SourceReachability` `suspend` +
  `HttpSourceReachability` con `HttpClient` inyectado y factory): sin puerto solo se
  valida la estructura; con puerto se comprueba que la fuente responde 2xx/3xx (un
  fallo de red es «no alcanzable», no una excepción). El guardrail **no** conoce
  Ktor.
- **Resultado y decisión tipados** (`SummaryGuardrailResult` + `GuardrailDecision` +
  `SummaryGuardrailViolation`): `PUBLISHABLE` / `NEEDS_REVIEW` / `DISCARDED` y una
  **puntuación de grounding** `[0,1]`. Contrato roto, fuente no oficial/no alcanzable
  o `score < DISCARD_THRESHOLD` (= 0.5) ⇒ `DISCARDED`; `score < REVIEW_THRESHOLD`
  (= 0.8) **o violaciones de grounding presentes** (`UNSUPPORTED_CLAIM`/
  `UNSUPPORTED_FIGURE`) ⇒ `NEEDS_REVIEW`; si no, `PUBLISHABLE`. `categoria` nula es
  fail-fast. **Invariante de trazabilidad**: una afirmación o cifra no sustentada
  por el contexto **nunca** publica; como `score` es una fracción, el caso límite
  4 de 5 afirmaciones sustentadas (= 0.8) alcanzaría `REVIEW_THRESHOLD` con una
  violación, así que publicar exige además que `grounding.violations` esté vacía.
- **Servicio** `SummaryGuardrail.evaluate(publication, summary, context)` que
  reutiliza `CitizenSummaryValidator` (FT00019) **sin** duplicar reglas y **no**
  persiste nada.

## Alternativas consideradas

- **Verificación semántica (embeddings/LLM).** Se descarta: introduce red, coste y
  no determinismo en el gate. El grounding **léxico** es offline, determinista y
  testeable con dobles; se asume el falso negativo (documentado) y los umbrales son
  constantes ajustables (el golden set de FT00024 debería calibrarlos).
- **Comprobar la alcanzabilidad dentro del validador puro.** Se descarta: la red no
  puede vivir en una pieza pura. Se separa en un **puerto** `suspend` inyectado de
  forma opcional; el gate usa un doble y la prueba real es **opt-in**.
- **Ampliar `CitizenSummaryValidator` con la veracidad.** Se descarta: mezclaría
  **contrato** (estructura, en `:shared`) con **contenido** (grounding, en `:backend`)
  y rompería la frontera fijada en ADR 0014.
- **Persistir la decisión/confianza y encolar aquí.** Se descarta: la cola de
  revisión y los estados del resumen son FT00023; aquí solo se **exponen** la decisión
  y la puntuación.
- **Descarte automático de todo lo que no sea `PUBLISHABLE`.** Se descarta: la baja
  confianza va a `NEEDS_REVIEW` para revisión humana, sin bloquear el feed (FT00023).
- **Cablear el guardrail en el arranque.** Se descarta: FT00022 es la **pieza**; el
  wiring llega con FT00026+.

## Consecuencias

- Ningún resumen con fuente no oficial/no alcanzable o afirmación fuera del contexto
  queda **publicable**; la baja confianza se marca para revisión y el descarte es
  explícito.
- La frontera **contrato (FT00019) vs. contenido (FT00022)** queda fijada: el
  validador de `:shared` no se modifica.
- Es una **librería sin wiring** y **sin** persistencia: no toca `Application.kt`/job/
  backfill, no añade migración ni endpoints/UI, y no modifica `ResumenDto`/
  `CitizenSummaryValidator`/`HybridSearch`/`CitizenSummaryGenerator`/
  `CachedCitizenSummaryGenerator`. La prueba real es **opt-in** (`BOE_LIVE_TEST=1`).
- Riesgos asumidos y documentados: el grounding es **léxico** (una paráfrasis válida
  puede acabar en revisión/descarte); el **contexto** que verifica el guardrail debe
  ser el **mismo** que alimentó la generación (el wiring de FT00026+ deberá pasarlo;
  `CitizenSummaryGenerator` hoy recupera internamente); `HybridSearch` no filtra por
  `publicationId` (el contexto puede incluir vecinos y «sustentar» de más); un enlace
  estructuralmente válido pero **muerto** pasa el gate offline (solo el puerto opt-in
  lo detecta); cifras con formato distinto («1.000» vs «1000») pueden fallar la regla
  estricta de cifras (se compensa con revisión/descarte); el guardrail es **inerte**
  hasta que FT00026+ lo construya.
