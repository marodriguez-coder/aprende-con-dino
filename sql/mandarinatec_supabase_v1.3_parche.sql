-- =====================================================================
-- Aprende con Dino · MandarinaTec · Parche v1.3 · 26/11/2026
-- Guías de MandarinaTec como premio, cofres en el mapa y canje de guías en la tienda.
-- Requiere v1.0, v1.1 y v1.2. Pegar en SQL Editor > New query > Run. Se puede ejecutar más de una vez.
-- =====================================================================

-- ---------- 1. Guías: catálogo público, contenido solo para quien la tiene ----------
create table if not exists public.guias (
  codigo  text primary key,
  titulo  text not null,
  resumen text not null,
  costo   int  not null default 80 check (costo > 0),
  orden   int  not null default 0,
  activo  boolean not null default true
);
create table if not exists public.guias_contenido (
  codigo    text primary key references public.guias(codigo) on delete cascade,
  secciones jsonb not null            -- [{"h":"Título","items":["texto", ...]}, ...]
);
create table if not exists public.guias_usuario (
  user_id uuid not null references public.perfiles(id) on delete cascade,
  codigo  text not null references public.guias(codigo),
  origen  text not null check (origen in ('cofre','tienda')),
  creado  timestamptz not null default now(),
  primary key (user_id, codigo)
);
comment on table public.guias is 'Catálogo de guías. Precio y textos editables desde Table Editor.';
comment on table public.guias_contenido is 'Contenido de cada guía. Solo lo lee quien la ganó o canjeó.';

-- ---------- 2. Cofres del mapa ----------
create table if not exists public.cofres (
  id          int primary key,
  despues_de  int not null references public.retos(orden),   -- se abre al completar este reto
  guia_codigo text references public.guias(codigo),          -- premio: una guía...
  mandarinas  int not null default 0 check (mandarinas >= 0),-- ...o mandarinas
  activo      boolean not null default true,
  check (guia_codigo is not null or mandarinas > 0)
);
create table if not exists public.cofres_abiertos (
  user_id  uuid not null references public.perfiles(id) on delete cascade,
  cofre_id int  not null references public.cofres(id),
  creado   timestamptz not null default now(),
  primary key (user_id, cofre_id)
);
comment on table public.cofres is 'Premios del camino. El contenido se muestra antes de abrir: nada es al azar.';

-- ---------- 3. Seguridad ----------
alter table public.guias           enable row level security;
alter table public.guias_contenido enable row level security;
alter table public.guias_usuario   enable row level security;
alter table public.cofres          enable row level security;
alter table public.cofres_abiertos enable row level security;
revoke all on public.guias, public.guias_contenido, public.guias_usuario, public.cofres, public.cofres_abiertos from anon, authenticated;
grant select on public.guias, public.cofres to anon, authenticated;
grant select on public.guias_contenido, public.guias_usuario, public.cofres_abiertos to authenticated;

drop policy if exists "guias activas visibles" on public.guias;
create policy "guias activas visibles" on public.guias for select to anon, authenticated using (activo);
drop policy if exists "cofres activos visibles" on public.cofres;
create policy "cofres activos visibles" on public.cofres for select to anon, authenticated using (activo);
drop policy if exists "cada uno ve sus guias" on public.guias_usuario;
create policy "cada uno ve sus guias" on public.guias_usuario for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "cada uno ve sus cofres" on public.cofres_abiertos;
create policy "cada uno ve sus cofres" on public.cofres_abiertos for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "contenido solo con la guia" on public.guias_contenido;
create policy "contenido solo con la guia" on public.guias_contenido for select to authenticated
  using (exists (select 1 from public.guias_usuario gu where gu.codigo = guias_contenido.codigo and gu.user_id = (select auth.uid())));

-- ---------- 4. Contenido inicial ----------
insert into public.guias (codigo, titulo, resumen, costo, orden) values
  ('atajos', $t$Atajos de teclado que te ahorran una hora$t$, $t$Los 12 atajos que más tiempo devuelven, para Windows y Mac.$t$, 80, 1),
  ('excel', $t$Excel de supervivencia$t$, $t$Lo mínimo para que una hoja de cálculo trabaje por ti.$t$, 80, 2),
  ('prompts', $t$20 prompts para la oficina$t$, $t$Instrucciones listas para copiar, pegar y adaptar en cualquier chat de IA.$t$, 80, 3),
  ('estafas', $t$Cómo detectar una estafa digital$t$, $t$Las señales que se repiten en casi todos los engaños por chat, correo y llamadas.$t$, 80, 4)
