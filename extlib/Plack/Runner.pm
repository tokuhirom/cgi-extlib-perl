package Plack::Runner;
use strict;
use warnings;
use Carp ();
use Plack::Util;
use Try::Tiny;

sub new {
    my $class = shift;
    bless {
        env      => $ENV{PLACK_ENV},
        loader   => 'Plack::Loader',
        includes => [],
        modules  => [],
        @_,
    }, $class;
}

# delay the build process for reloader
sub build(&;$) {
    my $block = shift;
    my $app   = shift || sub { };
    return sub { $block->($app->()) };
}

sub parse_options {
    my $self = shift;

    local @ARGV = @_;

    # From 'prove': Allow cuddling the paths with -I and -M
    @ARGV = map { /^(-[IM])(.+)/ ? ($1,$2) : $_ } @ARGV;

    my($host, $port, $socket, @listen);

    require Getopt::Long;
    Getopt::Long::Configure("no_ignore_case", "pass_through");
    Getopt::Long::GetOptions(
        "a|app=s"      => \$self->{app},
        "o|host=s"     => \$host,
        "p|port=i"     => \$port,
        "s|server=s"   => \$self->{server},
        "S|socket=s"   => \$socket,
        'l|listen=s@'  => \@listen,
        'D|daemonize'  => \$self->{daemonize},
        "E|env=s"      => \$self->{env},
        "e=s"          => \$self->{eval},
        'I=s@'         => $self->{includes},
        'M=s@'         => $self->{modules},
        'r|reload'     => sub { $self->{loader} = "Restarter" },
        'R|Reload=s'   => sub { $self->{loader} = "Restarter"; $self->loader->watch(split ",", $_[1]) },
        'L|loader=s'   => \$self->{loader},
        "h|help",      => \$self->{help},
    );

    my(@options, @argv);
    while (defined($_ = shift @ARGV)) {
        if (s/^--?//) {
            my @v = split '=', $_, 2;
            $v[0] =~ tr/-/_/;
            if (@v == 2) {
                push @options, @v;
            } else {
                push @options, @v, shift @ARGV;
            }
        } else {
            push @argv, $_;
        }
    }

    push @options, $self->mangle_host_port_socket($host, $port, $socket, @listen);
    push @options, daemonize => 1 if $self->{daemonize};

    $self->{options} = \@options;
    $self->{argv}    = \@argv;
}

sub set_options {
    my $self = shift;
    push @{$self->{options}}, @_;
}

sub mangle_host_port_socket {
    my($self, $host, $port, $socket, @listen) = @_;

    for my $listen (reverse @listen) {
        if ($listen =~ /:\d+$/) {
            ($host, $port) = split /:/, $listen, 2;
            $host = undef if $host eq '';
        } else {
            $socket ||= $listen;
        }
    }

    unless (@listen) {
        if ($socket) {
            @listen = ($socket);
        } else {
            $port ||= 5000;
            @listen = ($host ? "$host:$port" : ":$port");
        }
    }

    return host => $host, port => $port, listen => \@listen, socket => $socket;
}

sub setup {
    my $self = shift;

    if ($self->{help}) {
        require Pod::Usage;
        Pod::Usage::pod2usage(0);
    }

    lib->import(@{$self->{includes}}) if @{$self->{includes}};

    if ($self->{eval}) {
        push @{$self->{modules}}, 'Plack::Builder';
    }

    for (@{$self->{modules}}) {
        my($module, @import) = split /[=,]/;
        eval "require $module" or die $@;
        $module->import(@import);
    }
}

sub locate_app {
    my($self, @args) = @_;

    my $psgi = $self->{app} || $args[0];

    if (ref $psgi eq 'CODE') {
        return sub { $psgi };
    }

    if ($self->{eval}) {
        $self->loader->watch("lib");
        return build {
            no strict;
            no warnings;
            my $eval = "builder { $self->{eval};";
            $eval .= "Plack::Util::load_psgi(\$psgi);" if $psgi;
            $eval .= "}";
            eval $eval or die $@;
        };
    }

    $psgi ||= "app.psgi";

    require File::Basename;
    $self->loader->watch( File::Basename::dirname($psgi) . "/lib", $psgi );
    build { Plack::Util::load_psgi $psgi };
}

sub watch {
    my($self, @dir) = @_;

    push @{$self->{watch}}, @dir
        if $self->{loader} eq 'Restarter';
}

sub prepare_devel {
    my($self, $app) = @_;

    require Plack::Middleware::StackTrace;
    require Plack::Middleware::AccessLog;
    $app = build { Plack::Middleware::StackTrace->wrap($_[0]) } $app;
    unless ($ENV{GATEWAY_INTERFACE}) {
        $app = build { Plack::Middleware::AccessLog->wrap($_[0], logger => sub { print STDERR @_ }) } $app;
    }

    push @{$self->{options}}, server_ready => sub {
        my($args) = @_;
        my $name = $args->{server_software} || ref($args); # $args is $server
        my $host = $args->{host} || 0;
        print STDERR "$name: Accepting connections at http://$host:$args->{port}/\n";
    };

    $app;
}

sub loader {
    my $self = shift;
    $self->{_loader} ||= Plack::Util::load_class($self->{loader}, 'Plack::Loader')->new;
}

sub load_server {
    my($self, $loader) = @_;

    if ($self->{server}) {
        return $loader->load($self->{server}, @{$self->{options}});
    } else {
        return $loader->auto(@{$self->{options}});
    }
}

sub run {
    my $self = shift;

    unless (ref $self) {
        $self = $self->new;
        $self->parse_options(@_);
        return $self->run;
    }

    my @args = @_ ? @_ : @{$self->{argv}};

    $self->setup;

    my $app = $self->locate_app(@args);

    $ENV{PLACK_ENV} ||= $self->{env} || 'development';
    if ($ENV{PLACK_ENV} eq 'development') {
        $app = $self->prepare_devel($app);
    }

    my $loader = $self->loader;
    $loader->preload_app($app);

    my $server = $self->load_server($loader);
    $loader->run($server);
}

1;

__END__

=head1 NAME

Plack::Runner - plackup core

=head1 SYNOPSIS

  # Your bootstrap script
  use Plack::Runner;
  my $app = sub { ... };

  my $runner = Plack::Runner->new;
  $runner->parse_options(@ARGV);
  $runner->run($app);

=head1 DESCRIPTION

Plack::Runner is the core of L<plackup> runner script. You can create
your own frontend to run your application or framework, munge command
line options and pass that to C<run> method of this class.

C<run> method does exactly the same thing as the L<plackup> script
does, but one notable addition is that you can pass a PSGI application
code reference directly with C<--app> option, rather than via C<.psgi>
file path or with C<-e> switch. This would be useful if you want to
make an installable PSGI application.

Also, when C<-h> or C<--help> switch is passed, the usage text is
automatically extracted from your own script using L<Pod::Usage>.

=head1 NOTES

Do not directly call this module from your C<.psgi>, since that makes
your PSGI application unnecessarily depend on L<plackup> and won't run
other backends like L<Plack::Handler::Apache2> or mod_psgi.

If you I<really> want to make your C<.psgi> runnable as a standalone
script, you can do this:

  # foo.psgi
  if (__FILE__ eq $0) {
      require Plack::Runner;
      Plack::Runner->run(@ARGV, $0);
  }

  # This should always come last
  my $app = sub { ... };

=head1 SEE ALSO

L<plackup>

=cut


