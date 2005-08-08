use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Catalyst::Plugin::Devel::InPageLogs',
    AUTHOR              => 'Thomas L. Shinnick <tshinnic@cpan.org>',
    VERSION_FROM        => 'lib/Catalyst/Plugin/Devel/InPageLogs.pm',
    ABSTRACT            => 'Append Catalyst request debug messages to output web page',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Catalyst'      => '5.10',  # a guess; reports welcome
        'Data::Dumper'  => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Catalyst-Plugin-Devel-InPageLogs-*' },
);