on conflict (codigo) do nothing;
insert into public.guias_contenido (codigo, secciones) values
  ('atajos', $j$[{"h": "Los cinco de todos los días", "items": ["Ctrl + C, Ctrl + X y Ctrl + V: copiar, cortar y pegar.", "Ctrl + Z: deshace lo último. Ctrl + Y lo rehace.", "Ctrl + F: busca una palabra en cualquier documento o página.", "Ctrl + S (Ctrl + G en Office en español): guarda. Úsalo cada pocos minutos.", "Alt + Tab: salta entre ventanas abiertas sin tocar el ratón."]}, {"h": "Para volar en el navegador", "items": ["Ctrl + T abre una pestaña y Ctrl + W la cierra.", "Ctrl + Shift + T recupera la pestaña que cerraste sin querer.", "Ctrl + L te lleva a la barra de direcciones para escribir de una vez."]}, {"h": "Capturas sin programas raros", "items": ["Windows + Shift + S: recortas la parte de la pantalla que quieres.", "En Mac: Cmd + Shift + 4.", "La captura queda copiada: pégala con Ctrl + V en el chat o el correo."]}, {"h": "En Mac", "items": ["Casi todo es igual cambiando Ctrl por Cmd.", "Cmd + Espacio abre el buscador: escribe el nombre de la app y Enter."]}, {"h": "El truco para aprenderlos", "items": ["Elige tres esta semana y pégalos en un papelito junto a la pantalla. Cuando te salgan solos, suma tres más."]}]$j$::jsonb),
  ('excel', $j$[{"h": "La tabla bien hecha", "items": ["Títulos en la primera fila, un dato por celda, una fila por registro.", "Nada de filas vacías en medio ni celdas combinadas: rompen los filtros."]}, {"h": "Las cinco fórmulas que resuelven casi todo", "items": ["=SUMA(B2:B50) suma un rango.", "=PROMEDIO(B2:B50) saca el promedio.", "=CONTAR.SI(C2:C50;\"Pagado\") cuenta cuántas veces aparece algo.", "=SUMAR.SI(C2:C50;\"Pagado\";B2:B50) suma solo lo que cumple una condición.", "=SI(B2>100;\"Alto\";\"Normal\") decide por ti según una regla.", "Si tu Excel usa comas en vez de punto y coma, cambia el separador."]}, {"h": "Filtros y orden", "items": ["Selecciona los títulos y activa Datos, Filtro. Aparece una flecha en cada columna.", "Con la flecha ordenas de mayor a menor o muestras solo lo que quieres ver. No se borra nada."]}, {"h": "Que no se te mueva el título", "items": ["Vista, Inmovilizar, Inmovilizar fila superior. Bajas mil filas y el título sigue ahí."]}, {"h": "Antes de enviarlo", "items": ["Revisa un total a mano con dos o tres filas.", "Guarda una copia en PDF si solo quieres que lo lean."]}]$j$::jsonb),
  ('prompts', $j$[{"h": "Cómo usarlos", "items": ["Cambia lo que está entre corchetes por tu caso.", "Nunca pegues datos sensibles: cédulas, claves ni cifras confidenciales.", "Revisa siempre el resultado antes de enviarlo."]}, {"h": "Correos", "items": ["Redacta un correo cordial para [persona] pidiendo [cosa] antes del [fecha]. Máximo 5 líneas.", "Responde este correo con un no amable y propón una alternativa: [pega el correo].", "Convierte estas notas en un correo claro con viñetas: [notas].", "Reescribe este correo para que suene más profesional, sin alargarlo: [texto].", "Escribe un recordatorio de pago respetuoso para un cliente que debe [monto] desde [fecha]."]}, {"h": "Reuniones", "items": ["Resume esta transcripción en 5 puntos y una lista de pendientes con responsable: [texto].", "Arma la agenda de una reunión de 30 minutos sobre [tema] con tiempos por punto.", "Escribe la minuta de esta reunión en formato: acuerdos, pendientes, fechas. [notas].", "Dame 5 preguntas inteligentes para hacer en una reunión sobre [tema]."]}, {"h": "Documentos y reportes", "items": ["Resume este documento en 3 párrafos para alguien que no conoce el tema: [texto].", "Encuentra errores de ortografía y frases confusas en este texto y corrígelas: [texto].", "Dame los 3 hallazgos principales de esta tabla y un párrafo para mi jefe: [tabla].", "Convierte este texto en una presentación de 5 láminas con título y 3 puntos cada una: [texto].", "Explícame este concepto como si tuviera 12 años, con un ejemplo de oficina: [concepto]."]}, {"h": "Excel y datos", "items": ["Escribe la fórmula de Excel para [lo que necesitas] y explícame cada parte.", "Tengo una tabla con columnas [columnas]. ¿Cómo saco [resultado]? Paso a paso.", "Esta fórmula me da error: [fórmula]. Dime qué está mal y cómo arreglarla."]}, {"h": "Para organizarte", "items": ["Ordena estas tareas por urgencia e importancia y dime por cuál empiezo: [lista].", "Divide este proyecto en pasos pequeños con un tiempo estimado para cada uno: [proyecto].", "Soy [tu cargo]. Dame 5 tareas repetitivas de mi trabajo que podría hacer más rápido con IA."]}]$j$::jsonb),
  ('estafas', $j$[{"h": "Las tres señales", "items": ["Prisa: «es urgente», «solo hoy», «ya mismo».", "Dinero o datos: te piden transferir, o un código, clave o foto de tu documento.", "Canal raro: un número nuevo, un correo extraño o un enlace que no esperabas."]}, {"h": "Lo que nunca se comparte", "items": ["El código de 6 dígitos que llega por SMS o WhatsApp.", "Claves del banco, del correo o de tus redes.", "Fotos de tus tarjetas o de tu documento de identidad a desconocidos."]}, {"h": "Antes de hacer clic", "items": ["Mira la dirección completa del enlace: una letra cambiada delata la trampa.", "Si es de tu banco, no uses el enlace: entra tú mismo desde la app o escribiendo la dirección.", "Los premios que no pediste no existen."]}, {"h": "Si un conocido te pide dinero por chat", "items": ["Llámalo a su número de siempre o hazle una pregunta que solo él sepa.", "Si «no puede hablar ahora», no es él."]}, {"h": "Si ya caíste", "items": ["Llama a tu banco de inmediato para bloquear la tarjeta o la transferencia.", "Cambia tus contraseñas, empezando por el correo.", "Avisa a tus contactos para que no caigan con tu cuenta.", "Guarda capturas y denuncia ante las autoridades de tu país."]}, {"h": "Tu escudo", "items": ["Verificación en dos pasos en WhatsApp, correo y redes.", "Una contraseña distinta por cuenta."]}]$j$::jsonb)
