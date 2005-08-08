use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Catalyst::Plugin::Devel::InPageLogs',
    license             => 'perl',
    dist_author         => 'Thomas L. Shinnick <tshinnic@cpan.org>',
    dist_version_from   => 'lib/Catalyst/Plugin/Devel/InPageLogs.pm',
    requires => {
        'Test::More'    => 0,
        'Catalyst'      => '5.10',  # a guess; reports welcome
        'Data::Dumper'  => 0,
    },
    add_to_cleanup      => [ 'Catalyst-Plugin-Devel-InPageLogs-*' ],
    dist_abstract       => 'Append Catalyst request debug messages to output web page',
);

$builder->create_build_script();

#  vim:ft=perl:ts=4:sw=4:et:is:hls:ss=10:
