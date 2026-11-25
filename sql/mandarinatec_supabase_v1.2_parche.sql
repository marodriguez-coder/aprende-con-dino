-- =====================================================================
-- Aprende con Dino · MandarinaTec · Parche v1.2 · 25/11/2026
-- Mandarinas (los puntos pasan a ser moneda), tienda de recompensas,
-- protector de racha, niveles secretos y 3 retos secretos nuevos.
-- Requiere v1.0 y v1.1. Pegar en SQL Editor > New query > Run. Se puede ejecutar más de una vez.
-- =====================================================================

-- ---------- 1. Puntos -> mandarinas ----------
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'perfiles' and column_name = 'puntos') then
    alter table public.perfiles rename column puntos to mandarinas;
  end if;
end $$;
alter table public.perfiles add column if not exists total_ganado int not null default 0 check (total_ganado >= 0);
alter table public.perfiles add column if not exists protectores  int not null default 0 check (protectores between 0 and 2);
update public.perfiles p set total_ganado = coalesce((select sum(i.puntos) from public.intentos i where i.user_id = p.id), 0)
 where total_ganado = 0;
comment on column public.perfiles.mandarinas   is 'Saldo gastable';
comment on column public.perfiles.total_ganado is 'Mandarinas ganadas en total; nunca baja';

-- ---------- 2. Retos: principal o secreto ----------
alter table public.retos add column if not exists tipo text not null default 'principal';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'retos_tipo_check') then
    alter table public.retos add constraint retos_tipo_check check (tipo in ('principal','secreto'));
  end if;
end $$;

-- ---------- 3. Tienda, canjes y desbloqueos ----------
create table if not exists public.recompensas (
  codigo      text primary key,
  nombre      text not null,
  descripcion text not null,
  costo       int  not null check (costo > 0),
  orden       int  not null default 0,
  activo      boolean not null default true
);
comment on table public.recompensas is 'Catálogo de la tienda. El equipo puede cambiar precios y textos desde Table Editor.';

create table if not exists public.canjes (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.perfiles(id) on delete cascade,
  codigo     text not null references public.recompensas(codigo),
  costo      int  not null,
  reto_orden int,
  creado     timestamptz not null default now()
);
create index if not exists canjes_user_idx on public.canjes (user_id, creado desc);

create table if not exists public.desbloqueos (
  user_id    uuid not null references public.perfiles(id) on delete cascade,
  reto_orden int  not null references public.retos(orden),
  creado     timestamptz not null default now(),
  primary key (user_id, reto_orden)
);

alter table public.recompensas enable row level security;
alter table public.canjes      enable row level security;
alter table public.desbloqueos enable row level security;
revoke all on public.recompensas, public.canjes, public.desbloqueos from anon, authenticated;
grant select on public.recompensas to anon, authenticated;
grant select on public.canjes, public.desbloqueos to authenticated;

drop policy if exists "recompensas activas visibles" on public.recompensas;
create policy "recompensas activas visibles" on public.recompensas for select to anon, authenticated using (activo);
drop policy if exists "cada uno ve sus canjes" on public.canjes;
create policy "cada uno ve sus canjes" on public.canjes for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "cada uno ve sus desbloqueos" on public.desbloqueos;
create policy "cada uno ve sus desbloqueos" on public.desbloqueos for select to authenticated using ((select auth.uid()) = user_id);

insert into public.recompensas (codigo, nombre, descripcion, costo, orden) values
  ('pista',         'Pista',                'Elimina una opción incorrecta en una pregunta. Se usa dentro del reto.', 10, 1),
  ('segunda',       'Segunda oportunidad',  'Si fallas una pregunta, no pierdes las mandarinas de ese paso. Se usa dentro del reto.', 10, 2),
  ('nivel_secreto', 'Nivel secreto',        'Abre un reto extra con Dino, aparte del reto del día.', 50, 3),
  ('protector',     'Protector de racha',   'Si un día no juegas, tu racha sigue viva. Puedes guardar hasta 2.', 100, 4)
on conflict (codigo) do nothing;   -- no pisa precios cambiados por el equipo

