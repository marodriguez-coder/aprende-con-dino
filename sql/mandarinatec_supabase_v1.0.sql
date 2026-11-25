-- =====================================================================
-- Aprende con Dino · MandarinaTec
-- Script de base de datos para Supabase · v1.0 · 25/11/2026
-- Pegar completo en: Supabase > SQL Editor > New query > Run
-- Se puede ejecutar más de una vez: no duplica datos ni borra progreso.
-- =====================================================================

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------- 1. Retos (contenido editable por el equipo) ----------
create table if not exists public.retos (
  orden      int primary key check (orden > 0),
  mundo      smallint not null check (mundo between 0 and 2),  -- 0 Principiante, 1 Intermedio, 2 Avanzado
  titulo     text not null,
  pasos      jsonb not null,                                   -- actividades del reto
  activo     boolean not null default true,
  actualizado timestamptz not null default now()
);
comment on table public.retos is 'Contenido de los retos diarios. Editar desde Table Editor. Para retirar uno, poner activo = false.';

-- ---------- 2. Perfiles (uno por usuario, se crea solo al registrarse) ----------
create table if not exists public.perfiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  email          text not null,
  usuario        text not null,
  nivel_inicial  smallint check (nivel_inicial between 0 and 2),
  siguiente_reto int not null default 1,
  puntos         int not null default 0 check (puntos >= 0),
  racha          int not null default 0 check (racha >= 0),
  ultimo_dia     date,
  zona_horaria   text not null default 'America/Caracas',
  es_tester      boolean not null default false,               -- activar a mano para ver los controles de prueba
  desfase_dias   int not null default 0,                       -- solo testers: simula días futuros
  creado         timestamptz not null default now()
);

-- ---------- 3. Intentos (un registro por reto terminado, para métricas) ----------
create table if not exists public.intentos (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.perfiles(id) on delete cascade,
  reto_orden int not null references public.retos(orden),
  dia        date not null,
  puntos     int not null default 0,
  practico   boolean not null default false,
  es_repaso  boolean not null default false,
  creado     timestamptz not null default now()
);
create index if not exists intentos_user_idx on public.intentos (user_id, creado desc);
create index if not exists intentos_dia_idx  on public.intentos (dia);

-- ---------- 4. Seguridad: RLS y permisos ----------
alter table public.retos    enable row level security;
alter table public.perfiles enable row level security;
alter table public.intentos enable row level security;

revoke all on public.retos, public.perfiles, public.intentos from anon, authenticated;
grant select on public.retos    to anon, authenticated;
grant select on public.perfiles to authenticated;
grant select on public.intentos to authenticated;

drop policy if exists "retos activos visibles" on public.retos;
create policy "retos activos visibles" on public.retos
  for select to anon, authenticated using (activo);

drop policy if exists "cada uno ve su perfil" on public.perfiles;
create policy "cada uno ve su perfil" on public.perfiles
  for select to authenticated using ((select auth.uid()) = id);

drop policy if exists "cada uno ve sus intentos" on public.intentos;
create policy "cada uno ve sus intentos" on public.intentos
  for select to authenticated using ((select auth.uid()) = user_id);
-- Nadie escribe directo en perfiles ni intentos: todo pasa por las funciones de abajo.

-- ---------- 5. Crear el perfil al registrarse ----------
create or replace function private.crear_perfil()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, email, usuario)
  values (new.id, coalesce(new.email,''), split_part(coalesce(new.email,'usuario'),'@',1))
  on conflict (id) do nothing;
  return new;
end $$;
revoke all on function private.crear_perfil() from public, anon, authenticated;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function private.crear_perfil();

-- Perfiles de usuarios que ya existían antes de correr este script
insert into public.perfiles (id, email, usuario)
select id, coalesce(email,''), split_part(coalesce(email,'usuario'),'@',1) from auth.users
on conflict (id) do nothing;

-- ---------- 6. Funciones de juego ----------
-- Lógica privada (security definer, con chequeo de auth.uid()) en schema no expuesto;
-- envoltorios públicos security invoker para llamarlas desde la app con supabase.rpc().
grant usage on schema private to authenticated;

create or replace function private.hoy(p public.perfiles)
returns date language sql stable set search_path = '' as $$
  select ((now() at time zone p.zona_horaria)::date + p.desfase_dias)
