package Catalyst::Plugin::Devel::InPageLogs::Log;

use strict;
use warnings;

use base 'Catalyst::Log';

our $VERSION = '0.01_02';

## # hash key to use when saving plugin data into context
## our $plugin_dataname  = '_inpagelogs';


=head1 NAME

Catalyst::Plugin::Devel::InPageLogs::Log - 

=head1 SYNOPSIS

    use Catalyst::Plugin::Devel::InPageLogs::Log;


=head1 DESCRIPTION


=cut

=head1 METHODS

=head2 PUBLIC METHODS

=head3 new

=cut


sub new {
    my $class   = shift;
    my $dataref = shift;

    my $self  = $class->SUPER::new(@_);

    $self->{$Catalyst::Plugin::Devel::InPageLogs::plugin_dataname} = $dataref;

    return $self;
}

=head2 EXTENDED METHODS

=head3 _log

Add plugin-specific data attributes to current request.

=cut

sub _log {
    my $self    = shift;
    my $level   = shift;
    my $message = join( "\n", @_ );

    $level = substr($level,0,1);
    my $time    = _log_time_formatter();

    my  $msg = sprintf "[%s] [%s] %s\n", $time, $level, $message;

    my  $c = $self->{$Catalyst::Plugin::Devel::InPageLogs::plugin_dataname};
    $c->inpagelogs_add_msg( $msg );

    my  $passthru = $c->inpagelogs_config('passthru');
    if( ! defined $passthru  ||  $passthru ) {
        $self->SUPER::_log( $level, @_ );
    }
}


=head2 OVERRIDABLE METHODS

=head3 _log_time_formatter

=cut


{   
    # Persistent private variables for subroutine
    #   Previous epoch time value input received
    my  $prev_time;  
    #   Previous formatted string result 
    my  $prev_string;
    # If new time input is same as previous, then we can simply return
    # the previous formatted string result.

#   Return local date/time in format MMDDpHHmmSS  (e.g. 0109.191550)
sub _log_time_formatter {
    my( $time ) = shift  ||  time;

    unless( defined $prev_time  &&  $prev_time == $time ) {
        $prev_time = $time;
        my( $sec, $min, $hour, $mday, $mon, $year ) = localtime($prev_time);
        $prev_string = sprintf( "%02d%02d.%02d%02d%02d",
                                $mon+1, $mday, $hour, $min, $sec );
    }

    $prev_string;
}
}


1;

__END__



#  vim:ft=perl:ts=4:sw=4:et:is:hls:ss=10:
