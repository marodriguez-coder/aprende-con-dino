-- =====================================================================
-- Aprende con Dino · MandarinaTec · Parche v1.5 · 26/11/2026
-- Tres temas (IA, Tecnología, Herramientas) con submundos Principiante, Intermedio y Avanzado.
-- Un reto nuevo por día en cada tema. Onboarding con tema, nivel y meta semanal.
-- Requiere v1.0 a v1.4. Pegar en una consulta NUEVA del SQL Editor y pulsar Run. Se puede ejecutar más de una vez.
-- =====================================================================

-- ---------- 1. Retos: tema y posición dentro del submundo (mundo = nivel 0, 1, 2) ----------
alter table public.retos add column if not exists tema text;
alter table public.retos add column if not exists pos  int not null default 1;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'retos_tema_check') then
    alter table public.retos add constraint retos_tema_check check (tema is null or tema in ('ia','tecno','herr'));
  end if;
end $$;

update public.retos r set tema = v.tema, mundo = v.nivel, pos = v.pos, tipo = 'principal'
from (values
  (1,'herr',0,1),(2,'herr',0,2),(3,'ia',0,1),(4,'ia',1,1),(5,'herr',1,1),(6,'herr',1,2),(7,'ia',1,2),
  (8,'herr',2,1),(9,'ia',2,1),(10,'tecno',2,1),(101,'tecno',0,1),(102,'tecno',0,2),(103,'tecno',1,1)
) as v(orden,tema,nivel,pos)
where r.orden = v.orden;