$$;

-- 6.1 Guardar el resultado del test de nivel (una sola vez) y la zona horaria
create or replace function private.fijar_nivel(p_nivel int, p_zona text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  if p_nivel not between 0 and 2 then raise exception 'nivel_invalido'; end if;
  update public.perfiles set
    nivel_inicial  = p_nivel,
    siguiente_reto = coalesce((select min(orden) from public.retos where mundo = p_nivel and activo), 1),
    zona_horaria   = case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_zona)
                          then p_zona else zona_horaria end
  where id = uid and nivel_inicial is null
  returning * into r;
  if r.id is null then select * into r from public.perfiles where id = uid; end if;
  return r;
end $$;

-- 6.2 Terminar un reto: valida uno por día, calcula racha y puntos en el servidor
create or replace function private.completar_reto(p_reto int, p_puntos int, p_practico boolean)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles; d date; pts int;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  if not exists (select 1 from public.retos where orden = p_reto and activo) then raise exception 'reto_inexistente'; end if;
  d := private.hoy(r);

  if p_reto < r.siguiente_reto then                       -- repaso: se registra, no suma
    insert into public.intentos (user_id, reto_orden, dia, puntos, practico, es_repaso)
    values (uid, p_reto, d, 0, coalesce(p_practico,false), true);
    return r;
  end if;
  if p_reto > r.siguiente_reto then raise exception 'reto_bloqueado'; end if;
  if r.ultimo_dia = d then raise exception 'ya_completaste_hoy'; end if;

  pts := least(greatest(coalesce(p_puntos,0),0), 60);   -- tope por reto
  update public.perfiles set
    racha          = case when ultimo_dia = d - 1 then racha + 1 else 1 end,
    ultimo_dia     = d,
    puntos         = puntos + pts,
    siguiente_reto = coalesce((select min(orden) from public.retos where orden > p_reto and activo), p_reto + 1)
  where id = uid returning * into r;

  insert into public.intentos (user_id, reto_orden, dia, puntos, practico)
  values (uid, p_reto, d, pts, coalesce(p_practico,false));
  return r;
end $$;

