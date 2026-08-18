alter table public.profiles
  add column if not exists gender text not null default 'unspecified',
  add column if not exists bio text not null default '';

alter table public.profiles
  drop constraint if exists profiles_display_name_length,
  add constraint profiles_display_name_length check (char_length(display_name) <= 30),
  add constraint profiles_gender_value check (gender in ('male', 'female', 'unspecified')),
  add constraint profiles_bio_length check (char_length(bio) <= 130);
