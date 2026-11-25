-- =====================================================================
-- Aprende con Dino · MandarinaTec · Parche v1.1 · 25/11/2026
-- Para el nuevo inicio: jugar sin registro y guardar después con correo y contraseña.
-- Pegar en Supabase > SQL Editor > New query > Run. Se puede ejecutar más de una vez.
-- =====================================================================

-- 1. Cuando un usuario anónimo guarda su cuenta, copiar su correo al perfil
create or replace function private.sincronizar_correo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.perfiles
     set email   = coalesce(new.email, ''),
         usuario = case when usuario in ('', 'usuario') or usuario = split_part(coalesce(old.email,''),'@',1)
                        then split_part(coalesce(new.email,'usuario'),'@',1) else usuario end
   where id = new.id;
  return new;
end $$;
revoke all on function private.sincronizar_correo() from public, anon, authenticated;

drop trigger if exists al_cambiar_correo on auth.users;
create trigger al_cambiar_correo after update of email on auth.users
  for each row when (new.email is distinct from old.email)
  execute function private.sincronizar_correo();

-- 2. Usuarios anónimos sin nombre: "usuario" -> vacío (la app saluda sin nombre)
create or replace function private.crear_perfil()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, email, usuario)
  values (new.id, coalesce(new.email,''), coalesce(split_part(new.email,'@',1),''))
  on conflict (id) do nothing;
  return new;
end $$;
update public.perfiles set usuario = '' where usuario = 'usuario' and email = '';

-- 2b. Rellenar perfiles de invitados que ya guardaron su cuenta antes de este parche
update public.perfiles p
   set email = u.email, usuario = split_part(u.email,'@',1)
  from auth.users u
 where u.id = p.id and p.email = '' and u.email is not null;

-- 3. Limpieza: borra invitados que nunca guardaron su cuenta y llevan 30 días sin entrar.
--    No se ejecuta sola: córrela a mano cuando quieras (o prográmala con pg_cron).
--    delete from auth.users where is_anonymous and coalesce(last_sign_in_at, created_at) < now() - interval '30 days';

select 'Parche v1.1 aplicado' as resultado;
