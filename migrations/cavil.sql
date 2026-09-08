-- 67 up
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA public;

CREATE TYPE bot_state AS ENUM (
  'new',
  'waiting',
  'unacceptable',
  'acceptable',
  'acceptable_by_lawyer',
  'obsolete'
);

CREATE TABLE bot_sources (
  id serial PRIMARY KEY,
  api_url text NOT NULL,
  project text NOT NULL,
  package text NOT NULL,
  srcmd5 text NOT NULL,
  type text DEFAULT 'obs'::text NOT NULL
);

CREATE TABLE bot_users (
  id serial PRIMARY KEY,
  login text NOT NULL,
  comment text,
  email text,
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
  unresolved_matches int DEFAULT 0 NOT NULL,
  notice text,
  embargoed boolean DEFAULT false NOT NULL,
  cleaned timestamp with time zone,
  unpacked_files bigint,
  unpacked_size bigint,
  ai_assisted boolean DEFAULT false NOT NULL,
  cla boolean DEFAULT false NOT NULL,
  eula boolean DEFAULT false NOT NULL,
  diff_report text,
  processing_job int,
  index_stage text,
  reindex_requested timestamp with time zone,
  reindex_priority int,
  sbom_version int DEFAULT 0 NOT NULL,
  CONSTRAINT bot_packages_priority_check CHECK (((priority >= 1) AND (priority <= 10)))
);
CREATE INDEX ON bot_packages(requesting_user);
CREATE INDEX ON bot_packages(reviewing_user);
CREATE INDEX ON bot_packages(source);
CREATE INDEX ON bot_packages(reviewed);
CREATE INDEX ON bot_packages(external_link);
CREATE INDEX ON bot_packages(embargoed);
CREATE INDEX ON bot_packages(cleaned);
CREATE INDEX ON bot_packages(name);
CREATE INDEX ON bot_packages(obsolete);
CREATE INDEX ON bot_packages(ai_assisted);
CREATE INDEX bot_packages_open_reviews_idx ON bot_packages (priority DESC, external_link, unresolved_matches, name)
  WHERE state = 'new' AND obsolete = false;
CREATE INDEX bot_packages_name_trgm_idx ON bot_packages USING gin (name gin_trgm_ops);
CREATE INDEX bot_packages_imported_idx ON bot_packages (imported);
CREATE INDEX bot_packages_unsettled_idx ON bot_packages (id)
  WHERE processing_job IS NOT NULL OR index_stage IS NOT NULL OR reindex_requested IS NOT NULL;

CREATE TABLE emails (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  email text NOT NULL,
  hits int DEFAULT 0 NOT NULL,
  name text,
  generation int DEFAULT 0 NOT NULL
);
CREATE UNIQUE INDEX emails_package_md5_generation_idx ON emails (package, md5(email), generation);
CREATE INDEX ON emails(package);
CREATE INDEX emails_building_idx ON emails (package) WHERE generation <> 0;

CREATE TABLE urls (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  url text NOT NULL,
  hits int DEFAULT 0 NOT NULL,
  generation int DEFAULT 0 NOT NULL
);
CREATE UNIQUE INDEX urls_package_md5_generation_idx ON urls (package, md5(url), generation);
CREATE INDEX urls_building_idx ON urls (package) WHERE generation <> 0;

CREATE TABLE bot_products (
  id serial PRIMARY KEY,
  name text NOT NULL CONSTRAINT name_unique UNIQUE,
  updated timestamp with time zone DEFAULT now() NOT NULL,
  product text
);
CREATE INDEX ON bot_products(name);
CREATE INDEX ON bot_products(updated);
CREATE INDEX ON bot_products(product);

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
  rolemodel boolean,
  annotations text
);
CREATE INDEX ON bot_reports(package);

