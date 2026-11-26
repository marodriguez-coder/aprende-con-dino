-- =====================================================================
-- Aprende con Dino · MandarinaTec · Parche v1.4 · 26/11/2026
-- Premios de aliados (televisor de SoyTechno) y textos de los retos en español neutro.
-- Requiere v1.0 a v1.3. Pegar en una consulta NUEVA del SQL Editor y pulsar Run. Se puede ejecutar más de una vez.
-- =====================================================================

-- ---------- 1. Premios de aliados ----------
create table if not exists public.premios (
  codigo      text primary key,
  nombre      text not null,
  aliado      text not null,
  descripcion text not null,
  costo       int  not null check (costo > 0),
  orden       int  not null default 0,
  activo      boolean not null default true
);
create table if not exists public.solicitudes_premio (
  id      bigint generated always as identity primary key,
  user_id uuid not null references public.perfiles(id) on delete cascade,
  codigo  text not null references public.premios(codigo),
  costo   int  not null,
  estado  text not null default 'pendiente' check (estado in ('pendiente','aprobada','entregada','rechazada')),
  creado  timestamptz not null default now(),
  unique (user_id, codigo)
);
comment on table public.solicitudes_premio is 'Canjes de premios físicos. El equipo los revisa y cambia el estado a mano.';

alter table public.premios            enable row level security;
alter table public.solicitudes_premio enable row level security;
revoke all on public.premios, public.solicitudes_premio from anon, authenticated;
grant select on public.premios to anon, authenticated;
grant select on public.solicitudes_premio to authenticated;
drop policy if exists "premios activos visibles" on public.premios;
create policy "premios activos visibles" on public.premios for select to anon, authenticated using (activo);
drop policy if exists "cada uno ve sus solicitudes" on public.solicitudes_premio;
create policy "cada uno ve sus solicitudes" on public.solicitudes_premio for select to authenticated using ((select auth.uid()) = user_id);

insert into public.premios (codigo, nombre, aliado, descripcion, costo, orden) values
  ('televisor', 'Televisor', 'SoyTechno', 'Premio de nuestro aliado SoyTechno. Al canjearlo, el equipo te contacta por correo para coordinar la entrega.', 2400, 1)
on conflict (codigo) do nothing;

insert into public.recompensas (codigo, nombre, descripcion, costo, orden, activo)
values ('premio', 'Premio de aliado', 'Canje de un premio. El precio real está en la tabla premios.', 2400, 98, false)
on conflict (codigo) do nothing;

-- ---------- 2. Canje de premio: exige cuenta guardada (no invitados) ----------
create or replace function private.canjear_premio(p_codigo text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles; c int;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  if coalesce((select is_anonymous from auth.users where id = uid), true) then raise exception 'requiere_cuenta'; end if;
  select costo into c from public.premios where codigo = p_codigo and activo;
  if c is null then raise exception 'premio_inexistente'; end if;
  select * into r from public.perfiles where id = uid for update;
  if exists (select 1 from public.solicitudes_premio where user_id = uid and codigo = p_codigo) then
    raise exception 'premio_ya_solicitado'; end if;
  if r.mandarinas < c then raise exception 'saldo_insuficiente'; end if;
  insert into public.solicitudes_premio (user_id, codigo, costo) values (uid, p_codigo, c);
  update public.perfiles set mandarinas = mandarinas - c where id = uid returning * into r;
  insert into public.canjes (user_id, codigo, costo) values (uid, 'premio', c);
  return r;
end $$;
revoke all on function private.canjear_premio(text) from public, anon;
grant execute on function private.canjear_premio(text) to authenticated;

create or replace function public.canjear_premio(p_codigo text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.canjear_premio(p_codigo) $$;
revoke all on function public.canjear_premio(text) from public, anon;
grant execute on function public.canjear_premio(text) to authenticated;

-- ---------- 3. Textos de los retos en español neutro ----------
update public.retos set titulo = '¿Qué es una IA?'           where orden = 3   and titulo = '¿Qué rayos es una IA?';
update public.retos set titulo = 'Datos ordenados'           where orden = 6   and titulo = 'Datos en cristiano';
update public.retos set titulo = 'Automatiza lo repetitivo'  where orden = 8   and titulo = 'Automatiza para flojos';
update public.retos set titulo = '¿Qué es una API?'          where orden = 10  and titulo = '¿Qué rayos es una API?';
update public.retos set titulo = '¿Qué es la nube?'          where orden = 103 and titulo = '¿Qué rayos es la nube?';

do $$
declare par text[]; pares text[][] := array[
  ['En cristiano: tu teclado', 'Tu teclado'],
  ['como una arepa bien hecha', 'como una buena receta'],
  ['para pelar una mandarina', 'para pelar una fruta'],
  ['Quiero una arepa reina pepiada.', 'Quiero una hamburguesa.'],
  ['Aquí tiene su arepa.', 'Aquí tiene su hamburguesa.'],
  ['Dino hace de mesonero', 'Dino hace de mesero'],
  ['Dino, el mesonero', 'Dino, el mesero'],
  ['El mesonero', 'El mesero'],
  ['el mesonero', 'el mesero'],
  ['Quitas nombres, cédulas y datos sensibles', 'Quitas nombres, documentos y datos sensibles'],
  ['cafe-arepa-lluvia-tranvia', 'cafe-mesa-lluvia-tranvia'],
  ['solo transfiere rápido, porfa.', 'solo transfiere rápido, por favor.']];
begin
  foreach par slice 1 in array pares loop
    update public.retos set pasos = replace(pasos::text, par[1], par[2])::jsonb, actualizado = now()
     where pasos::text like '%' || par[1] || '%';
  end loop;
end $$;
update public.guias_contenido set secciones = replace(secciones::text, 'datos sensibles: cédulas, claves', 'datos sensibles: documentos de identidad, claves')::jsonb
 where secciones::text like '%cédulas, claves%';

notify pgrst, 'reload schema';

select 'Parche v1.4 aplicado' as resultado,
       (select count(*) from public.premios) as premios,
       (select count(*) from public.retos where pasos::text ~ 'arepa|mesonero|cristiano') as textos_pendientes;
