package HTTP::Headers::Fast;
use strict;
use warnings;
use 5.00800;
use Carp ();

our $VERSION = '0.04';

our $TRANSLATE_UNDERSCORE = 1;

# "Good Practice" order of HTTP message headers:
#    - General-Headers
#    - Request-Headers
#    - Response-Headers
#    - Entity-Headers

# yappo says "Readonly sucks".
my $OP_GET    = 0;
my $OP_SET    = 1;
my $OP_INIT   = 2;
my $OP_PUSH   = 3;

my @general_headers = qw(
  Cache-Control Connection Date Pragma Trailer Transfer-Encoding Upgrade
  Via Warning
);

my @request_headers = qw(
  Accept Accept-Charset Accept-Encoding Accept-Language
  Authorization Expect From Host
  If-Match If-Modified-Since If-None-Match If-Range If-Unmodified-Since
  Max-Forwards Proxy-Authorization Range Referer TE User-Agent
);

my @response_headers = qw(
  Accept-Ranges Age ETag Location Proxy-Authenticate Retry-After Server
  Vary WWW-Authenticate
);

my @entity_headers = qw(
  Allow Content-Encoding Content-Language Content-Length Content-Location
  Content-MD5 Content-Range Content-Type Expires Last-Modified
);

my %entity_header = map { lc($_) => 1 } @entity_headers;

my @header_order =
  ( @general_headers, @request_headers, @response_headers, @entity_headers, );

# Make alternative representations of @header_order.  This is used
# for sorting and case matching.
my %header_order;
my %standard_case;

{
    my $i = 0;
    for (@header_order) {
        my $lc = lc $_;
        $header_order{$lc}  = ++$i;
        $standard_case{$lc} = $_;
    }
}

sub new {
    my ($class) = shift;
    my $self = bless {}, $class;
    $self->header(@_) if @_;    # set up initial headers
    $self;
}

sub header {
    my $self = shift;
    Carp::croak('Usage: $h->header($field, ...)') unless @_;
    my (@old);

    if (@_ == 1) {
        @old = $self->_header_get(@_);
    } elsif( @_ == 2 ) {
        @old = $self->_header_set(@_);
    } else {
        my %seen;
        while (@_) {
            my $field = shift;
            if ( $seen{ lc $field }++ ) {
                @old = $self->_header_push($field, shift);
            } else {
                @old = $self->_header_set($field, shift);
            }
        }
    }
    return @old    if wantarray;
    return $old[0] if @old <= 1;
    join( ", ", @old );
}

sub clear {
    my $self = shift;
    %$self = ();
}

sub push_header {
    my $self = shift;

    if (@_ == 2) {
        my ($field, $val) = @_;
        $field = _standardize_field_name($field) unless $field =~ /^:/;

        my $h = $self->{$field};
        if (!defined $h) {
            $h = [];
            $self->{$field} = $h;
        } elsif (ref $h ne 'ARRAY') {
            $h = [ $h ];
            $self->{$field} = $h;
        }
    
        push @$h, ref $val ne 'ARRAY' ? $val : @$val;
    } else {
        while ( my ($field, $val) = splice( @_, 0, 2 ) ) {
            $field = _standardize_field_name($field) unless $field =~ /^:/;

            my $h = $self->{$field};
            if (!defined $h) {
                $h = [];
                $self->{$field} = $h;
            } elsif (ref $h ne 'ARRAY') {
                $h = [ $h ];
                $self->{$field} = $h;
            }
    
            push @$h, ref $val ne 'ARRAY' ? $val : @$val;
        }
    }
    return ();
}

sub init_header {
    Carp::croak('Usage: $h->init_header($field, $val)') if @_ != 3;
    shift->_header( @_, $OP_INIT );
}

sub remove_header {
    my ( $self, @fields ) = @_;
    my $field;
    my @values;
    for my $field (@fields) {
        $field =~ tr/_/-/ if $field !~ /^:/ && $TRANSLATE_UNDERSCORE;
        my $v = delete $self->{ lc $field };
        push( @values, ref($v) eq 'ARRAY' ? @$v : $v ) if defined $v;
    }
    return @values;
}