-- ---------- 4. Funciones de juego (reemplazan las de v1.0) ----------
create or replace function private.fijar_nivel(p_nivel int, p_zona text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  if p_nivel not between 0 and 2 then raise exception 'nivel_invalido'; end if;
  update public.perfiles set
    nivel_inicial  = p_nivel,
    siguiente_reto = coalesce((select min(orden) from public.retos where mundo = p_nivel and activo and tipo = 'principal'), 1),
    zona_horaria   = case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_zona)
                          then p_zona else zona_horaria end
  where id = uid and nivel_inicial is null
  returning * into r;
  if r.id is null then select * into r from public.perfiles where id = uid; end if;
  return r;
end $$;

create or replace function private.completar_reto(p_reto int, p_puntos int, p_practico boolean)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); r public.perfiles; d date; pts int; t text; m smallint;
  sig int; bono int := 0; nueva_racha int; usa_prot boolean := false;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  select tipo, mundo into t, m from public.retos where orden = p_reto and activo;
  if t is null then raise exception 'reto_inexistente'; end if;
  d   := private.hoy(r);
  pts := least(greatest(coalesce(p_puntos,0),0), 60);            -- tope por reto

  -- Niveles secretos: hay que haberlos comprado; suman mandarinas solo la primera vez, no tocan la racha
  if t = 'secreto' then
    if not exists (select 1 from public.desbloqueos where user_id = uid and reto_orden = p_reto) then
      raise exception 'reto_bloqueado'; end if;
    if exists (select 1 from public.intentos where user_id = uid and reto_orden = p_reto and not es_repaso) then
      insert into public.intentos (user_id, reto_orden, dia, puntos, practico, es_repaso)
      values (uid, p_reto, d, 0, coalesce(p_practico,false), true);
      return r;
    end if;
    update public.perfiles set mandarinas = mandarinas + pts, total_ganado = total_ganado + pts
     where id = uid returning * into r;
    insert into public.intentos (user_id, reto_orden, dia, puntos, practico)
    values (uid, p_reto, d, pts, coalesce(p_practico,false));
    return r;
  end if;

  if p_reto < r.siguiente_reto then                              -- repaso: se registra, no suma
    insert into public.intentos (user_id, reto_orden, dia, puntos, practico, es_repaso)
    values (uid, p_reto, d, 0, coalesce(p_practico,false), true);
    return r;
  end if;
  if p_reto > r.siguiente_reto then raise exception 'reto_bloqueado'; end if;
  if r.ultimo_dia = d then raise exception 'ya_completaste_hoy'; end if;

  -- Racha: el protector cubre un solo día sin jugar
  if r.ultimo_dia = d - 1 then nueva_racha := r.racha + 1;
  elsif r.ultimo_dia = d - 2 and r.protectores > 0 and r.racha > 0 then nueva_racha := r.racha + 1; usa_prot := true;
  else nueva_racha := 1; end if;

  -- Bonos: +20 al terminar un mundo, +15 cada 7 días de racha
  sig := (select min(orden) from public.retos where orden > p_reto and activo and tipo = 'principal');
  if sig is null or (select mundo from public.retos where orden = sig) <> m then bono := bono + 20; end if;
  if nueva_racha % 7 = 0 then bono := bono + 15; end if;

  update public.perfiles set
    racha          = nueva_racha,
    ultimo_dia     = d,
    mandarinas     = mandarinas + pts + bono,
    total_ganado   = total_ganado + pts + bono,
    protectores    = protectores - case when usa_prot then 1 else 0 end,
    siguiente_reto = coalesce(sig, p_reto + 1)
  where id = uid returning * into r;

  insert into public.intentos (user_id, reto_orden, dia, puntos, practico)
  values (uid, p_reto, d, pts + bono, coalesce(p_practico,false));
  return r;
end $$;