insert into public.retos (orden, mundo, titulo, pasos, tipo, tema, pos) values
  (11, 0, $t$Tu primera conversación con una IA$t$, $j$[{"k": "card", "d": "Hablarle a una IA es como escribirle a un compañero de trabajo muy rápido. No necesitas palabras técnicas: escribe lo que necesitas como lo dirías en voz alta. Si la respuesta no te sirve, pídele que la cambie."}, {"k": "orden", "o": ["Abre un chat de IA", "Escribe tu pregunta con tus palabras", "Lee la respuesta completa", "Pide un ajuste si algo no te sirve"]}, {"k": "mito", "items": [["Si la primera respuesta no sirve, hay que empezar de cero.", false, "Puedes pedir cambios en el mismo chat: más corto, más formal o con ejemplos."], ["Puedes pedirle que te explique algo como a un principiante.", true, "Es una de las mejores formas de usarla para aprender."]]}, {"k": "quiz", "q": "¿Cuál es la mejor forma de pedirle algo a una IA?", "o": ["Con palabras técnicas en inglés", "Con tus palabras, explicando qué necesitas", "Con la menor cantidad de palabras posible"], "a": 1}, {"k": "reto", "r": "Pídele a una IA que te explique un término de tu trabajo en tres líneas y luego pídele un ejemplo."}]$j$::jsonb, 'principal', 'ia', 2),
  (12, 2, $t$Revisa lo que dice la IA$t$, $j$[{"k": "escena", "h": "Dino es el editor de un periódico", "l": [["a", "Redacción de un periódico. Dino revisa todo antes de publicar."], ["t", "Reportero", "Tengo la nota lista. La escribió una IA en dos minutos."], ["d", "Dino, el editor", "Bien. ¿De dónde salen estas cifras?", "lupa"], ["t", "Reportero", "Las puso la IA. Suenan bien."], ["d", "Dino, el editor", "Sonar bien no es lo mismo que ser cierto. Las verificamos con la fuente original.", "alto"], ["t", "Reportero", "¿Y el nombre del cliente que aparece aquí?"], ["d", "Dino, el editor", "Fuera. Los datos personales no se pegan en una IA ni se publican sin permiso.", "guia"]], "m": "La IA da un buen primer borrador, no la última palabra. Verifica cifras, nombres y fechas, y no le compartas datos sensibles."}, {"k": "pares", "h": "Une qué revisar con cómo hacerlo", "p": [["Cifras", "Compáralas con la fuente"], ["Nombres y fechas", "Confírmalos en el original"], ["Enlaces", "Ábrelos y comprueba que existen"], ["Datos personales", "Quítalos antes de pegar"]]}, {"k": "quiz", "q": "La IA te da un dato que no aparece en ninguna fuente. ¿Qué haces?", "o": ["Lo usas igual", "No lo usas hasta confirmarlo", "Le pides que lo repita"], "a": 1}, {"k": "reto", "r": "Pídele a una IA un resumen de un documento tuyo y verifica tres datos contra el original."}]$j$::jsonb, 'principal', 'ia', 2),
  (13, 1, $t$Actualizaciones sin miedo$t$, $j$[{"k": "card", "d": "Una actualización es como el mantenimiento de un carro: corrige fallas, cierra huecos de seguridad y a veces trae mejoras. Posponerla para siempre deja la puerta abierta a problemas."}, {"k": "mito", "items": [["Las actualizaciones solo cambian colores y botones.", false, "Muchas corrigen fallas de seguridad que ya se conocen."], ["Conviene actualizar con batería y buena conexión.", true, "Así evitas que se interrumpa a la mitad."], ["Se pueden descargar actualizaciones de cualquier página que las ofrezca.", false, "Solo desde los ajustes del equipo o la tienda oficial."]]}, {"k": "completa", "s": "Las actualizaciones se instalan desde los ___ del equipo o la tienda oficial.", "o": ["ajustes", "anuncios", "correos"], "a": 0}, {"k": "orden", "o": ["Conecta el equipo a la corriente", "Abre Ajustes", "Busca Actualizaciones", "Instala y reinicia"]}, {"k": "reto", "r": "Revisa si tu teléfono tiene una actualización pendiente y programa su instalación para esta noche."}]$j$::jsonb, 'principal', 'tecno', 2),
  (14, 2, $t$¿Qué es un algoritmo?$t$, $j$[{"k": "escena", "h": "Dino cocina con una receta", "l": [["a", "Una cocina. Dino tiene una receta escrita paso a paso."], ["t", "Tú", "¿Qué es eso de «algoritmo» que escucho en todas partes?"], ["d", "Dino, el cocinero", "Es una receta: pasos en orden para llegar a un resultado.", "guia"], ["t", "Tú", "¿Y por qué las redes me muestran siempre lo mismo?"], ["d", "Dino, el cocinero", "Porque su receta dice: muéstrale más de lo que miró, comentó o guardó.", "lupa"], ["t", "Tú", "¿Entonces puedo cambiar lo que veo?"], ["d", "Dino, el cocinero", "Claro. Si cambias lo que miras y lo que marcas como «no me interesa», cambias los ingredientes.", "reto"]], "m": "Un algoritmo es una receta con pasos en orden. Las apps usan recetas así para decidir qué mostrarte según lo que haces."}, {"k": "pares", "h": "Une la cocina con el mundo digital", "p": [["Receta", "Algoritmo"], ["Ingredientes", "Datos"], ["Pasos", "Instrucciones"], ["El plato", "El resultado"]]}, {"k": "quiz", "q": "Tu red social te muestra muchos videos de cocina. ¿Por qué?", "o": ["Es casualidad", "Porque has mirado y guardado videos de cocina", "Porque todos ven lo mismo"], "a": 1}, {"k": "reto", "r": "En una red social que uses, marca «No me interesa» en tres publicaciones y observa cómo cambia tu inicio en unos días."}]$j$::jsonb, 'principal', 'tecno', 2),
  (15, 2, $t$Formularios que trabajan por ti$t$, $j$[{"k": "card", "d": "Un formulario en línea, como Google Forms o Microsoft Forms, junta las respuestas de muchas personas en una sola tabla, sin copiar y pegar. Sirve para pedidos, inscripciones o encuestas."}, {"k": "orden", "o": ["Crea el formulario", "Agrega las preguntas", "Comparte el enlace", "Revisa las respuestas en la hoja de cálculo"]}, {"k": "pares", "h": "Une cada tipo de pregunta con su uso", "p": [["Respuesta corta", "Nombre o correo"], ["Opción múltiple", "Elegir una talla"], ["Casillas", "Marcar varios días"], ["Fecha", "Día de entrega"]]}, {"k": "quiz", "q": "¿Dónde quedan las respuestas de un formulario?", "o": ["En el correo de cada persona", "En una tabla que se llena sola", "Hay que pedirlas una por una"], "a": 1}, {"k": "reto", "r": "Crea un formulario de tres preguntas para organizar algo real, como un almuerzo o una reunión, y envíaselo a dos personas."}]$j$::jsonb, 'principal', 'herr', 2)
