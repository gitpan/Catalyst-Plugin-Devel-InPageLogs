package Catalyst::Plugin::Devel::InPageLogs;

use strict;
use warnings;

use Catalyst::Plugin::Devel::InPageLogs::Log;
use NEXT;

our $VERSION = '0.01_02';

# hash key to use when saving plugin data into context
our $plugin_dataname  = 'inpagelogs';


=head1 NAME

Catalyst::Plugin::Devel::InPageLogs - append request debug messages to HTML web page output

=head1 SYNOPSIS

    use Catalyst 'Devel::InPageLogs';

    # These are the default values
    __PACKAGE__->config->{inpagelogs} = { 
        enabled    => 1,
        passthru   => 1,
        addcaller  => 1,
        shortnames => 'dbg,dbgf',
    };

    # In MyApp::C::SuperHero
    $c->dbgf( "Leaped over %d tall buildings", $count );


=head1 DESCRIPTION

This plugin module for the Catalyst framework provides a means to capture
debugging messages and append them to the end of web page output.  
The automatic display of debug messages in the same web page with 
normal HTML output can be very convenient during development.  

One way to think about this plugin is to compare it with the Unix 
'tee' command.  Debug log messages continue to display using the 
core logger Catalyst::Log, but are also captured and displayed
in the browser.

Almost all debug/info/etc. messages created during processing of
one HTTP request are returned in the generated HTML page, grouped together 
and appended to the end of the displayed HTML.  A few core debug messages
are missed at end of a request (see L<"LIMITATIONS">).

Please note that B<only during processing of requests> are debug messages
are captured and displayed.
This means that only debug calls from controller, model, and view 
routines will be handled.
This is not a real limitation as only these messages I<could>
be added to the web page.

If care for security issues is taken then this facility could even be
enabled at will using URL parameters.  This could be I<very> helpful
when only the beta tester's browser is close at hand.

In addition to the normal debug, warn, etc. routines documented for
L<Catalyst::Log>, this plugin adds two convenience methods.  
These two methods combine shorter names with added information noting
the calling location.  One of these add-on methods also conveniently
handles L<sprintf> formatting.

=cut

=head1 CONFIGURATION OPTIONS

Some plugin behavior can be controlled by configuration options.  You can
modify the defaults by specifying values using the 
C<__PACKAGE__-E<gt>config-E<gt>{inpagelogs}> key.

=head2 enabled

The plugin can be disabled by setting this value to zero.  
You may want to do this to leave the code unchanged but prevent
debug output from being seen when not in development.  
A warning log message will be generated noting that the plugin is
installed but disabled.

=head2 passthru

The plugin defaults to 'tee' mode - passing calls to debug/warn/etc.
to the core logger after capturing them.  Messages will be displayed
in both the normal log and in the web page.

If you want debug messages displayed only in the web page you can 
set this config value to zero.

=head2 shortnames

As a convenience for the developer, the plugin will define short name
aliases for the add-on debug routines.  

You may change the short name symbol definitions used if the defaults
would conflict with existing other code.  Set the config value to a 
string of two name symbols separated by a comma:

        shortname => "bugout,bugfmt",

The first name is aliased to the "capture a set of messages" routine.
The second name is aliased to the "format a message and capture it"
routine.

=head2 addcaller

The add-on debug routines (normally 'dbg' and 'dbgf') will record
caller information in each message.  
The calling filename and linenumber will be added after the timestamp.

If you do not want this added information, set this config value to zero.

=head1 METHODS

=head2 EXTENDED METHODS

=head3 prepare_request

Setup plugin-specific data area in the current request.

This plugin method will create and attach a work area to the current
request context.  The work area will contain the array used to
collect the captured debug messages.  
The existing core logger object reference is saved before installing
our own logger object.

=cut

# This plugin method is the first point at which we can execute during
# processing of one request.  The context at this point is an Engine
# object, which will be discarded at end of request processing.
#
# We attach our data area to the context object using the hash key
# 'inpagelogs', in keeping with the methods employed by other plugins.