CREATE TABLE bot_requests (
  id serial PRIMARY KEY,
  external_link text,
  package int REFERENCES bot_packages(id)
);
CREATE INDEX ON bot_requests(package);
CREATE UNIQUE INDEX ON bot_requests(external_link, package);

CREATE TABLE matched_files (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  filename text NOT NULL,
  mimetype text NOT NULL,
  generation int DEFAULT 0 NOT NULL
);
CREATE INDEX ON matched_files(package);
CREATE INDEX matched_files_building_idx ON matched_files (package) WHERE generation <> 0;

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
  export_restricted boolean DEFAULT false NOT NULL,
  owner int REFERENCES bot_users(id),
  contributor int REFERENCES bot_users(id),
  cla boolean DEFAULT false NOT NULL,
  eula boolean DEFAULT false NOT NULL,
  catch_all boolean DEFAULT false NOT NULL,
  full_license_text boolean DEFAULT false NOT NULL
);
CREATE INDEX ON license_patterns(packname);
CREATE UNIQUE INDEX ON license_patterns(token_hexsum);
CREATE INDEX ON license_patterns(license);
CREATE INDEX ON license_patterns(unique_id);
CREATE INDEX ON license_patterns(spdx);
CREATE INDEX license_patterns_created_idx ON license_patterns (created);
CREATE UNIQUE INDEX license_patterns_full_text_idx ON license_patterns (license) WHERE full_license_text;

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
  like_pattern int REFERENCES license_patterns(id) ON DELETE SET NULL,
  package int REFERENCES bot_packages(id) ON DELETE SET NULL,
  second_match real DEFAULT 0 NOT NULL,
  score_version int DEFAULT 0 NOT NULL
);
CREATE INDEX ON snippets(classified);
CREATE UNIQUE INDEX ON snippets(hash);
CREATE INDEX ON snippets(approved);
CREATE INDEX snippets_fold_idx ON snippets (score_version, likelyness) WHERE classified AND license;
CREATE INDEX snippets_text_fts_idx ON snippets USING gin (to_tsvector('english', text));

CREATE TABLE file_snippets (
  id bigserial PRIMARY KEY,
  created timestamp with time zone DEFAULT now() NOT NULL,
  package int REFERENCES bot_packages(id) ON DELETE CASCADE NOT NULL,
  file bigint REFERENCES matched_files(id) ON DELETE CASCADE NOT NULL,
  snippet int REFERENCES snippets(id) ON DELETE CASCADE NOT NULL,
  sline int NOT NULL,
  eline int NOT NULL,
  resolution text,
  generation int DEFAULT 0 NOT NULL
);
CREATE INDEX ON file_snippets(snippet);
CREATE INDEX ON file_snippets(file);
CREATE INDEX file_snippets_resolution_idx ON file_snippets (resolution) WHERE resolution IS NOT NULL;
CREATE INDEX file_snippets_resolution_snippet_idx ON file_snippets (resolution, snippet DESC) WHERE resolution IS NOT NULL;
CREATE INDEX file_snippets_cleared_snippet_idx ON file_snippets (snippet DESC)
  WHERE resolution IN ('clear', 'overlap', 'covered');
CREATE INDEX file_snippets_unresolved_snippet_idx ON file_snippets (snippet) WHERE resolution IS NULL;
CREATE INDEX file_snippets_unresolved_package_idx ON file_snippets (package, snippet) WHERE resolution IS NULL;
CREATE INDEX file_snippets_building_idx ON file_snippets (package) WHERE generation <> 0;

CREATE TABLE ignored_files (
  id serial PRIMARY KEY,
  glob text NOT NULL,
  owner int REFERENCES bot_users(id) NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  contributor int REFERENCES bot_users(id)
);
CREATE UNIQUE INDEX ON ignored_files(glob);

