# IMG Business Review

App de una sola página para la agencia IMG. Cada cliente entra con un PIN de 4 dígitos y ve su review semanal de meta ads, industria, academia y proyectos. El rol **admin** (gerencia) ve además los módulos de administración y de gerencia (Financiero, Comercial, Ajustes).

Sin build step: es un único `index.html` con vanilla JS + Chart.js + PapaParse cargados por CDN, y Supabase (Postgres vía REST/PostgREST) como backend.

## Cómo está desplegado

- **Repo**: `github.com/joseandresmoscosoa-gif/Imagine-Business-Review`, rama `master`.
- **Hosting**: Netlify, subido **manualmente** (drag & drop del `index.html`) — no está conectado al repo de GitHub, así que cada cambio de código hay que volver a subirlo a mano después de que se haga el push aquí.
- **Backend**: Supabase. Las credenciales (`SUPA_URL`, `SUPA_KEY`) están hardcodeadas al inicio del `<script>` en `index.html` — es la clave pública (anon/publishable), pensada para eso.

### Modo demostración

Si `SUPA_URL` contiene `TU-PROYECTO` o `SUPA_KEY` contiene `TU_CLAVE`, la app entra en modo demo: todas las llamadas a Supabase se resuelven contra datos de ejemplo en memoria (objeto `D` al inicio del script), sin tocar la red. Sirve para probar la interfaz sin credenciales reales. El PIN `1017` entra como admin, `2401` como cliente de ejemplo.

## Modelo de datos (Supabase)

Tablas ya existentes antes de este proyecto (no gestionadas por este repo, viven directo en Supabase):
- `clientes` — nombre, slug, pin, rol (`admin`/`cliente`), industria, acento, ad_account, contacto, activo.
- `reportes` — review semanal por cliente (métricas, campañas, serie de 8 semanas, audiencia, logros, oportunidades).
- `industria` — diario semanal de industria por cliente.
- `academia` — lecciones semanales por cliente.
- `proyectos` — proyectos en marcha por cliente.
- `imagine` — textos globales de "Cómo trabajamos" (visibles para todos los clientes).

Tablas del módulo Gerencia (creadas por `supabase/gerencia.sql`, correr una sola vez en el SQL Editor de Supabase):
- `fuentes_datos` — links de Google Sheets (publicados como CSV) que alimentan Financiero/Comercial. Se editan desde la pestaña **Ajustes**. Columnas: `modulo` (`financiero`/`comercial`), `etiqueta`, `url`, `orden`.
- `datos_gerencia` — el último resultado ya calculado por módulo (fila única por `modulo`, con `datos` en jsonb y `actualizado_en`). Se recalcula con el botón "Actualizar ahora"; mientras nadie le da clic, se sigue mostrando esta foto guardada.

### Seguridad — importante

El PIN es una puerta de **interfaz**, no una restricción a nivel de base de datos: la clave pública de Supabase está en el HTML (visible en el código fuente) y por default en este proyecto las tablas tienen políticas RLS permisivas (cualquiera con esa clave puede leer/escribir todas las tablas vía la API REST de Supabase, sin pasar por el PIN). Esto ya era así para `clientes`/`reportes`/etc. antes de este trabajo; el módulo Gerencia replica el mismo criterio para `fuentes_datos`/`datos_gerencia`. Dado que ahora hay datos financieros (P&L) en juego, vale la pena revisar si conviene endurecer las políticas de RLS (por ejemplo con Supabase Auth) más adelante.

## Módulo Gerencia (Financiero + Comercial + Ajustes)

Solo visible para el rol `admin`. Lee datos de Google Sheets publicados como CSV — **no hay actualización automática**: alguien tiene que entrar y darle "Actualizar ahora" (en Ajustes, o directo en la pestaña Financiero/Comercial) para que se vuelvan a leer los Sheets y se recalculen los números. Mientras tanto se muestra la última foto guardada en `datos_gerencia`.

### Cómo conectar un Google Sheet

El link que funciona de forma confiable (evita bloqueos de CORS que sí ocurren con el link normal de "Publicar en la Web") es el formato **gviz**:

```
https://docs.google.com/spreadsheets/d/{ID_DEL_SHEET}/gviz/tq?tqx=out:csv&gid={GID_DE_LA_PESTAÑA}
```