sub prepare_request {
    my ( $c ) = shift;

    unless( $c->is_inpagelogs_enabled ) {
        $c->log->warn( "InPageLogs plugin is disabled by config" );
        return $c->NEXT::prepare_request( @_ );
    }

    # Determine whether shortnames are enabled and what they are
    #
    # We use defaults of enabled and shortnames 'dbg' and 'dbgf'
    #   - if no config is specified
    #   - if no 'shortnames' config value is specified
    #   - if config value is 'yes'
    # We are disabled if config value is present and equals 'no'
    # We use shortnames from the config value if two name strings 
    #   are present in the value
    # Otherwise we complain and disable ourselves

    my  @shortnames = ( 'dbg', 'dbgf' );
    
    my  $cfg_value = $c->inpagelogs_config('shortnames');
    if( defined $cfg_value ) {

        my  $shortnames = 'yes';

        if ( my  @newnames = $cfg_value =~ m/^\s*(\w+)\s*,\s*(\w+)\s*$/ ) {
            if( @newnames == 2 ) {
                @shortnames = @newnames;
            }
            else {
                $shortnames = 'bad'; # disabled by bad 'shortnames' config value 
            }
        }
        elsif ( $cfg_value =~ m/^ \s* no \s* $/ix ) {
            @shortnames = ();
        }
        elsif ( $cfg_value =~ m/^ \s* yes \s* $/ix ) {
            ;
        }
        else {
            $shortnames = 'bad'; # disabled by bad 'shortnames' config value 
        }

        if ( $shortnames eq 'bad' ) {
            $c->log->warn( "InPageLogs plugin 'shortnames' config value '$cfg_value' is invalid" );
            @shortnames = ();
        }
    }

    # Create our new logger object
    my  $new_log_obj = Catalyst::Plugin::Devel::InPageLogs::Log->new( $c );
    
    # Create plugin-specific data area, storing array ref for captured
    #   debug messages, and saving the current logging object.
    my  %data_area  = (
            buffer       => [],
            old_log_obj  => $c->log,
            new_log_obj  => $new_log_obj,
        );

    $c->{$plugin_dataname} = \%data_area;

    # Replace current log object for use during this request
    $c->log( $new_log_obj );

    # If convenience short names are enabled, create those definitions
    if( @shortnames ) {
        no strict 'refs';
        *{ ref($c) . '::' . $shortnames[0] } = \&inpagelogs_log_msg;
        *{ ref($c) . '::' . $shortnames[1] } = \&inpagelogs_log_msgf;
    }

    # Done here, continue the plugin chain
    $c->NEXT::prepare_request( @_ );
}


=head3 finalize

This plugin method will check whether captured debug messages can be
appended to the current output body.  Only content type 'text/html'
output will be updated.

The saved previous logger object will be restored at this point.

=cut

# This is the last possible point during finalization of a response 
# for us intervene, before the generated output is actually sent to
# the browser.
#
# As our data area reference is held within the engine context object
# we shouldn't need to take extra efforts to delete the hash, but can
# let discarding the engine context at end of request do that for us.


sub finalize {
    my ( $c ) = shift;

    unless ( $c->response->body ) {
        return $c->NEXT::finalize;
    }

    unless ( $c->response->content_type =~ m!^text/html!i ) {
        return $c->NEXT::finalize;
    }
    
    my  $data_area = $c->inpagelogs_data;
    unless ( defined $data_area  ) {
        return $c->NEXT::finalize;
    }

    # If there are captured messages in our save area
    if ( defined $data_area->{buffer} ) {
        my  $ra = $c->inpagelogs_data->{buffer};
        $c->res->body( $c->res->body . '<pre>' . join('',@$ra) . '</pre>' );
    }

    # Restore the original log object
    if ( defined $data_area->{old_log_obj} ) {
        $c->log( $data_area->{old_log_obj} );
    }

    # Allow other plugins/core to finish generating output body
    return $c->NEXT::finalize;
}


=head2 INTERNAL METHODS