on conflict (orden) do nothing;

-- ---------- 2. Perfil: tema principal, meta semanal y preferencias de la tienda ----------
alter table public.perfiles add column if not exists tema_principal text;
alter table public.perfiles add column if not exists meta_semanal  smallint not null default 5 check (meta_semanal between 1 and 7);
alter table public.perfiles add column if not exists meta_tienda   text;
alter table public.perfiles add column if not exists tour_tienda   boolean not null default false;

-- ---------- 3. Avance por tema ----------
create table if not exists public.progreso_tema (
  user_id        uuid not null references public.perfiles(id) on delete cascade,
  tema           text not null check (tema in ('ia','tecno','herr')),
  nivel_inicial  smallint not null default 0,
  siguiente_reto int references public.retos(orden),   -- null = tema completado
  ultimo_dia     date,
  primary key (user_id, tema)
);
alter table public.progreso_tema enable row level security;
revoke all on public.progreso_tema from anon, authenticated;
grant select on public.progreso_tema to authenticated;
drop policy if exists "cada uno ve su avance" on public.progreso_tema;
create policy "cada uno ve su avance" on public.progreso_tema for select to authenticated using ((select auth.uid()) = user_id);

-- Orden de un reto dentro de su tema
create or replace function private.clave(p_orden int) returns int language sql stable set search_path = '' as
$$ select mundo * 100 + pos from public.retos where orden = p_orden $$;
create or replace function private.primer_reto(p_tema text, p_nivel int) returns int language sql stable set search_path = '' as
$$ select orden from public.retos where tema = p_tema and tipo = 'principal' and activo and mundo >= p_nivel order by mundo, pos limit 1 $$;

-- Usuarios que ya tenían avance: se reparte por tema, saltando lo que ya completaron
insert into public.progreso_tema (user_id, tema, nivel_inicial, siguiente_reto)
select p.id, t.tema, p.nivel_inicial,
       (select r.orden from public.retos r
         where r.tema = t.tema and r.tipo = 'principal' and r.activo and r.mundo >= p.nivel_inicial
           and not exists (select 1 from public.intentos i where i.user_id = p.id and i.reto_orden = r.orden and not i.es_repaso)
         order by r.mundo, r.pos limit 1)
from public.perfiles p cross join (values ('ia'),('tecno'),('herr')) t(tema)
where p.nivel_inicial is not null
on conflict (user_id, tema) do nothing;
update public.perfiles set tema_principal = 'ia' where nivel_inicial is not null and tema_principal is null;

-- ---------- 4. Cofres: uno al final de cada submundo ----------
update public.cofres set activo = false where id between 1 and 6;
insert into public.cofres (id, despues_de, guia_codigo, mandarinas) values
  (11, 11,  null,      15),
  (12, 7,   'prompts', 0),
  (13, 12,  null,      30),
  (14, 102, 'estafas', 0),
  (15, 13,  null,      15),
  (16, 14,  null,      30),
  (17, 2,   'atajos',  0),
  (18, 6,   'excel',   0),
  (19, 15,  null,      30)
on conflict (id) do nothing;

-- ---------- 5. Funciones ----------
create or replace function private.configurar_inicio(p_tema text, p_nivel int, p_meta int, p_zona text)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  if p_tema not in ('ia','tecno','herr') then raise exception 'tema_invalido'; end if;
  if p_nivel not between 0 and 2 then raise exception 'nivel_invalido'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is not null then return r; end if;          -- ya configurado
  update public.perfiles set
    nivel_inicial = p_nivel, tema_principal = p_tema,
    meta_semanal  = greatest(1, least(7, coalesce(p_meta, 5))),
    zona_horaria  = case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_zona) then p_zona else zona_horaria end
  where id = uid returning * into r;
  insert into public.progreso_tema (user_id, tema, nivel_inicial, siguiente_reto)
  select uid, t, case when t = p_tema then p_nivel else 0 end,
         private.primer_reto(t, case when t = p_tema then p_nivel else 0 end)
  from unnest(array['ia','tecno','herr']) t
  on conflict (user_id, tema) do nothing;
  return r;
