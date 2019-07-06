-- 1 up
create type bot_state as enum (
  'new', 'waiting', 'unacceptable', 'acceptable', 'correct', 'obsolete');
create table if not exists bot_sources (
  id      serial primary key,
  api_url text not null,
  project text not null,
  package text not null,
  srcmd5  text not null
);
create table if not exists bot_users (
  id        serial primary key,
  login     text not null,
  email     text,
  fullname  text,
  roles     text[] not null default '{user}',
  comment   text
);
create table if not exists bot_products (
  id   serial primary key,
  name text not null constraint name_unique unique
);
create index on bot_products(name);
create table if not exists bot_packages (
  id              serial primary key,
  name            text not null,
  checkout_dir    text not null,
  checksum        text,
  source          int not null references bot_sources(id),
  requesting_user int not null references bot_users(id),
  external_link   text,
  created         timestamp with time zone not null default now(),
  reviewed        timestamp with time zone,
  priority        int not null check(priority >= 1 and priority <= 10),
  reviewing_user  int references bot_users(id),
  state           bot_state not null,
  obsolete        boolean not null default false,
  result          text,
  imported        timestamp with time zone,
  unpacked        timestamp with time zone,
  indexed         timestamp with time zone
);
create index on bot_packages(requesting_user);
create index on bot_packages(reviewing_user);
create index on bot_packages(source);
create index on bot_packages(reviewed);
create index on bot_packages(external_link);
create table if not exists bot_package_products (
  package int not null references bot_packages(id),
  product int not null references bot_products(id)
);
create unique index on bot_package_products(package, product);
create index on bot_package_products(product);
create table if not exists bot_requests (
  id            serial primary key,
  external_link text,
  package       int references bot_packages(id)
);
create index on bot_requests (package);
create table if not exists bot_reports (
  id              serial primary key,
  package         int not null references bot_packages(id),
  specfile_report text not null,
  ldig_report     text,
  rolemodel       boolean
);
create index on bot_reports (package);
create table report_checksums (
  id        bigserial primary key,
  checksum  text not null,
  shortname text not null constraint shortname_unique unique
);
create unique index on report_checksums(checksum);
create table if not exists emails (
  id      bigserial primary key,
  package int not null references bot_packages(id),
  name    text,
  email   text not null,
  hits    int not null default 0
);
create unique index on emails (package, md5(email));
create index on emails (package);
create table if not exists urls (
  id      serial primary key,
  package int not null references bot_packages(id),
  url     text not null,
  hits    int not null default 0
);
create unique index on urls (package, md5(url));
create index on urls (package);
create table if not exists matched_files (
  id       bigserial primary key,
  package  int not null references bot_packages(id),
  filename text not null,
  mimetype text not null
);
create index on matched_files (package);
create table licenses (
  id           serial primary key,
  name         text not null,
  url          text,
  description  text,
  created      timestamp with time zone not null default now(),
  risk         int not null default 5,
  eula         boolean not null default false,
  nonfree      boolean not null default false
);
create unique index on licenses (name);
create table license_patterns (
  id           serial primary key,
  pattern      text not null,
  token_hexsum char(32) not null,
  license      int not null references licenses (id),
  created      timestamp with time zone not null default now(),
  packname     text not null default '',
  patent       boolean not null default false,
  trademark    boolean not null default false,
  opinion      boolean not null default false
);
create index on license_patterns (license);
create index on license_patterns (packname);
create unique index on license_patterns (token_hexsum);
create table pattern_matches (
  id           bigserial primary key,
  package      int not null references bot_packages(id) on delete cascade,
  file         bigint not null references matched_files(id)
               on delete cascade,
  pattern      int not null references license_patterns(id) on delete cascade,
  sline        int not null,
  eline        int not null,
  created      timestamp with time zone not null default now(),
  ignored      boolean not null default false
);
create index on pattern_matches (file);
create index on pattern_matches (package);
create index on pattern_matches (pattern);
create table ignored_lines (
  id           bigserial primary key,
  packname     text not null,
  hash         text not null,
  created      timestamp with time zone not null default now()
);
create index on ignored_lines(packname);
create unique index on ignored_lines(packname,hash);

-- 1 down
drop table if exists ignored_lines cascade;
drop table if exists pattern_matches;
drop table if exists license_patterns;
drop table if exists licenes;
drop table if exists bot_requests;
drop table if exists bot_reports;
drop table if exists bot_packages;
drop table if exists bot_sources;
drop table if exists bot_users;
drop table if exists report_checksums;
drop table if exists emails;
drop table if exists urls;
drop table if exists matched_files;
drop type if exists bot_state;

-- 2 up
alter table license_patterns add column license_string text;

-- 2 down
alter table license_patterns drop column license_string;

-- 3 up
create table snippets (
  id        bigserial primary key,
  hash      text not null,
  created   timestamp with time zone not null default now()
)

-- 3 down
drop table if exists snippets;
