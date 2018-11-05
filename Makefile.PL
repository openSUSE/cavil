use 5.010001;

use strict;
use warnings;
use utf8;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Cavil',
  VERSION_FROM => 'lib/Cavil.pm',
  ABSTRACT     => 'Legal Reviews',
  AUTHOR =>
    ['Sebastian Riedel <sriedel@suse.de>', 'Stephan Kulow <coolo@suse.de>'],
  LICENSE    => 'gpl_2',
  META_MERGE => {
    dynamic_config => 0,
    'meta-spec'    => {version => 2},
    no_index       => {directory => ['t']},
    prereqs        => {runtime => {requires => {perl => '5.010001'}}},
    resources      => {
      bugtracker => {web => 'https://github.com/openSUSE/cavil/issues'},
      homepage   => 'https://github.com/openSUSE/cavil',
      repository => {
        type => 'git',
        url  => 'https://github.com/openSUSE/cavil.git',
        web  => 'https://github.com/openSUSE/cavil/issues',
      },
      x_IRC => 'irc://irc.freenode.org/#opensuse-factory'
    },
  },
  PREREQ_PM => {
    Mojolicious                      => '7.88',
    'Mojolicious::Plugin::AssetPack' => 0,
    'Mojo::Pg'                       => '4.08',
    'Minion'                         => '8.0',
    'File::Unpack'                   => 0,
    'Cpanel::JSON::XS'               => 0,
    'Spooky::Patterns::XS'           => '1.50',
    'Net::OpenID::Consumer'          => 0,
    'LWP::UserAgent'                 => 0,
    'BSD::Resource'                  => 0
  },
  EXE_FILES => ['script/cavil'],
  test      => {TESTS => 't/*.t t/*/*.t'}
);
