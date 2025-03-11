-- 17 up
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE TYPE bot_state AS ENUM (
  'new',
  'waiting',
  'unacceptable',
  'acceptable',
  'correct',
  'obsolete'
);
CREATE TABLE bot_sources (
  id serial PRIMARY KEY,
  api_url text NOT NULL,
  project text NOT NULL,
  package text NOT NULL,
  srcmd5 text NOT NULL
);
CREATE TABLE bot_users (
  id serial PRIMARY KEY,
  login text NOT NULL,
  comment text,
  email text,
  fullname text,
  roles text[] DEFAULT '{user}'::text[] NOT NULL
);
CREATE TABLE bot_packages (
  id serial PRIMARY KEY,
  name text NOT NULL,
  checkout_dir text NOT NULL,
  source int REFERENCES bot_sources(id) NOT NULL,
  requesting_user int REFERENCES bot_users(id) NOT NULL,
  external_link text,
  created timestamp with time zone DEFAULT now() NOT NULL,
  priority int NOT NULL,
  reviewing_user int REFERENCES bot_users(id),
  state bot_state NOT NULL,
  result text,
  unpacked timestamp with time zone,
  indexed timestamp with time zone,
  reviewed timestamp with time zone,
  obsolete boolean DEFAULT false NOT NULL,
  checksum text,
  imported timestamp with time zone,
  patent boolean DEFAULT false NOT NULL,
  trademark boolean DEFAULT false NOT NULL,
  export_restricted boolean DEFAULT false NOT NULL,
  CONSTRAINT bot_packages_priority_check CHECK (((priority >= 1) AND (priority <= 10)))
);
CREATE INDEX ON bot_packages(requesting_user);
CREATE INDEX ON bot_packages(reviewing_user);
CREATE INDEX ON bot_packages(source);
CREATE INDEX ON bot_packages(reviewed);
CREATE INDEX ON bot_packages(external_link);
CREATE TABLE emails (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  email text NOT NULL,
  hits int DEFAULT 0 NOT NULL,
  name text
);
CREATE UNIQUE INDEX ON emails(package, md5(email));
CREATE INDEX ON emails(package);
CREATE TABLE urls (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  url text NOT NULL,
  hits int DEFAULT 0 NOT NULL
);
CREATE UNIQUE INDEX ON urls(package, md5(url));
CREATE TABLE bot_products (
  id serial PRIMARY KEY,
  name text NOT NULL CONSTRAINT name_unique UNIQUE
);
CREATE INDEX ON bot_products(name);
CREATE TABLE bot_package_products (
  package int REFERENCES bot_packages(id) NOT NULL,
  product int REFERENCES bot_products(id) ON DELETE CASCADE NOT NULL
);
CREATE UNIQUE INDEX ON bot_package_products(package, product);
CREATE INDEX ON bot_package_products(product);
CREATE TABLE bot_reports (
  id serial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  ldig_report text,
  specfile_report text NOT NULL,
  rolemodel boolean
);
CREATE INDEX ON bot_reports(package);
CREATE TABLE bot_requests (
  id serial PRIMARY KEY,
  external_link text,
  package int REFERENCES bot_packages(id)
);
CREATE INDEX ON bot_requests(package);
CREATE TABLE matched_files (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  filename text NOT NULL,
  mimetype text NOT NULL
);
CREATE INDEX ON matched_files(package);
CREATE TABLE license_patterns (
  id serial PRIMARY KEY,
  pattern text NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  packname text DEFAULT ''::text NOT NULL,
  patent boolean DEFAULT false NOT NULL,
  trademark boolean DEFAULT false NOT NULL,
  token_hexsum character(32) NOT NULL,
  license text DEFAULT ''::text NOT NULL,
  risk int DEFAULT 5 NOT NULL,
  unique_id uuid DEFAULT gen_random_uuid() NOT NULL CONSTRAINT unique_id_unique UNIQUE,
  spdx text DEFAULT ''::text NOT NULL,
  export_restricted boolean DEFAULT false NOT NULL
);
CREATE INDEX ON license_patterns(packname);
CREATE UNIQUE INDEX ON license_patterns(token_hexsum);
CREATE INDEX ON license_patterns(license);
CREATE INDEX ON license_patterns(unique_id);
CREATE INDEX ON license_patterns(spdx);
CREATE TABLE snippets (
  id bigserial PRIMARY KEY,
  hash text NOT NULL,
  text text NOT NULL,
  license boolean DEFAULT false NOT NULL,
  classified boolean DEFAULT false NOT NULL,
  approved boolean DEFAULT false NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  confidence int DEFAULT 0 NOT NULL,
  likelyness real DEFAULT 0 NOT NULL,
  like_pattern int REFERENCES license_patterns(id) ON DELETE SET NULL
);
CREATE INDEX ON snippets(classified);
CREATE UNIQUE INDEX ON snippets(hash);
CREATE INDEX ON snippets(approved);
CREATE TABLE file_snippets (
  id bigserial PRIMARY KEY,
  created timestamp with time zone DEFAULT now() NOT NULL,
  package int REFERENCES bot_packages(id) ON DELETE CASCADE NOT NULL,
  file bigint REFERENCES matched_files(id) ON DELETE CASCADE NOT NULL,
  snippet int REFERENCES snippets(id) ON DELETE CASCADE NOT NULL,
  sline int NOT NULL,
  eline int NOT NULL
);
CREATE INDEX ON file_snippets(snippet);
CREATE TABLE ignored_files (
  id serial PRIMARY KEY,
  glob text NOT NULL,
  owner int REFERENCES bot_users(id) NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE ignored_lines (
  id bigserial PRIMARY KEY,
  packname text NOT NULL,
  hash text NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX ON ignored_lines(packname);
CREATE UNIQUE INDEX ON ignored_lines(packname, hash);
CREATE TABLE pattern_matches (
  id bigserial PRIMARY KEY,
  file bigint REFERENCES matched_files(id) ON DELETE CASCADE NOT NULL,
  pattern int REFERENCES license_patterns(id) ON DELETE CASCADE NOT NULL,
  sline int NOT NULL,
  eline int NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  ignored boolean DEFAULT false NOT NULL,
  package int REFERENCES bot_packages(id) ON DELETE CASCADE NOT NULL
);
CREATE INDEX ON pattern_matches(file);
CREATE INDEX ON pattern_matches(package);
CREATE INDEX ON pattern_matches(pattern);
CREATE TABLE report_checksums (
  id bigserial PRIMARY KEY,
  checksum text NOT NULL,
  shortname text NOT NULL CONSTRAINT shortname_unique UNIQUE
);
CREATE UNIQUE INDEX ON report_checksums(checksum);

-- 17 down
DROP TABLE IF EXISTS report_checksums;
DROP TABLE IF EXISTS pattern_matches;
DROP TABLE IF EXISTS ignored_lines;
DROP TABLE IF EXISTS ignored_files;
DROP TABLE IF EXISTS file_snippets;
DROP TABLE IF EXISTS snippets;
DROP TABLE IF EXISTS license_patterns;
DROP TABLE IF EXISTS bot_requests;
DROP TABLE IF EXISTS matched_files;
DROP TABLE IF EXISTS bot_reports;
DROP TABLE IF EXISTS bot_package_products;
DROP TABLE IF EXISTS bot_products;
DROP TABLE IF EXISTS urls;
DROP TABLE IF EXISTS emails;
DROP TABLE IF EXISTS bot_packages;
DROP TABLE IF EXISTS bot_users;
DROP TABLE IF EXISTS bot_sources;
DROP TYPE IF EXISTS bot_state;

-- 18 up
CREATE TABLE proposed_changes (
  id serial PRIMARY KEY,
  action text NOT NULL,
  token_hexsum text NOT NULL,
  data jsonb NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  owner int REFERENCES bot_users(id) NOT NULL
);
CREATE UNIQUE INDEX ON proposed_changes(token_hexsum);

--18 down
DROP TABLE IF EXISTS proposed_changes;

-- 19 up
ALTER TABLE bot_packages ADD COLUMN unresolved_matches int DEFAULT 0 NOT NULL;

-- 20 up
CREATE UNIQUE INDEX ON ignored_files(glob);
ALTER TABLE license_patterns ADD COLUMN owner int REFERENCES bot_users(id);
ALTER TABLE license_patterns ADD COLUMN contributor int REFERENCES bot_users(id);

-- 21 up
ALTER TABLE ignored_lines ADD COLUMN owner int REFERENCES bot_users(id);
ALTER TABLE ignored_lines ADD COLUMN contributor int REFERENCES bot_users(id);

-- 22 up
ALTER TABLE pattern_matches ADD COLUMN ignored_line int REFERENCES ignored_lines(id) ON DELETE SET NULL;
CREATE INDEX ON pattern_matches(ignored_line);

-- 23 up
ALTER TYPE bot_state RENAME VALUE 'correct' TO 'acceptable_by_lawyer';
ALTER TABLE bot_packages ADD COLUMN notice text;

-- 24 up
ALTER TABLE bot_packages ADD COLUMN embargoed boolean DEFAULT false NOT NULL;
CREATE INDEX ON bot_packages(embargoed);
ALTER TABLE snippets ADD COLUMN package int REFERENCES bot_packages(id) ON DELETE SET NULL;

-- 25 up
ALTER TABLE bot_sources ADD COLUMN type text DEFAULT 'obs' NOT NULL;

-- 26 up
CREATE UNIQUE INDEX ON bot_requests(external_link, package);

--27 up
ALTER TABLE bot_packages ADD COLUMN cleaned timestamp with time zone;

--28 up
CREATE INDEX ON bot_packages(cleaned);
