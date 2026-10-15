# Capturas — FT00053 `ui-design-refresh`

Las capturas **antes/después** no se pudieron tomar en esta sesión. El entorno de
ejecución es **headless**: el navegador del harness no tiene ventana visible y
`browser.screenshot` falla con «Screenshot needs a visible tab».

## Qué sí se verificó

- La **Web (Wasm) de producción** se construyó y **arrancó**:
  `./gradlew :composeApp:wasmJsBrowserDistribution` → `BUILD SUCCESSFUL`, y el
  distribuible servido en local cargó correctamente (el servidor estático
  registró `200` para `index.html`, `composeApp.js` y los dos `.wasm`).
- El gate del cliente quedó en verde (compilación Wasm, `jvmTest`, `detekt` +
  `cpdCheck`) y `init.sh --with-client`.

## Cómo reproducir las capturas

1. `./gradlew :composeApp:wasmJsBrowserDistribution`
2. Servir `composeApp/build/dist/wasmJs/productionExecutable` con un servidor
   estático y abrir `index.html` en un navegador **con ventana visible**.
3. Para ver **contenido** de ejemplo sin backend, apuntar temporalmente el
   *composition root* (`app/App.kt`) a los repositorios en memoria
   (`InMemoryFeedRepository`, `InMemorySearchRepository`,
   `InMemoryDetailRepository`, `InMemoryChatRepository`).

Las capturas «antes» corresponden a `origin/main` (estado previo al rediseño) y
las «después» al head de la rama `feat/ft00053-ui-design-refresh`.