sub remove_content_headers {
    my $self = shift;
    unless ( defined(wantarray) ) {

        # fast branch that does not create return object
        delete @$self{ grep $entity_header{$_} || /^content-/, keys %$self };
        return;
    }

    my $c = ref($self)->new;
    for my $f ( grep $entity_header{$_} || /^content-/, keys %$self ) {
        $c->{$f} = delete $self->{$f};
    }
    $c;
}

my %field_name;
sub _standardize_field_name {
    my $field = shift;

    $field =~ tr/_/-/ if $TRANSLATE_UNDERSCORE;
    if (my $cache = $field_name{$field}) {
        return $cache;
    }

    my $old = $field;
    $field = lc $field;
    unless ( defined $standard_case{$field} ) {
        # generate a %standard_case entry for this field
        $old =~ s/\b(\w)/\u$1/g;
        $standard_case{$field} = $old;
    }
    $field_name{$old} = $field;
    return $field;
}

sub _header_get {
    my ($self, $field, $skip_standardize) = @_;

    $field = _standardize_field_name($field) unless $skip_standardize || $field =~ /^:/;

    my $h = $self->{$field};
    return (ref($h) eq 'ARRAY') ? @$h : ( defined($h) ? ($h) : () );
}

sub _header_set {
    my ($self, $field, $val) = @_;

    $field = _standardize_field_name($field) unless $field =~ /^:/;

    my $h = $self->{$field};
    my @old = ref($h) eq 'ARRAY' ? @$h : ( defined($h) ? ($h) : () );
    if ( defined($val) ) {
        if (ref $val eq 'ARRAY' && scalar(@$val) == 1) {
            $val = $val->[0];
        }
        $self->{$field} = $val;
    } else {
        delete $self->{$field};
    }
    return @old;
}

sub _header_push_no_return {
    my ($self, $field, $val) = @_;

    $field = _standardize_field_name($field) unless $field =~ /^:/;

    my $h = $self->{$field};
    if (ref($h) eq 'ARRAY') {
        push @$h, ref $val ne 'ARRAY' ? $val : @$val;
    } elsif (defined $h) {
        $self->{$field} = [$h, ref $val ne 'ARRAY' ? $val : @$val ];
    } else {
        $self->{$field} = ref $val ne 'ARRAY' ? $val : @$val;
    }
    return;
}

sub _header_push {
    my ($self, $field, $val) = @_;

    $field = _standardize_field_name($field) unless $field =~ /^:/;

    my $h = $self->{$field};
    if (ref($h) eq 'ARRAY') {
        my @old = @$h;
        push @$h, ref $val ne 'ARRAY' ? $val : @$val;
        return @old;
    } elsif (defined $h) {
        $self->{$field} = [$h, ref $val ne 'ARRAY' ? $val : @$val ];
        return ($h);
    } else {
        $self->{$field} = ref $val ne 'ARRAY' ? $val : @$val;
        return ();
    }
}

sub _header {
    my ($self, $field, $val, $op) = @_;

    $field = _standardize_field_name($field) unless $field =~ /^:/;

    $op ||= defined($val) ? $OP_SET : $OP_GET;

    my $h = $self->{$field};
    my @old = ref($h) eq 'ARRAY' ? @$h : ( defined($h) ? ($h) : () );

    unless ( $op == $OP_GET || ( $op == $OP_INIT && @old ) ) {
        if ( defined($val) ) {
            my @new = ( $op == $OP_PUSH ) ? @old : ();
            if ( ref($val) ne 'ARRAY' ) {
                push( @new, $val );
            }
            else {
                push( @new, @$val );
            }
            $self->{$field} = @new > 1 ? \@new : $new[0];
        }
        elsif ( $op != $OP_PUSH ) {
            delete $self->{$field};
        }
    }
    @old;
}

sub _sorted_field_names {
    my $self = shift;
    return sort {
        ( $header_order{$a} || 999 ) <=> ( $header_order{$b} || 999 )
          || $a cmp $b
    } keys %$self;
}

sub header_field_names {
    my $self = shift;
    return map $standard_case{$_} || $_, $self->_sorted_field_names
      if wantarray;
    return keys %$self;
}