end $$;

-- Compatibilidad con la versión anterior de la app
create or replace function private.fijar_nivel(p_nivel int, p_zona text)
returns public.perfiles language sql security definer set search_path = '' as
$$ select * from private.configurar_inicio('ia', p_nivel, 5, p_zona) $$;

create or replace function private.completar_reto(p_reto int, p_puntos int, p_practico boolean)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); r public.perfiles; pt public.progreso_tema; d date; pts int;
  t text; tm text; nv smallint; k int; sig int; bono int := 0; nueva_racha int; sube boolean := true; usa_prot boolean := false;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  select tipo, tema, mundo into t, tm, nv from public.retos where orden = p_reto and activo;
  if t is null then raise exception 'reto_inexistente'; end if;
  d   := private.hoy(r);
  pts := least(greatest(coalesce(p_puntos,0),0), 60);

  if t = 'secreto' then                                          -- niveles secretos (si el equipo crea nuevos)
    if not exists (select 1 from public.desbloqueos where user_id = uid and reto_orden = p_reto) then raise exception 'reto_bloqueado'; end if;
    if exists (select 1 from public.intentos where user_id = uid and reto_orden = p_reto and not es_repaso) then
      insert into public.intentos (user_id, reto_orden, dia, puntos, practico, es_repaso) values (uid, p_reto, d, 0, coalesce(p_practico,false), true);
      return r;
    end if;
    update public.perfiles set mandarinas = mandarinas + pts, total_ganado = total_ganado + pts where id = uid returning * into r;
    insert into public.intentos (user_id, reto_orden, dia, puntos, practico) values (uid, p_reto, d, pts, coalesce(p_practico,false));
    return r;
  end if;

  select * into pt from public.progreso_tema where user_id = uid and tema = tm for update;
  if pt.user_id is null then raise exception 'falta_test'; end if;
  k := private.clave(p_reto);
  if pt.siguiente_reto is null or k < private.clave(pt.siguiente_reto) then   -- repaso
    insert into public.intentos (user_id, reto_orden, dia, puntos, practico, es_repaso) values (uid, p_reto, d, 0, coalesce(p_practico,false), true);
    return r;
  end if;
  if k > private.clave(pt.siguiente_reto) then raise exception 'reto_bloqueado'; end if;
  if pt.ultimo_dia = d then raise exception 'ya_completaste_hoy'; end if;

  -- Racha global: sube con el primer reto del día, en cualquier tema
  if r.ultimo_dia = d then nueva_racha := r.racha; sube := false;
  elsif r.ultimo_dia = d - 1 then nueva_racha := r.racha + 1;
  elsif r.ultimo_dia = d - 2 and r.protectores > 0 and r.racha > 0 then nueva_racha := r.racha + 1; usa_prot := true;
  else nueva_racha := 1; end if;

  select orden into sig from public.retos where tema = tm and tipo = 'principal' and activo and mundo * 100 + pos > k order by mundo, pos limit 1;
  if sig is null or (select mundo from public.retos where orden = sig) <> nv then bono := bono + 20; end if;   -- fin de submundo
  if sube and nueva_racha % 7 = 0 then bono := bono + 15; end if;

  update public.progreso_tema set siguiente_reto = sig, ultimo_dia = d where user_id = uid and tema = tm;
  update public.perfiles set
    racha = nueva_racha, ultimo_dia = d,
    mandarinas = mandarinas + pts + bono, total_ganado = total_ganado + pts + bono,
    protectores = protectores - case when usa_prot then 1 else 0 end
  where id = uid returning * into r;
  insert into public.intentos (user_id, reto_orden, dia, puntos, practico) values (uid, p_reto, d, pts + bono, coalesce(p_practico,false));
  return r;