CREATE TABLE ignored_lines (
  id bigserial PRIMARY KEY,
  packname text NOT NULL,
  hash text NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  owner int REFERENCES bot_users(id),
  contributor int REFERENCES bot_users(id)
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
  package int REFERENCES bot_packages(id) ON DELETE CASCADE NOT NULL,
  ignored_line int REFERENCES ignored_lines(id) ON DELETE SET NULL,
  generation int DEFAULT 0 NOT NULL
);
CREATE INDEX ON pattern_matches(file);
CREATE INDEX ON pattern_matches(package);
CREATE INDEX ON pattern_matches(pattern);
CREATE INDEX ON pattern_matches(ignored_line);
CREATE INDEX ON pattern_matches(ignored);

CREATE TABLE report_checksums (
  id bigserial PRIMARY KEY,
  checksum text NOT NULL,
  shortname text NOT NULL CONSTRAINT shortname_unique UNIQUE
);
CREATE UNIQUE INDEX ON report_checksums(checksum);

CREATE TABLE proposed_changes (
  id serial PRIMARY KEY,
  action text NOT NULL,
  token_hexsum text NOT NULL,
  data jsonb NOT NULL,
  created timestamp with time zone DEFAULT now() NOT NULL,
  owner int REFERENCES bot_users(id) NOT NULL
);
CREATE UNIQUE INDEX ON proposed_changes(token_hexsum);

CREATE TABLE api_keys (
  id          bigserial PRIMARY KEY,
  owner       int REFERENCES bot_users(id) NOT NULL,
  api_key     uuid DEFAULT gen_random_uuid() NOT NULL CONSTRAINT api_key_unique UNIQUE,
  description TEXT,
  created     timestamp with time zone DEFAULT now() NOT NULL,
  expires     timestamp with time zone NOT NULL,
  write_access boolean DEFAULT false NOT NULL,
  can_finalize_reviews boolean DEFAULT false NOT NULL
);

CREATE TABLE package_notes (
  id           bigserial PRIMARY KEY,
  package_name text NOT NULL,
  package      int REFERENCES bot_packages(id) ON DELETE SET NULL,
  author       int REFERENCES bot_users(id) NOT NULL,
  ai_assisted  boolean DEFAULT false NOT NULL,
  body         text NOT NULL,
  lawyer_only  boolean DEFAULT false NOT NULL,
  created      timestamp with time zone DEFAULT now() NOT NULL,
  edited       timestamp with time zone,
  tags         text[] DEFAULT '{}' NOT NULL,
  pinned       boolean DEFAULT false NOT NULL
);
CREATE INDEX ON package_notes (package_name, id DESC);
CREATE INDEX ON package_notes (author);
CREATE INDEX package_notes_tags_idx ON package_notes USING gin (tags);
CREATE INDEX package_notes_pinned_idx ON package_notes (package_name, id DESC) WHERE pinned;

CREATE TABLE package_components (
  id       bigserial PRIMARY KEY,
  package  int REFERENCES bot_packages(id) ON DELETE CASCADE NOT NULL,
  purl     text NOT NULL,
  type     text NOT NULL,
  name     text NOT NULL,
  version  text,
  license  text,
  source   text,
  complete boolean DEFAULT false NOT NULL,
  generation int DEFAULT 0 NOT NULL
);
CREATE UNIQUE INDEX package_components_package_md5_generation_idx ON package_components (package, md5(purl), generation);
CREATE INDEX ON package_components(package);
CREATE INDEX package_components_building_idx ON package_components (package) WHERE generation <> 0;