on conflict (codigo) do nothing;

insert into public.cofres (id, despues_de, guia_codigo, mandarinas) values
  (1, 2,  null,      15),
  (2, 3,  'atajos',  0),
  (3, 5,  null,      15),
  (4, 6,  'excel',   0),
  (5, 8,  null,      15),
  (6, 10, 'prompts', 0)
on conflict (id) do nothing;

-- Para que el historial de canjes acepte guías (no aparece en la tienda como recompensa)
insert into public.recompensas (codigo, nombre, descripcion, costo, orden, activo)
values ('guia', 'Guía de MandarinaTec', 'Canje de una guía. El precio real está en la tabla guias.', 80, 99, false)
on conflict (codigo) do nothing;

-- ---------- 5. Funciones ----------
create or replace function private.abrir_cofre(p_cofre int)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles; c public.cofres;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into c from public.cofres where id = p_cofre and activo;
  if c.id is null then raise exception 'cofre_inexistente'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  if r.siguiente_reto <= c.despues_de then raise exception 'cofre_bloqueado'; end if;
  if exists (select 1 from public.cofres_abiertos where user_id = uid and cofre_id = p_cofre) then
    raise exception 'cofre_ya_abierto'; end if;
  insert into public.cofres_abiertos (user_id, cofre_id) values (uid, p_cofre);
  if c.guia_codigo is not null then
    insert into public.guias_usuario (user_id, codigo, origen) values (uid, c.guia_codigo, 'cofre')
    on conflict do nothing;
  end if;
  if c.mandarinas > 0 then
    update public.perfiles set mandarinas = mandarinas + c.mandarinas, total_ganado = total_ganado + c.mandarinas
     where id = uid returning * into r;
  end if;
  return r;
end $$;

create or replace function private.canjear_guia(p_codigo text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles; c int;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select costo into c from public.guias where codigo = p_codigo and activo;
  if c is null then raise exception 'guia_inexistente'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  if exists (select 1 from public.guias_usuario where user_id = uid and codigo = p_codigo) then
    raise exception 'guia_ya_obtenida'; end if;
  if r.mandarinas < c then raise exception 'saldo_insuficiente'; end if;
  insert into public.guias_usuario (user_id, codigo, origen) values (uid, p_codigo, 'tienda');
  update public.perfiles set mandarinas = mandarinas - c where id = uid returning * into r;
  insert into public.canjes (user_id, codigo, costo) values (uid, 'guia', c);
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
    delete from public.intentos        where user_id = uid;
    delete from public.canjes          where user_id = uid;
    delete from public.desbloqueos     where user_id = uid;
    delete from public.guias_usuario   where user_id = uid;
    delete from public.cofres_abiertos where user_id = uid;
    update public.perfiles set nivel_inicial = null, siguiente_reto = 1, mandarinas = 0, total_ganado = 0,
      protectores = 0, racha = 0, ultimo_dia = null, desfase_dias = 0 where id = uid returning * into r;
  else raise exception 'accion_invalida'; end if;
  return r;
end $$;

revoke all on function private.abrir_cofre(int), private.canjear_guia(text), private.tester_accion(text) from public, anon;
grant execute on function private.abrir_cofre(int), private.canjear_guia(text), private.tester_accion(text) to authenticated;

create or replace function public.abrir_cofre(p_cofre int)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.abrir_cofre(p_cofre) $$;
create or replace function public.canjear_guia(p_codigo text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.canjear_guia(p_codigo) $$;
revoke all on function public.abrir_cofre(int), public.canjear_guia(text) from public, anon;
grant execute on function public.abrir_cofre(int), public.canjear_guia(text) to authenticated;

select 'Parche v1.3 aplicado' as resultado,
       (select count(*) from public.guias)  as guias,
       (select count(*) from public.cofres) as cofres;