=head3 inpagelogs_data  - access to plugin-specific data area

    $data_area = $c->inpagelogs_data;

Return reference to work area for this plugin during this request.
If no work area was created (perhaps because plugin is disabled)
then C<undef> is returned.

=cut 

sub inpagelogs_data {
    my ( $c ) = @_;

    return  $c->{$plugin_dataname};
}

=head3  inpagelogs_config   - access to plugin-specific config area

    $config_area = $c->inpagelogs_config;

Return reference to config hash section for this plugin, if present.
Otherwise C<undef> will be returned.

=cut

sub inpagelogs_config {
    my ( $c ) = @_;

    my  $our_config = $c->config->{$plugin_dataname};

    # If a specific config value is requested, return that
    if( defined $our_config  &&  @_ > 1  ) {
        return  $our_config->{ $_[1] };
    }

    return  $our_config;
}

=head3  is_inpagelogs_enabled - check config flag

    return  unless $c->is_inpagelogs_enabled;

The default is to assume the installed plugin is enabled, unless

=over 8

=item   'inpagelogs' config section is present, and

=item   'enabled' flag value is present, and

=item   the value is set to zero

=back

=cut 

sub is_inpagelogs_enabled {
    my ( $c ) = shift;

    my  $enabled = $c->inpagelogs_config('enabled');
    # Default to 'enabled' if installed but no config set
    # Default to 'enabled' if config doesn't mention flag
    return 1  unless defined $enabled;

    # Otherwise return configured enable flag value
    return $enabled;
}


=head2 PUBLIC METHODS

=head3 inpagelogs_add_msg - add messages to our capture array

    $c->inpagelogs_add_msg( 
            'Whoa! What they said!', 
            "  parameter was '$he_said_she_said'" );

This method will take one or more strings and save them in the capture buffer
for later display.

The only formatting done is to add a "\n" to the end of every string
that does not already end with "\n".            

=cut 

sub inpagelogs_add_msg {
    my( $c ) = shift;

    return  unless @_ > 0;

    my  $data_area = $c->inpagelogs_data;
    return  unless defined $data_area;

    my  $buffer = $data_area->{buffer};
    return  unless defined $buffer;

    foreach my $msg ( @_ ) {
        if( $msg =~ m/\n\z/ ) {
            push @{$buffer}, $msg;
        } else {
            push @{$buffer}, $msg . "\n";
        }
    }
}

# The add-on convenience methods for debugging with added information

=head3  inpagelogs_log_msg   - capture debug messages

Add a list of strings to captured debug messages.

=cut 

sub inpagelogs_log_msg {
    my  $c  = shift;
    my( $filename, $line ) = ( caller() )[1,2];
    $c->inpagelogs_log_msgsub( $filename, $line, @_ );
}

=head3  inpagelogs_log_msgf  - sprintf format parameters and capture debug message

    $c->inpagelogs_log_msgf( "I saw a huge number '%12.3g'\n", $value );

Process a format and parameters using sprintf, then add result
to captured debug messages.

=cut 

sub inpagelogs_log_msgf {
    my  $c = shift;
    my  $msg = sprintf shift, @_;
    my( $filename, $line ) = ( caller() )[1,2];
    $c->inpagelogs_log_msgsub( $filename, $line, $msg );
}


=head3  inpagelogs_log_msgsub  - internal debug message capture routine

This routine handles the final formatting of messages added to the
capture array.

The formatted current time will prefix the first message.  The time is 
formatted using overridable routine C<_log_time_formatter>.

By default the caller information, filename and line number, will be
formatted and also added before the first message.  This can be controlled
by configuration option C<addcaller>.

=cut 

