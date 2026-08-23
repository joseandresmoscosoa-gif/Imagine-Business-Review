-- IMG Business Review · módulo Gerencia (Financiero + Comercial)
-- Ejecutar una sola vez en Supabase → SQL Editor → Run.
--
-- fuentes_datos    : links de Google Sheets (publicados como CSV) que
--                    alimentan cada módulo. Se editan desde la pestaña
--                    Ajustes de la app.
-- datos_gerencia    : el último resultado ya calculado por módulo
--                    ('financiero' / 'comercial'), para que abrir la
--                    pestaña sea instantáneo. Se recalcula con el botón
--                    "Actualizar ahora".

create table if not exists fuentes_datos (
  id bigint generated always as identity primary key,
  modulo text not null check (modulo in ('financiero','comercial')),
  etiqueta text not null,
  url text,
  orden integer default 0,
  creado_en timestamptz default now()
);

create table if not exists datos_gerencia (
  id bigint generated always as identity primary key,
  modulo text not null unique check (modulo in ('financiero','comercial')),
  datos jsonb not null default '{}'::jsonb,
  actualizado_en timestamptz
);

alter table fuentes_datos enable row level security;
alter table datos_gerencia enable row level security;

-- Mismo modelo de acceso que el resto de tablas de la app: la clave pública
-- (anon/publishable, la misma que ya está escrita en index.html) puede leer
-- y escribir. La app controla el acceso por PIN en el navegador, no a nivel
-- de base de datos — es el mismo criterio que ya usan clientes, reportes,
-- industria, etc. Si en algún momento ajustas las políticas de esas tablas
-- para restringirlas más (por ejemplo exigiendo Supabase Auth), replica el
-- mismo criterio aquí: estás por meter datos financieros, que pesan más que
-- una cifra de pauta si ese link llegara a manos equivocadas.
create policy "anon acceso total fuentes_datos" on fuentes_datos
  for all using (true) with check (true);
create policy "anon acceso total datos_gerencia" on datos_gerencia
  for all using (true) with check (true);