-- 6.3 Controles de prueba (solo perfiles con es_tester = true)
create or replace function private.tester_accion(p_accion text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into r from public.perfiles where id = uid;
  if not r.es_tester then raise exception 'solo_testers'; end if;
  if p_accion = 'saltar_dia' then
    update public.perfiles set desfase_dias = desfase_dias + 1 where id = uid returning * into r;
  elsif p_accion = 'reiniciar' then
    delete from public.intentos where user_id = uid;
    update public.perfiles set nivel_inicial = null, siguiente_reto = 1, puntos = 0, racha = 0,
      ultimo_dia = null, desfase_dias = 0 where id = uid returning * into r;
  else raise exception 'accion_invalida'; end if;
  return r;
end $$;

revoke all on function private.hoy(public.perfiles), private.fijar_nivel(int,text),
  private.completar_reto(int,int,boolean), private.tester_accion(text) from public, anon;
grant execute on function private.hoy(public.perfiles), private.fijar_nivel(int,text),
  private.completar_reto(int,int,boolean), private.tester_accion(text) to authenticated;

-- Envoltorios públicos (lo que llama la app)
create or replace function public.fijar_nivel(p_nivel int, p_zona text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.fijar_nivel(p_nivel, p_zona) $$;
create or replace function public.completar_reto(p_reto int, p_puntos int, p_practico boolean)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.completar_reto(p_reto, p_puntos, p_practico) $$;
create or replace function public.tester_accion(p_accion text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.tester_accion(p_accion) $$;
create or replace function public.hoy_usuario()
returns date language sql stable security invoker set search_path = '' as
$$ select private.hoy(p) from public.perfiles p where p.id = (select auth.uid()) $$;

revoke all on function public.fijar_nivel(int,text), public.completar_reto(int,int,boolean),
  public.tester_accion(text), public.hoy_usuario() from public, anon;
grant execute on function public.fijar_nivel(int,text), public.completar_reto(int,int,boolean),
  public.tester_accion(text), public.hoy_usuario() to authenticated;

-- ---------- 7. Contenido inicial: 10 retos ----------
insert into public.retos (orden, mundo, titulo, pasos) values
  (1, 0, $t$El atajo que te ahorra 10 clics$t$, $j$[{"k": "card", "d": "En cristiano: tu teclado tiene trucos que usan los que salen temprano. <b>Ctrl + C</b> copia, <b>Ctrl + X</b> corta, <b>Ctrl + V</b> pega y <b>Ctrl + Z</b> deshace la metida de pata. En Mac es lo mismo con la tecla Cmd."}, {"k": "pares", "h": "Une cada atajo con lo que hace", "p": [["Ctrl + C", "Copiar"], ["Ctrl + V", "Pegar"], ["Ctrl + Z", "Deshacer"], ["Ctrl + X", "Cortar"]]}, {"k": "quiz", "q": "Borraste un párrafo sin querer. ¿Qué tocas?", "o": ["Ctrl + V", "Ctrl + Z", "Cierras todo y lloras"], "a": 1}, {"k": "orden", "o": ["Selecciona el texto", "Toca Ctrl + C", "Haz clic donde lo quieres", "Toca Ctrl + V"]}, {"k": "reto", "r": "Copia una frase de cualquier página y pégala en una nota usando solo el teclado. Después deshaz con Ctrl + Z."}]$j$::jsonb),
  (2, 0, $t$PDF sin dramas$t$, $j$[{"k": "card", "d": "Un PDF es como una foto de tu documento: se ve igual en cualquier computadora o celular y nadie te mueve la tabla. Por eso lo que mandas al jefe va en PDF."}, {"k": "mito", "items": [["Un PDF se ve igual en cualquier equipo.", true, "Para eso existe: lo que tú ves es lo que ve el otro."], ["Para crear un PDF hay que pagar un programa.", false, "Word, Google Docs y hasta tu celular lo hacen sin pagar nada."], ["Un PDF se puede abrir desde el celular.", true, "Cualquier teléfono lo abre sin instalar nada raro."]]}, {"k": "orden", "o": ["Abre tu documento", "Entra a Archivo", "Elige Guardar como", "Cambia el tipo a PDF", "Dale a Guardar"]}, {"k": "reto", "r": "Convierte a PDF un documento tuyo, el que sea. Ábrelo para comprobar que se ve igual."}]$j$::jsonb),
  (3, 0, $t$¿Qué rayos es una IA?$t$, $j$[{"k": "escena", "h": "Dino hace de pasante nuevo en la oficina", "l": [["a", "Lunes, 8:05 a. m. Llega el pasante que se leyó toda la biblioteca."], ["t", "Tú", "Necesito un correo para pedirle una prórroga al cliente."], ["d", "Dino, el pasante", "Listo. Aquí tienes tres versiones: formal, cercana y cortita."], ["t", "Tú", "¡Qué rápido! ¿Y cuánto vendimos en marzo?"], ["d", "Dino, el pasante", "Exactamente 48.312 dólares."], ["t", "Tú", "Tú no tienes acceso a las ventas…"], ["d", "Dino, el pasante", "Cierto. Me lo inventé, pero sonó convincente, ¿no?"]], "m": "Eso es una IA de chat: un pasante rapidísimo y muy leído que a veces inventa con total seguridad. Tú pides, tú revisas."}, {"k": "completa", "s": "Lo que le escribes a la IA se llama ___.", "o": ["píxel", "prompt", "plugin"], "a": 1}, {"k": "mito", "items": [["La IA siempre dice la verdad.", false, "A veces inventa. Los datos importantes se revisan."], ["Puedes escribirle como le hablas a un vecino.", true, "No hace falta ningún idioma secreto."], ["Para usar una IA hay que saber programar.", false, "Si sabes mandar un mensaje, sabes usarla."]]}, {"k": "reto", "r": "Pídele a una IA (o a Mandarina SOS) que te explique algo de tu trabajo en tres líneas."}]$j$::jsonb),
  (4, 1, $t$El prompt con receta$t$, $j$[{"k": "card", "d": "Un buen prompt lleva cuatro ingredientes, como una arepa bien hecha: <b>quién</b> debe ser la IA, <b>qué</b> quieres, <b>para quién o para qué</b> es, y <b>cómo</b> lo quieres de vuelta."}, {"k": "prompt", "s": [["Papel", ["Eres asistente de ventas.", "Hola."], 0], ["Tarea", ["Haz algo con esto.", "Resume estas notas de la reunión."], 1], ["Contexto", ["Es para mi jefe, que tiene dos minutos para leerlo.", "Es para ya."], 0], ["Formato", ["Como tú veas.", "En 5 puntos cortos."], 1]]}, {"k": "quiz", "q": "¿Qué le falta a «Hazme un correo»?", "o": ["Nada, está perfecto", "Contexto: para quién y sobre qué", "Palabras en inglés"], "a": 1}, {"k": "reto", "r": "Escribe un prompt con los cuatro ingredientes para un correo que de verdad tengas pendiente."}]$j$::jsonb),
  (5, 1, $t$Excel sin sudar$t$, $j$[{"k": "card", "d": "Para sumar una columna escribes <b>=SUMA(A1:A10)</b> y listo. Y el filtro es como un colador: te muestra solo las filas que quieres, sin borrar nada."}, {"k": "completa", "s": "Toda fórmula empieza con el signo ___.", "o": ["#", "@", "="], "a": 2}, {"k": "orden", "o": ["Haz clic en una celda vacía", "Escribe =SUMA(", "Selecciona las celdas a sumar", "Cierra el paréntesis y toca Enter"]}, {"k": "quiz", "q": "¿Qué hace el filtro?", "o": ["Borra las filas que sobran", "Muestra solo lo que pides, sin borrar", "Cambia los colores"], "a": 1}, {"k": "reto", "r": "Abre una hoja de cálculo, escribe cinco números en una columna y súmalos con =SUMA."}]$j$::jsonb),
  (6, 1, $t$Datos en cristiano$t$, $j$[{"k": "card", "d": "Una tabla ordenada es como un clóset ordenado: cada <b>fila</b> es una sola cosa (un cliente, una venta) y cada <b>columna</b> guarda un solo dato (nombre, monto, fecha). Así cualquier herramienta, incluida la IA, la entiende."}, {"k": "quiz", "q": "¿Cuál celda está mal?", "o": ["500", "Ana Pérez", "Ana - 500 - pagó ayer"], "a": 2}, {"k": "mito", "items": [["Meter dos datos en una celda ahorra espacio y no pasa nada.", false, "Después no puedes sumar ni filtrar. Un dato por celda."], ["La primera fila lleva los títulos.", true, "Así todos, IA incluida, saben qué hay en cada columna."]]}, {"k": "orden", "o": ["Pon los títulos en la primera fila", "Deja un dato por columna", "Usa una fila por registro", "Quita las filas vacías"]}, {"k": "reto", "r": "Toma una lista tuya que esté desordenada y pásala a tabla: títulos arriba y un dato por celda."}]$j$::jsonb),
  (7, 2, $t$Elige tu IA$t$, $j$[{"k": "card", "d": "No existe una IA para todo, igual que no usas un cuchillo de pan para pelar una mandarina. Primero la tarea, después la herramienta."}, {"k": "pares", "h": "Une cada tarea con su herramienta", "p": [["Redactar un correo", "Chat de IA"], ["Resumir una reunión grabada", "Transcriptor"], ["Hacer un afiche", "Generador de imágenes"], ["Sumar las ventas del mes", "Hoja de cálculo"]]}, {"k": "quiz", "q": "¿Qué defines primero?", "o": ["La tarea que quieres resolver", "La IA que está de moda", "El precio"], "a": 0}, {"k": "reto", "r": "Piensa en una tarea que te quita tiempo y busca en el Recomendador qué IA le sirve."}]$j$::jsonb),
  (8, 2, $t$Automatiza para flojos$t$, $j$[{"k": "escena", "h": "Dino hace de portero del edificio", "l": [["a", "Recepción. Dino tiene una libreta con una sola regla escrita."], ["t", "Mensajero", "Buenas, traigo una factura del proveedor."], ["d", "Dino, el portero", "Factura del proveedor… mi regla dice: piso 3, carpeta de pagos. Pase."], ["t", "Otro mensajero", "Yo traigo otra factura del mismo proveedor."], ["d", "Dino, el portero", "Piso 3, carpeta de pagos. Ni tengo que pensarlo."], ["t", "Tú", "¿Y no te cansas de repetir lo mismo?"], ["d", "Dino, el portero", "Para nada. Tú escribiste la regla una vez. El que repite soy yo."]], "m": "Automatizar es dejar una regla escrita: si pasa esto, haz aquello. Tú la escribes una vez y la máquina la repite sin quejarse."}, {"k": "completa", "s": "Si llega una factura, ___ en la carpeta de pagos.", "o": ["guárdala", "bórrala", "imprímela dos veces"], "a": 0}, {"k": "quiz", "q": "En esa regla, ¿qué es lo que la dispara?", "o": ["La carpeta de pagos", "Que llegue la factura", "El portero"], "a": 1}, {"k": "orden", "o": ["Detecta lo que repites", "Escribe qué lo dispara", "Define qué debe pasar", "Prueba con un caso"]}, {"k": "reto", "r": "Crea una regla en tu correo que mande los mensajes de un remitente a su propia carpeta."}]$j$::jsonb),
  (9, 2, $t$Reporte en 10 minutos$t$, $j$[{"k": "card", "d": "Junta lo aprendido: tabla ordenada + buen prompt = reporte. Pegas tus datos, pides los tres hallazgos principales y un párrafo para tu jefe. Dos reglas: nada de datos sensibles, y las cifras se revisan contra tu tabla."}, {"k": "quiz", "q": "¿Qué haces antes de pegar datos en una IA?", "o": ["Quitas nombres, cédulas y datos sensibles", "Nada", "Los pasas a mayúsculas"], "a": 0}, {"k": "completa", "s": "Las cifras que te da la IA se ___ contra tu tabla.", "o": ["redondean", "verifican", "adornan"], "a": 1}, {"k": "orden", "o": ["Ordena tu tabla", "Quita los datos sensibles", "Pide 3 hallazgos y un párrafo", "Verifica las cifras"]}, {"k": "reto", "r": "Haz un mini reporte con datos tuyos (o inventados) y comprueba un número contra la tabla."}]$j$::jsonb),
  (10, 2, $t$¿Qué rayos es una API?$t$, $j$[{"k": "escena", "h": "Dino hace de mesonero", "l": [["a", "Un restaurante. Tú estás en la mesa. La cocina queda detrás de una puerta que dice «Solo personal»."], ["t", "Tú", "Buenas. Quiero una arepa reina pepiada."], ["d", "Dino, el mesonero", "Anotado. Ya vuelvo."], ["a", "Dino cruza la puerta, habla con la cocina y regresa."], ["d", "Dino, el mesonero", "Aquí tiene su arepa."], ["t", "Tú", "¿Puedo pasar yo a la cocina a prepararla?"], ["d", "Dino, el mesonero", "Ni lo sueñe. Usted pide, yo llevo y traigo. Así nadie se quema."]], "m": "Eso es una API: el mesonero entre dos sistemas. Tu app pide, la API lleva el pedido al otro sistema y vuelve con la respuesta. Tú nunca entras a la cocina."}, {"k": "pares", "h": "Une el restaurante con el mundo digital", "p": [["Tú en la mesa", "La app que usas"], ["El mesonero", "La API"], ["La cocina", "El otro sistema"], ["El plato", "Los datos que pediste"]]}, {"k": "mito", "items": [["Para aprovechar una API tienes que saber programar.", false, "Ya las usas a diario sin enterarte: cada vez que una app te muestra el clima o un mapa."], ["Cuando pagas en una tienda en línea, una API habla con el banco.", true, "La tienda es la mesa, el banco es la cocina y la API lleva y trae."]]}, {"k": "quiz", "q": "Tu app de delivery muestra un mapa. ¿De dónde sale?", "o": ["La app dibuja las calles a mano", "Se lo pide a un servicio de mapas con una API", "Viene instalado en el teléfono del repartidor"], "a": 1}, {"k": "reto", "r": "Abre una app que uses a diario y encuentra un dato que viene de otro lado: el mapa, el clima, el precio del dólar. Ese viaje lo hizo una API."}]$j$::jsonb)
on conflict (orden) do nothing;   -- no pisa ediciones hechas por el equipo

-- Listo. Comprobación rápida:
select orden, mundo, titulo, jsonb_array_length(pasos) as actividades from public.retos order by orden;