- `{ID_DEL_SHEET}`: se obtiene de la URL normal del Sheet cuando lo tienes abierto para editar (`.../spreadsheets/d/AQUÍ/edit`).
- `{GID_DE_LA_PESTAÑA}`: el número que aparece después de `#gid=` en la URL cuando tienes esa pestaña específica seleccionada.
- El Sheet necesita acceso general en **"Cualquier persona con el enlace" → Lector** (botón Compartir, no "Publicar en la Web") para que este link funcione sin iniciar sesión.

En Ajustes se guarda una fila por cada pestaña/hoja conectada (etiqueta + link), agrupadas por módulo (`financiero` / `comercial`). Financiero espera 3 hojas: Pérdidas y Ganancias, Ingresos, Gastos de Funcionamiento — pero funciona con cualquier subconjunto de esas tres.

### Cómo lee las hojas (parser)

Todo el código relevante vive en la sección `GERENCIA · FINANCIERO Y COMERCIAL` de `index.html`, hacia el final del `<script>`.

**Financiero** — intenta dos formatos, en orden:
1. **Con fila de encabezados real**: una fila con "Concepto" (o similar) seguida de columnas de mes (`Ene-25`, `feb 2025`, etc.), o una fila con columnas de fecha/concepto/valor (formato largo).
2. **Sin fila de encabezados** (`parseFuenteFinancieraSinHeader`): pasa seguido porque lo que se ve en pantalla como encabezados de mes en realidad es el eje de un gráfico incrustado sobre la tabla, y los gráficos no se exportan a CSV. En ese caso el código busca el año en una celda suelta de las primeras filas (p. ej. "2026"), ancla a la primera fila con una etiqueta de texto seguida de al menos 3 valores numéricos, y lee los 12 meses siguientes por posición de columna (columna 1 = enero, columna 2 = febrero, etc.), deteniéndose tras dos filas seguidas sin valores para no arrastrar una segunda tabla que venga más abajo en la misma pestaña.

Reglas de cálculo (`calculaFinanciero`):
- Si hay una fuente cuya etiqueta contiene "ingreso" o "gasto", esa fuente manda para el total de Ingresos/Gastos de ese periodo (prefiriendo una fila cuyo concepto empiece con "total" o termine en "neta(s)"/"total(es)" si existe, para no sumar detalle + total dos veces). Si no hay una fuente dedicada, se infiere por palabras clave en el concepto (`ingres|venta` / `gasto|costo`) dentro de la fuente de Pérdidas y Ganancias.
- La Utilidad Neta se toma de una fila que matchee "utilidad neta"/"resultado neto"/"utilidad del ejercicio" si existe; si no, se calcula como Ingresos − Gastos.
- Los periodos finales donde ambos (ingreso y gasto) dan exactamente cero se recortan — pasa cuando una fila de fórmula trae "0,00" ya calculado para meses futuros sin datos cargados todavía, y sin este recorte el tablero mostraría un mes vacío en vez del último mes real.

**Comercial** — espera una fila por periodo con columnas de fecha/ventas/transacciones (el ticket promedio se calcula solo si no viene). Si la hoja trae comparativo año-vs-año (`Venta 2026` / `Venta 2025`) y/o presupuesto (`Presupuesto`, `Cumplimiento vs Presupuesto`), el parser los detecta automáticamente e ignora columnas de "Diferencia"/comparación para no confundirlas con el valor real — esos datos alimentan la tarjeta "Comparativo anual y presupuesto" y los insights de año contra año / racha de cumplimiento de presupuesto.

Ambos parsers son heurísticos (no hay un esquema fijo impuesto al usuario) — si una hoja nueva no se lee bien, lo más rápido es pedirle al usuario el CSV crudo (abrir el link gviz en una pestaña, copiar el texto) y probar el parser contra eso directamente en vez de adivinar por capturas de pantalla.

## Desarrollo

No hay build ni dependencias que instalar — es abrir `index.html` en el navegador. Para probar con datos de ejemplo sin tocar Supabase, cambia temporalmente `SUPA_URL`/`SUPA_KEY` a algo que contenga `TU-PROYECTO`/`TU_CLAVE` (activa el modo demo) y ábrelo con doble clic o sírvelo con cualquier servidor estático — **nunca hagas ese cambio en el archivo que subes a Netlify**, es solo para probar localmente.