sub scan {
    my ( $self, $sub ) = @_;
    for my $key ( $self->_sorted_field_names ) {
        next if substr($key, 0, 1) eq '_';
        my $vals = $self->{$key};
        if ( ref($vals) eq 'ARRAY' ) {
            for my $val (@$vals) {
                $sub->( $standard_case{$key} || $key, $val );
            }
        }
        else {
            $sub->( $standard_case{$key} || $key, $vals );
        }
    }
}

sub _process_newline {
    local $_ = shift;
    my $endl = shift;
    # must handle header values with embedded newlines with care
    s/\s+$//;        # trailing newlines and space must go
    s/\n\n+/\n/g;    # no empty lines
    s/\n([^\040\t])/\n $1/g; # intial space for continuation
    s/\n/$endl/g;    # substitute with requested line ending
    $_;
}

sub _as_string {
    my ($self, $endl, $fieldnames) = @_;

    my @result;
    for my $key ( @$fieldnames ) {
        next if index($key, '_') == 0;
        my $vals = $self->{$key};
        if ( ref($vals) eq 'ARRAY' ) {
            for my $val (@$vals) {
                my $field = $standard_case{$key} || $key;
                $field =~ s/^://;
                if ( index($val, "\n") >= 0 ) {
                    $val = _process_newline($val, $endl);
                }
                push @result, $field . ': ' . $val;
            }
        } else {
            my $field = $standard_case{$key} || $key;
            $field =~ s/^://;
            if ( index($vals, "\n") >= 0 ) {
                $vals = _process_newline($vals, $endl);
            }
            push @result, $field . ': ' . $vals;
        }
    }

    join( $endl, @result, '' );
}

sub as_string {
    my ( $self, $endl ) = @_;
    $endl = "\n" unless defined $endl;
    $self->_as_string($endl, [$self->_sorted_field_names]);
}

sub as_string_without_sort {
    my ( $self, $endl ) = @_;
    $endl = "\n" unless defined $endl;
    $self->_as_string($endl, [keys(%$self)]);
}

{
    my $storable_required;
    sub clone {
        unless ($storable_required) {
            require Storable;
            $storable_required++;
        }
        goto &Storable::dclone;
    }
}

sub _date_header {
    require HTTP::Date;
    my ( $self, $header, $time ) = @_;
    my $old;
    if ( defined $time ) {
        ($old) = $self->_header_set( $header, HTTP::Date::time2str($time) );
    } else {
        ($old) = $self->_header_get($header, 1);
    }
    $old =~ s/;.*// if defined($old);
    HTTP::Date::str2time($old);
}

sub date                { shift->_date_header( 'date',                @_ ); }
sub expires             { shift->_date_header( 'expires',             @_ ); }
sub if_modified_since   { shift->_date_header( 'if-modified-since',   @_ ); }
sub if_unmodified_since { shift->_date_header( 'if-unmodified-since', @_ ); }
sub last_modified       { shift->_date_header( 'last-modified',       @_ ); }

# This is used as a private LWP extension.  The Client-Date header is
# added as a timestamp to a response when it has been received.
sub client_date { shift->_date_header( 'client-date', @_ ); }

# The retry_after field is dual format (can also be a expressed as
# number of seconds from now), so we don't provide an easy way to
# access it until we have know how both these interfaces can be
# addressed.  One possibility is to return a negative value for
# relative seconds and a positive value for epoch based time values.
#sub retry_after       { shift->_date_header('Retry-After',       @_); }

sub content_type {
    my $self = shift;
    my $ct   = $self->{'content-type'};
    $self->{'content-type'} = shift if @_;
    $ct = $ct->[0] if ref($ct) eq 'ARRAY';
    return '' unless defined($ct) && length($ct);
    my @ct = split( /;\s*/, $ct, 2 );
    for ( $ct[0] ) {
        s/\s+//g;
        $_ = lc($_);
    }
    wantarray ? @ct : $ct[0];
}

sub content_is_html {
    my $self = shift;
    return $self->content_type eq 'text/html' || $self->content_is_xhtml;
}

sub content_is_xhtml {
    my $ct = shift->content_type;
    return $ct eq "application/xhtml+xml"
      || $ct   eq "application/vnd.wap.xhtml+xml";
}

sub content_is_xml {
    my $ct = shift->content_type;
    return 1 if $ct eq "text/xml";
    return 1 if $ct eq "application/xml";
    return 1 if $ct =~ /\+xml$/;
    return 0;
}