sub inpagelogs_log_msgsub {
    my  $c        = shift;
    my  $filename = shift;
    my  $line     = shift;

    my  $time_string = _log_time_formatter();

    my  $addcaller = $c->inpagelogs_config('addcaller');
    if( ! defined $addcaller  ||  $addcaller ) {
        # While running using stand-alone server, remove leading home path
        my  $home   = $c->config->{home};
        $home =~ s/\\/\//g;
        if( substr($filename,0,length $home) eq $home ) {
            $filename = substr($filename,length $home);
        } 
        # Remove some more repeated stuff if present
        $home = '/script/../lib/';
        if( substr($filename,0,length $home) eq $home ) {
            $filename = substr($filename,length $home);
        } 
  
        my  $hdr = "${time_string}:  ($filename,$line)\n";
        $c->inpagelogs_add_msg( $hdr, @_ );
    } 
    else {
        my  $hdr = "${time_string}:  " . shift;
        $c->inpagelogs_add_msg( $hdr, @_ );
    }
}


{   
#   Return local epoch date/time in format MMDDpHHmmSS  (e.g. 0109.191550)

    # A small bit of memoizing of results.  We are assuming that the
    #   log times will be in forward sequence, with each input time
    #   value repeated a number of times.
    # If a new time input value is same as previous, then we can simply 
    #   return the previously formatted string result.

    #   Previous epoch time value input received
    my  $prev_time;  
    #   Previous formatted string result 
    my  $prev_string;

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



=head1 LIMITATIONS

=head2 MISSED MESSAGES

Due to the sequence of Catalyst internal operations and calls to the
plugin methods, some debug messages at the very end of processing 
for a request cannot be seen by this plugin.

Specifically (and most regretably) the displayed output table showing
the actions executed for the request are not captured, e.g. 

  [Wed Aug  3 16:30:39 2005] [catalyst] [info] Request took 0.27s (3.70/s)
  .=---------------------------------------------+----------=.
  | Action                                       | Time      |
  |=---------------------------------------------+----------=|
  | /begin                                       | 0.000955s |
  | -> /user/upld/phase2page                     | 0.000614s |
  | /user/upld/phase1                            | 0.002515s |
  | -> Widget::V::TT->process                    | 0.228791s |
  | /user/upld/end                               | 0.230610s |
  '=---------------------------------------------+----------='

will not be seen except in the core logger output.    

=head2 NOT INTEGRATED WITH DEFAULT ERROR PAGE

The 'pretty' error page displayed by Catalyst upon an exception
does not include any debug messages captured by this plugin.

=head1 TODOS

=over 4

=item Figure out how to add our messages to Catalyst exception page

=item Propose patch to move logging of action execution summary earlier?

=item Use check "if ( $c->isa('Catalyst::Plugin::Devel::InPageLogs') )" ?

=back


=head1 SEE ALSO

L<Catalyst>, L<Catalyst::Log>.

=head1 AUTHOR

Thomas L. Shinnick  <tshinnic@cpan.org>

=head1 LICENSE

This library is free software . You can redistribute it and/or modify
it under the same terms as perl itself.

=cut

1;

__END__

Todos:

    Should the removed leading caller filename string be configurable
        in inpagelogs_log_msgsub() ?

    Use config flags to control behaviors

    Move the logging inner class to own module

    Do I need something like:
       if ( $c->isa('Catalyst::Plugin::Devel::InPageLogs') ) {

    Why is finalize_body not being called on (?) 
        - non text/html requests?
        - static data requests?  status = 304 not modified

    What facilities in Catalyst to process arguments meant for plugins
        Can it correctly process 
            use Catalyst qw{ -log=MyLogger InPageLogs=passthru };
      * only the -Debug and -opt options show any evidence of allowing
            arguments with 'plugin' names
      * however, there is an "instant plugin" (dynamic plugin?) that
            shows handling of arguments to a 'new()' call
            

## xshortnames: no              defaults defined
## shortnames: dbg, dbgf        works as though defaulted
## shortnames: yes              works as though defaulted
## shortnames: xdbg, xdbgf      dies with:  Can't locate object method "dbgf"
## shortnames: foo              dies with:  Can't locate object method "dbgf"
## shortnames: no               dies with:  Can't locate object method "dbgf"



#  vim:ft=perl:ts=4:sw=4:et:is:hls:ss=10:
