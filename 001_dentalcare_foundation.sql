-- DentalCare OS: multi-clinic foundation
-- Apply once in Supabase SQL Editor or with Supabase CLI.
-- Never expose service_role keys in browser code.

create extension if not exists pgcrypto;

create type public.org_role as enum ('owner', 'org_admin');
create type public.clinic_role as enum ('clinic_admin', 'doctor', 'receptionist');
create type public.patient_status as enum ('active', 'inactive', 'archived');
create type public.appointment_status as enum ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show');
create type public.followup_status as enum ('pending', 'completed', 'cancelled');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.org_role not null default 'org_admin',
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table public.clinics (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 120),
  timezone text not null default 'Asia/Karachi',
  phone text,
  email text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.clinic_members (
  clinic_id uuid not null,
  organization_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.clinic_role not null,
  created_at timestamptz not null default now(),
  primary key (clinic_id, user_id),
  foreign key (clinic_id, organization_id)
    references public.clinics(id, organization_id) on delete cascade
);

create table public.patients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  clinic_id uuid not null,
  patient_number bigint generated always as identity,
  first_name text not null check (char_length(trim(first_name)) between 1 and 80),
  last_name text,
  phone text,
  email text,
  date_of_birth date,
  sex text check (sex is null or sex in ('female','male','other','prefer_not_to_say')),
  notes text,
  status public.patient_status not null default 'active',
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (clinic_id, organization_id)
    references public.clinics(id, organization_id) on delete restrict,
  unique (clinic_id, patient_number),
  unique (id, clinic_id, organization_id)
);

create table public.procedures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  clinic_id uuid not null,
  patient_id uuid not null,
  doctor_id uuid references auth.users(id) on delete set null,
  procedure_name text not null check (char_length(trim(procedure_name)) between 2 and 160),
  tooth_number text,
  description text,
  performed_at timestamptz not null default now(),
  fee numeric(12,2) check (fee is null or fee >= 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (clinic_id, organization_id)
    references public.clinics(id, organization_id) on delete restrict,
  foreign key (patient_id, clinic_id, organization_id)
    references public.patients(id, clinic_id, organization_id) on delete restrict
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  clinic_id uuid not null,
  patient_id uuid not null,
  doctor_id uuid references auth.users(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.appointment_status not null default 'scheduled',
  reason text,
  internal_notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  foreign key (clinic_id, organization_id)
    references public.clinics(id, organization_id) on delete restrict,
  foreign key (patient_id, clinic_id, organization_id)
    references public.patients(id, clinic_id, organization_id) on delete restrict
);

create table public.followups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  clinic_id uuid not null,
  patient_id uuid not null,
  procedure_id uuid references public.procedures(id) on delete set null,
  assigned_to uuid references auth.users(id) on delete set null,
  due_at timestamptz not null,
  status public.followup_status not null default 'pending',
  note text,
  completed_at timestamptz,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (clinic_id, organization_id)
    references public.clinics(id, organization_id) on delete restrict,
  foreign key (patient_id, clinic_id, organization_id)
    references public.patients(id, clinic_id, organization_id) on delete restrict
);

-- Queue is written by trusted server-side functions, not directly by browsers.
create table public.notification_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  clinic_id uuid not null,
  followup_id uuid references public.followups(id) on delete cascade,
  channel text not null check (channel in ('email','whatsapp')),
  recipient text not null,
  payload jsonb not null default '{}'::jsonb,
  scheduled_for timestamptz not null,
  sent_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  foreign key (clinic_id, organization_id)
    references public.clinics(id, organization_id) on delete cascade
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  clinic_id uuid references public.clinics(id) on delete set null,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  created_at timestamptz not null default now()
);

create index patients_clinic_name_idx on public.patients (clinic_id, last_name, first_name) where deleted_at is null;
create index appointments_clinic_starts_idx on public.appointments (clinic_id, starts_at);
create index followups_due_idx on public.followups (clinic_id, due_at) where status = 'pending';
create index notification_jobs_due_idx on public.notification_jobs (scheduled_for) where sent_at is null;

-- Authorization helpers are SECURITY DEFINER to avoid RLS recursion.
create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id = p_org_id and m.user_id = (select auth.uid())
  );
$$;

create or replace function public.has_org_role(p_org_id uuid, p_roles public.org_role[])
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = (select auth.uid())
      and m.role = any(p_roles)
  );
$$;

create or replace function public.has_clinic_role(p_clinic_id uuid, p_roles public.clinic_role[] default null)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.clinic_members cm
    where cm.clinic_id = p_clinic_id
      and cm.user_id = (select auth.uid())
      and (p_roles is null or cm.role = any(p_roles))
  );
$$;