sub referer {
    my $self = shift;
    if ( @_ && $_[0] =~ /#/ ) {

        # Strip fragment per RFC 2616, section 14.36.
        my $uri = shift;
        if ( ref($uri) ) {
            $uri = $uri->clone;
            $uri->fragment(undef);
        }
        else {
            $uri =~ s/\#.*//;
        }
        unshift @_, $uri;
    }
    ( $self->_header( 'Referer', @_ ) )[0];
}
*referrer = \&referer;    # on tchrist's request

for my $key (qw/content-length content-language content-encoding title user-agent server from warnings www-authenticate authorization proxy-authenticate proxy-authorization/) {
    no strict 'refs';
    (my $meth = $key) =~ s/-/_/g;
    *{$meth} = sub {
        my $self = shift;
        if (@_) {
            ( $self->_header_set( $key, @_ ) )[0]
        } else {
            my $h = $self->{$key};
            (ref($h) eq 'ARRAY') ? $h->[0] : $h;
        }
    };
}

sub authorization_basic { shift->_basic_auth( "Authorization", @_ ) }
sub proxy_authorization_basic {
    shift->_basic_auth( "Proxy-Authorization", @_ );
}

sub _basic_auth {
    require MIME::Base64;
    my ( $self, $h, $user, $passwd ) = @_;
    my ($old) = $self->_header($h);
    if ( defined $user ) {
        Carp::croak("Basic authorization user name can't contain ':'")
          if $user =~ /:/;
        $passwd = '' unless defined $passwd;
        $self->_header(
            $h => 'Basic ' . MIME::Base64::encode( "$user:$passwd", '' ) );
    }
    if ( defined $old && $old =~ s/^\s*Basic\s+// ) {
        my $val = MIME::Base64::decode($old);
        return $val unless wantarray;
        return split( /:/, $val, 2 );
    }
    return;
}

1;
__END__

=encoding utf8

=head1 NAME

HTTP::Headers::Fast - faster implementation of HTTP::Headers

=head1 SYNOPSIS

  use HTTP::Headers::Fast;
  # and, same as HTTP::Headers.

=head1 DESCRIPTION

HTTP::Headers::Fast is a perl class for parsing/writing HTTP headers.

The interface is same as HTTP::Headers.

=head1 WHY YET ANOTHER ONE?

HTTP::Headers is a very good. But I needed a faster implementation, fast  =)

HTTP::Headers is also a part of LWP, but I only needed HTTP::Headers. I didn't want to require more modules than necessary.

=head1 ADDITIONAL METHODS

=over 4

=item as_string_without_sort

as_string method sorts the header names.But, sorting is bit slow.

In this method, stringify the instance of HTTP::Headers::Fast without sorting.

=back

=head1 @ISA HACK

If you want HTTP::Headers::Fast to pretend like it's really HTTP::Headers, you can try the following hack:

    unshift @HTTP::Headers::Fast::ISA, 'HTTP::Headers';

=head1 BENCHMARK

    HTTP::Headers 5.818, HTTP::Headers::Fast 0.01

    -- push_header
            Rate orig fast
    orig 144928/s   -- -20%
    fast 181818/s  25%   --

    -- push_header_many
            Rate orig fast
    orig 74627/s   -- -16%
    fast 89286/s  20%   --

    -- get_date
            Rate orig fast
    orig 34884/s   -- -14%
    fast 40541/s  16%   --

    -- set_date
            Rate orig fast
    orig 21505/s   -- -19%
    fast 26525/s  23%   --

    -- scan
            Rate orig fast
    orig 57471/s   --  -1%
    fast 57803/s   1%   --

    -- get_header
            Rate orig fast
    orig 120337/s   -- -24%
    fast 157729/s  31%   --

    -- set_header
            Rate orig fast
    orig  79745/s   -- -30%
    fast 113766/s  43%   --

    -- get_content_length
            Rate orig fast
    orig 182482/s   -- -77%
    fast 793651/s 335%   --

    -- as_string
            Rate orig fast
    orig 23753/s   -- -41%
    fast 40161/s  69%   --

=head1 AUTHOR

    Tokuhiro Matsuno E<lt>tokuhirom@gmail.comE<gt>
    Daisuke Maki

=head1 SEE ALSO

L<HTTP::Headers>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