end $$;

create or replace function private.abrir_cofre(p_cofre int)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles; c public.cofres; pt public.progreso_tema;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  select * into c from public.cofres where id = p_cofre and activo;
  if c.id is null then raise exception 'cofre_inexistente'; end if;
  select * into r from public.perfiles where id = uid for update;
  if r.nivel_inicial is null then raise exception 'falta_test'; end if;
  select p.* into pt from public.progreso_tema p join public.retos x on x.tema = p.tema
   where p.user_id = uid and x.orden = c.despues_de;
  if pt.user_id is null or (pt.siguiente_reto is not null and private.clave(c.despues_de) >= private.clave(pt.siguiente_reto)) then
    raise exception 'cofre_bloqueado'; end if;
  if exists (select 1 from public.cofres_abiertos where user_id = uid and cofre_id = p_cofre) then raise exception 'cofre_ya_abierto'; end if;
  insert into public.cofres_abiertos (user_id, cofre_id) values (uid, p_cofre);
  if c.guia_codigo is not null then
    insert into public.guias_usuario (user_id, codigo, origen) values (uid, c.guia_codigo, 'cofre') on conflict do nothing;
  end if;
  if c.mandarinas > 0 then
    update public.perfiles set mandarinas = mandarinas + c.mandarinas, total_ganado = total_ganado + c.mandarinas where id = uid returning * into r;
  end if;
  return r;
end $$;

create or replace function private.guardar_pref(p_meta text, p_tour boolean)
returns public.perfiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.perfiles;
begin
  if uid is null then raise exception 'sin_sesion'; end if;
  update public.perfiles set
    meta_tienda = case when p_meta = '' then null else coalesce(left(p_meta, 60), meta_tienda) end,
    tour_tienda = coalesce(p_tour, tour_tienda)
  where id = uid returning * into r;
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
    delete from public.intentos           where user_id = uid;
    delete from public.canjes             where user_id = uid;
    delete from public.desbloqueos        where user_id = uid;
    delete from public.guias_usuario      where user_id = uid;
    delete from public.cofres_abiertos    where user_id = uid;
    delete from public.progreso_tema      where user_id = uid;
    delete from public.solicitudes_premio where user_id = uid;
    update public.perfiles set nivel_inicial = null, tema_principal = null, siguiente_reto = 1, mandarinas = 0, total_ganado = 0,
      protectores = 0, racha = 0, ultimo_dia = null, desfase_dias = 0, meta_tienda = null, tour_tienda = false
    where id = uid returning * into r;
  else raise exception 'accion_invalida'; end if;
  return r;
end $$;

revoke all on function private.clave(int), private.primer_reto(text,int), private.configurar_inicio(text,int,int,text),
  private.fijar_nivel(int,text), private.completar_reto(int,int,boolean), private.abrir_cofre(int),
  private.guardar_pref(text,boolean), private.tester_accion(text) from public, anon;
grant execute on function private.clave(int), private.primer_reto(text,int), private.configurar_inicio(text,int,int,text),
  private.fijar_nivel(int,text), private.completar_reto(int,int,boolean), private.abrir_cofre(int),
  private.guardar_pref(text,boolean), private.tester_accion(text) to authenticated;

create or replace function public.configurar_inicio(p_tema text, p_nivel int, p_meta int, p_zona text)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.configurar_inicio(p_tema, p_nivel, p_meta, p_zona) $$;
create or replace function public.guardar_pref(p_meta text, p_tour boolean)
returns public.perfiles language sql security invoker set search_path = '' as
$$ select * from private.guardar_pref(p_meta, p_tour) $$;
revoke all on function public.configurar_inicio(text,int,int,text), public.guardar_pref(text,boolean) from public, anon;
grant execute on function public.configurar_inicio(text,int,int,text), public.guardar_pref(text,boolean) to authenticated;

notify pgrst, 'reload schema';

select 'Parche v1.5 aplicado' as resultado,
       (select count(*) from public.retos where tipo = 'principal' and tema is not null) as retos_con_tema,
       (select count(*) from public.cofres where activo) as cofres_activos;