create or replace function private.canjear(p_codigo text, p_reto int)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles; c int;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select costo into c from public.recompensas where codigo = p_codigo and activo;
  if c is null then raise exception 'recompensa_inexistente'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  if r.mandarinas < c then raise exception 'saldo_insuficiente'; end if;

  if p_codigo = 'nivel_secreto' then
    if p_reto is null or not exists (select 1 from public.retos where orden = p_reto and tipo = 'secreto' and activo) then
      raise exception 'reto_inexistente'; end if;
    if exists (select 1 from public.desbloqueos where user_id = uid and reto_orden = p_reto) then
      raise exception 'ya_desbloqueado'; end if;
    insert into public.desbloqueos (user_id, reto_orden) values (uid, p_reto);
  elsif p_codigo = 'protector' then
    if r.protectores >= 2 then raise exception 'maximo_protectores'; end if;
    update public.perfiles set protectores = protectores + 1 where id = uid;
  end if;                                                        -- pista y segunda: se consumen al momento

  update public.perfiles set mandarinas = mandarinas - c where id = uid returning * into r;
  insert into public.canjes (user_id, codigo, costo, reto_orden) values (uid, p_codigo, c, p_reto);
  return r;
end $$;

create or replace function private.tester_accion(p_accion text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into r from public.perfiles where id = uid;
  if not r.es_tester then raise exception 'solo_testers'; end if;
  if p_accion = 'saltar_dia' then
    update public.perfiles set desfase_dias = desfase_dias + 1 where id = uid returning * into r;
  elsif p_accion = 'mandarinas' then
    update public.perfiles set mandarinas = mandarinas + 200, total_ganado = total_ganado + 200 where id = uid returning * into r;
  elsif p_accion = 'reiniciar' then
    delete from public.intentos    where user_id = uid;
    delete from public.canjes      where user_id = uid;
    delete from public.desbloqueos where user_id = uid;
    update public.perfiles set nivel_inicial = null, siguiente_reto = 1, mandarinas = 0, total_ganado = 0,
      protectores = 0, racha = 0, ultimo_dia = null, desfase_dias = 0 where id = uid returning * into r;
  else raise exception 'accion_invalida'; end if;
  return r;
end $$;

revoke all on function private.fijar_nivel(int,text), private.completar_reto(int,int,boolean),
  private.canjear(text,int), private.tester_accion(text) from public, anon;
grant execute on function private.fijar_nivel(int,text), private.completar_reto(int,int,boolean),
  private.canjear(text,int), private.tester_accion(text) to authenticated;

create or replace function public.canjear(p_codigo text, p_reto int default null)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.canjear(p_codigo, p_reto) $$;
create or replace function public.fijar_nivel(p_nivel int, p_zona text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.fijar_nivel(p_nivel, p_zona) $$;
create or replace function public.completar_reto(p_reto int, p_puntos int, p_practico boolean)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.completar_reto(p_reto, p_puntos, p_practico) $$;
create or replace function public.tester_accion(p_accion text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.tester_accion(p_accion) $$;
revoke all on function public.canjear(text,int) from public, anon;
grant execute on function public.canjear(text,int) to authenticated;

-- ---------- 5. Tres niveles secretos ----------
insert into public.retos (orden, mundo, titulo, pasos, tipo) values
  (101, 0, $t$Estafas por WhatsApp$t$, $j$[{"k": "escena", "h": "Dino hace de detective", "l": [["a", "Llega un mensaje a las 11 de la noche, de un número que no tienes guardado."], ["t", "Número desconocido", "¡Hola! Soy tu sobrino, cambié de número. Necesito que me prestes 50 dólares urgente, mañana te los devuelvo."], ["d", "Dino, el detective", "Alto ahí. Número nuevo, prisa y dinero. Tres pistas en una sola frase.", "lupa"], ["t", "Tú", "¿Y si de verdad es él?"], ["d", "Dino, el detective", "Fácil: llámalo a su número de siempre, o pregúntale algo que solo él sepa.", "guia"], ["t", "Número desconocido", "No puedo hablar ahora, solo transfiere rápido, porfa."], ["d", "Dino, el detective", "Caso cerrado. Quien no puede hablar pero sí cobrar, no es tu sobrino.", "alto"]], "m": "Las estafas por WhatsApp casi siempre juntan tres cosas: alguien que dice ser conocido, prisa y dinero. Antes de pagar, confirma por otro canal."}, {"k": "mito", "items": [["Tu banco te puede pedir tu clave por WhatsApp.", false, "Ningún banco serio te pide claves ni códigos por chat."], ["Si alguien te pide el código de 6 dígitos que te llegó por SMS, es una estafa.", true, "Ese código abre tu cuenta. No se le da a nadie, ni a «soporte»."], ["Un enlace con un premio que no pediste es seguro si viene de un conocido.", false, "A tu conocido le pudieron robar la cuenta. Desconfía igual."]]}, {"k": "orden", "o": ["No respondas ni pagues", "Llama al contacto a su número de siempre", "Bloquea y reporta el número", "Avisa en tu grupo familiar"]}, {"k": "reto", "r": "Activa la verificación en dos pasos de WhatsApp: Ajustes, Cuenta, Verificación en dos pasos. Así nadie te roba la cuenta con un código."}]$j$::jsonb, 'secreto'),
  (102, 0, $t$Contraseñas que no se adivinan$t$, $j$[{"k": "escena", "h": "Dino hace de cerrajero", "l": [["a", "Dino abre una cerrajería de llaves digitales."], ["t", "Cliente", "Quiero la misma llave para mi casa, mi carro, mi oficina y mi banco."], ["d", "Dino, el cerrajero", "Si alguien copia esa llave, entra a todo. Una llave por puerta.", "alto"], ["t", "Cliente", "¿Y cómo me acuerdo de tantas?"], ["d", "Dino, el cerrajero", "Con un llavero: un gestor de contraseñas las guarda por ti. Tú solo recuerdas una.", "guia"], ["t", "Cliente", "¿Y si me roban esa una?"], ["d", "Dino, el cerrajero", "Para eso está el segundo candado: un código que llega a tu teléfono. Sin tu teléfono, no entran.", "lupa"]], "m": "Una contraseña distinta para cada cuenta, un gestor que las recuerde por ti y la verificación en dos pasos como segundo candado."}, {"k": "quiz", "q": "¿Cuál contraseña es más difícil de adivinar?", "o": ["123456", "Daniela1996", "cafe-arepa-lluvia-tranvia"], "a": 2}, {"k": "completa", "s": "La verificación en dos pasos funciona como un ___ candado.", "o": ["segundo", "oxidado", "invisible"], "a": 0}, {"k": "reto", "r": "Cambia la contraseña de tu correo por una frase de cuatro palabras que no tengan relación entre sí."}]$j$::jsonb, 'secreto'),
  (103, 1, $t$¿Qué rayos es la nube?$t$, $j$[{"k": "escena", "h": "Dino atiende el guardarropa", "l": [["a", "Una fiesta. En la entrada hay un guardarropa, y lo atiende Dino."], ["t", "Tú", "Le dejo mi chaqueta."], ["d", "Dino, el del guardarropa", "Listo, aquí tiene su ficha. Su chaqueta queda guardada en el depósito.", "guia"], ["t", "Tú", "¿Y si mañana voy a otro local de la misma cadena?"], ["d", "Dino, el del guardarropa", "Muestra la ficha en cualquier local y le entregan su chaqueta. Está en nuestro depósito, no en su bolsillo.", "reto"], ["t", "Tú", "¿Y si pierdo la ficha?"], ["d", "Dino, el del guardarropa", "Ahí sí se complica. Por eso su ficha lleva contraseña.", "alto"]], "m": "La nube es eso: tus archivos guardados en computadoras de una empresa como Google, Microsoft o Apple. Los recuperas desde cualquier equipo con tu cuenta, que es tu ficha."}, {"k": "pares", "h": "Une cada servicio con lo que guarda", "p": [["Google Drive", "Documentos"], ["Google Fotos o iCloud", "Fotos del celular"], ["Gmail", "Correos"], ["WhatsApp", "Copia de tus chats"]]}, {"k": "mito", "items": [["Si se me daña el celular, pierdo lo que estaba en la nube.", false, "Lo que está en la nube sigue ahí. Entras desde otro equipo con tu cuenta."], ["La nube necesita internet para sincronizar.", true, "Sin conexión, los cambios esperan y se suben cuando vuelves a tener internet."]]}, {"k": "reto", "r": "Activa el respaldo automático de fotos de tu celular (Google Fotos o iCloud) y comprueba que una foto se ve desde la web."}]$j$::jsonb, 'secreto')
on conflict (orden) do nothing;

select 'Parche v1.2 aplicado' as resultado,
       (select count(*) from public.retos where tipo = 'secreto') as niveles_secretos,
       (select count(*) from public.recompensas) as recompensas;