create or replace function public.can_access_clinic(p_clinic_id uuid, p_org_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select public.is_org_member(p_org_id)
     and exists (
       select 1 from public.clinics c
       where c.id = p_clinic_id and c.organization_id = p_org_id
     )
     and (
       public.has_org_role(p_org_id, array['owner','org_admin']::public.org_role[])
       or public.has_clinic_role(p_clinic_id)
     );
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_updated_at before update on public.organizations
for each row execute function public.set_updated_at();
create trigger clinics_updated_at before update on public.clinics
for each row execute function public.set_updated_at();
create trigger patients_updated_at before update on public.patients
for each row execute function public.set_updated_at();
create trigger appointments_updated_at before update on public.appointments
for each row execute function public.set_updated_at();
create trigger followups_updated_at before update on public.followups
for each row execute function public.set_updated_at();

-- RLS on every tenant-bearing table.
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.clinics enable row level security;
alter table public.clinic_members enable row level security;
alter table public.patients enable row level security;
alter table public.procedures enable row level security;
alter table public.appointments enable row level security;
alter table public.followups enable row level security;
alter table public.notification_jobs enable row level security;
alter table public.audit_logs enable row level security;

create policy "org members read organization"
on public.organizations for select
using (public.is_org_member(id));

create policy "authenticated users create organization"
on public.organizations for insert to authenticated
with check (created_by = (select auth.uid()));

create policy "org owners update organization"
on public.organizations for update to authenticated
using (public.has_org_role(id, array['owner']::public.org_role[]))
with check (public.has_org_role(id, array['owner']::public.org_role[]));

create policy "members read own org memberships"
on public.organization_members for select
using (user_id = (select auth.uid()) or public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[]));
-- Membership writes are deliberately unavailable to browser sessions. Use a
-- trusted Edge Function with service-role credentials for invitations/role changes.

create policy "org members read clinics they can access"
on public.clinics for select
using (public.can_access_clinic(id, organization_id));

create policy "org admins create clinics"
on public.clinics for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[]));

create policy "org admins update clinics"
on public.clinics for update to authenticated
using (public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[]))
with check (public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[]));

create policy "clinic members read clinic memberships"
on public.clinic_members for select
using (
  user_id = (select auth.uid())
  or public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[])
  or public.has_clinic_role(clinic_id, array['clinic_admin']::public.clinic_role[])
);
-- Membership writes are deliberately unavailable to browser sessions. Use a
-- trusted Edge Function with service-role credentials for invitations/role changes.

create policy "clinic staff read patients"
on public.patients for select
using (deleted_at is null and public.can_access_clinic(clinic_id, organization_id));

create policy "clinic staff create patients"
on public.patients for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.can_access_clinic(clinic_id, organization_id)
);

create policy "clinic staff update patients"
on public.patients for update to authenticated
using (public.can_access_clinic(clinic_id, organization_id))
with check (public.can_access_clinic(clinic_id, organization_id));

create policy "clinic staff read procedures"
on public.procedures for select
using (public.can_access_clinic(clinic_id, organization_id));

create policy "doctors and clinic admins create procedures"
on public.procedures for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.can_access_clinic(clinic_id, organization_id)
  and (
    public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[])
    or public.has_clinic_role(clinic_id, array['doctor','clinic_admin']::public.clinic_role[])
  )
);

create policy "doctors and clinic admins update procedures"
on public.procedures for update to authenticated
using (
  public.can_access_clinic(clinic_id, organization_id)
  and (
    public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[])
    or public.has_clinic_role(clinic_id, array['doctor','clinic_admin']::public.clinic_role[])
  )
)
with check (public.can_access_clinic(clinic_id, organization_id));

create policy "clinic staff read appointments"
on public.appointments for select
using (public.can_access_clinic(clinic_id, organization_id));

create policy "clinic staff create appointments"
on public.appointments for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.can_access_clinic(clinic_id, organization_id)
);

create policy "clinic staff update appointments"
on public.appointments for update to authenticated
using (public.can_access_clinic(clinic_id, organization_id))
with check (public.can_access_clinic(clinic_id, organization_id));

create policy "clinic staff read followups"
on public.followups for select
using (public.can_access_clinic(clinic_id, organization_id));

create policy "clinic staff create followups"
on public.followups for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.can_access_clinic(clinic_id, organization_id)
);

create policy "clinic staff update followups"
on public.followups for update to authenticated
using (public.can_access_clinic(clinic_id, organization_id))
with check (public.can_access_clinic(clinic_id, organization_id));

-- Browser users can read their clinic's notification history, but only trusted
-- server-side code using the service role may insert/update queue jobs.
create policy "clinic staff read notification jobs"
on public.notification_jobs for select
using (public.can_access_clinic(clinic_id, organization_id));

create policy "org admins read audit logs"
on public.audit_logs for select
using (
  public.has_org_role(organization_id, array['owner','org_admin']::public.org_role[])
  or (clinic_id is not null and public.has_clinic_role(clinic_id, array['clinic_admin']::public.clinic_role[]))
);

-- Do not grant anon access. Authenticated table access is constrained by RLS.
grant usage on schema public to authenticated;
grant select, insert, update on public.organizations to authenticated;
grant select, insert, update on public.organization_members to authenticated;
grant select, insert, update on public.clinics to authenticated;
grant select, insert, update on public.clinic_members to authenticated;
grant select, insert, update on public.patients to authenticated;
grant select, insert, update on public.procedures to authenticated;
grant select, insert, update on public.appointments to authenticated;
grant select, insert, update on public.followups to authenticated;
grant select on public.notification_jobs to authenticated;
grant select on public.audit_logs to authenticated;

-- Important bootstrap note:
-- Organization creation + owner membership must be performed atomically by a
-- trusted RPC/Edge Function. Do not allow users to self-assign owner in a
-- browser insert. The next implementation step adds that secure RPC.