CREATE TABLE pattern_shingles (
  pattern_id bigint NOT NULL REFERENCES license_patterns(id) ON DELETE CASCADE,
  license    text   NOT NULL,
  shingle    bigint NOT NULL
);
CREATE INDEX pattern_shingles_pattern_idx ON pattern_shingles (pattern_id);
CREATE INDEX pattern_shingles_license_shingle_idx ON pattern_shingles (license, shingle);
CREATE TABLE shingle_license (
  shingle bigint NOT NULL,
  license text   NOT NULL,
  PRIMARY KEY (shingle, license)
);
CREATE FUNCTION pattern_shingles_ins() RETURNS trigger AS $$
  BEGIN
    INSERT INTO shingle_license (shingle, license) VALUES (NEW.shingle, NEW.license) ON CONFLICT DO NOTHING;
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql;
CREATE FUNCTION pattern_shingles_del() RETURNS trigger AS $$
  BEGIN
    DELETE FROM shingle_license sl
     WHERE sl.shingle = OLD.shingle AND sl.license = OLD.license
       AND NOT EXISTS (SELECT 1 FROM pattern_shingles ps WHERE ps.shingle = OLD.shingle AND ps.license = OLD.license);
    RETURN NULL;
  END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER pattern_shingles_ins_trg AFTER INSERT ON pattern_shingles
  FOR EACH ROW EXECUTE FUNCTION pattern_shingles_ins();
CREATE TRIGGER pattern_shingles_del_trg AFTER DELETE ON pattern_shingles
  FOR EACH ROW EXECUTE FUNCTION pattern_shingles_del();

CREATE TABLE comment_templates (
  id      bigserial PRIMARY KEY,
  name    text NOT NULL,
  body    text NOT NULL,
  author  int REFERENCES bot_users(id),
  created timestamp with time zone DEFAULT now() NOT NULL,
  edited  timestamp with time zone
);
CREATE UNIQUE INDEX ON comment_templates (name);
CREATE INDEX ON comment_templates (author);
INSERT INTO comment_templates (name, body) VALUES ('Unacceptable-File',
'This package cannot be accepted as is.

The file [FILE] is licensed under [LICENSE], which we cannot ship.

Please remove the file from the sources, or replace it with a version under an
acceptable license, and then resubmit the package for review.');

CREATE TABLE copyrights (
  id bigserial PRIMARY KEY,
  package int REFERENCES bot_packages(id) NOT NULL,
  copyright text NOT NULL,
  files text[] DEFAULT '{}' NOT NULL,
  generation int DEFAULT 0 NOT NULL
);
CREATE UNIQUE INDEX copyrights_package_md5_generation_idx ON copyrights (package, md5(copyright), generation);
CREATE INDEX copyrights_package_idx  ON copyrights (package);
CREATE INDEX copyrights_building_idx ON copyrights (package) WHERE generation <> 0;

-- 67 down
DROP TABLE IF EXISTS copyrights;
DROP TABLE IF EXISTS comment_templates;
DROP TABLE IF EXISTS shingle_license;
DROP TABLE IF EXISTS pattern_shingles;
DROP FUNCTION IF EXISTS pattern_shingles_ins;
DROP FUNCTION IF EXISTS pattern_shingles_del;
DROP TABLE IF EXISTS package_components;
DROP TABLE IF EXISTS package_notes;
DROP TABLE IF EXISTS api_keys CASCADE;
DROP TABLE IF EXISTS proposed_changes;
DROP TABLE IF EXISTS report_checksums;
DROP TABLE IF EXISTS pattern_matches;
DROP TABLE IF EXISTS ignored_lines;
DROP TABLE IF EXISTS ignored_files;
DROP TABLE IF EXISTS file_snippets;
DROP TABLE IF EXISTS snippets;
DROP TABLE IF EXISTS license_patterns;
DROP TABLE IF EXISTS matched_files;
DROP TABLE IF EXISTS bot_requests;
DROP TABLE IF EXISTS bot_reports;
DROP TABLE IF EXISTS bot_package_products;
DROP TABLE IF EXISTS bot_products;
DROP TABLE IF EXISTS urls;
DROP TABLE IF EXISTS emails;
DROP TABLE IF EXISTS bot_packages;
DROP TABLE IF EXISTS bot_users;
DROP TABLE IF EXISTS bot_sources;
DROP TYPE IF EXISTS bot_state;
