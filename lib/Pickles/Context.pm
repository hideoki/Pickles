package Pickles::Context;
use strict;
use base qw(Class::Data::Inheritable);
use Plack::Util;
use Plack::Util::Accessor qw(env stash finished);
use Class::Trigger qw(pre_dispatch post_dispatch pre_render post_render pre_filter post_filter pre_finalize post_finalize);
use String::CamelCase qw(camelize);

__PACKAGE__->mk_classdata(__registered_components => {});
__PACKAGE__->mk_classdata(__plugins => {});

sub register {
    my( $class, $name, $component ) = @_;
    # register class.
    Plack::Util::load_class( $component ) unless ref $component;
    $class->__registered_components->{$name} = $component;
}

sub get {
    my( $self, $name ) = @_;
    return $self->{__components}{$name} if $self->{__components}{$name};
    my $component = $self->__registered_components->{$name};
    if ( ref($component) eq 'CODE' ) {
        $self->{__components}{$name} = $component->();
    }
    else {
        $self->{__components}{$name} = $component;
    }
    $self->{__components}{$name};
}

sub load_plugins {
    my( $class, @plugins ) = @_;
    for my $plugin( @plugins ) {
        my $plugin_class = Plack::Util::load_class( $plugin, 'Pickles::Plugin' );
        $plugin_class->install( $class );
        $class->__plugins->{$plugin} = $plugin_class;
    }
}

sub plugins {
    my $class = shift;
    values %{$class->__plugins};
}

sub has_plugin {
    my( $pkg, $name ) = @_;
    $pkg->__plugins->{$name};
}

sub add_method {
    my( $pkg, $method, $code ) = @_;
    {
        no strict 'refs';
        *{"$pkg\::$method"} = $code;
    }
}

sub new {
    my( $class, $env ) = @_;
    my $self = bless { 
        stash => +{},
        filters => [],
        env => $env,
        __components => {},
        finished => 0,
    }, $class;
    $self;
}

sub appname {
    my $self = shift;
    my $pkg = ref $self ? ref $self : $self;
    $pkg =~ s/::Context$//;
    $pkg;
}

sub request {
    my $self = shift;
    $self->{_request} ||= do {
        my $class = $self->request_class;
        $class->new( $self->env );
    };
}
sub req { shift->request(@_); }

sub response {
    my $self = shift;
    $self->{_response} ||= do {
        my $class = $self->response_class;
        $class->new( 200 );
    };
}
sub res { shift->response(@_); }

# class method
sub config {
    my $self = shift;
    $self->config_class->instance;
}

sub match {
    my $self = shift;
    $self->{_match} ||= $self->dispatcher_class->match( $self->req );
}

sub render {
    my( $self, $view ) = @_;
    $self->call_trigger('pre_render');
    $view ||= $self->view_class;
    unless ( ref $view ) {
        $view = $view->new;
    }
    $self->res->content_type( $view->content_type );
    my $body = $view->render( $self );
    $self->res->body( $body );
    $self->call_trigger('post_render');
    $self->finished(1);
}

sub dispatch {
    my $self = shift;
    $self->_prepare;
    $self->call_trigger('pre_dispatch');
    my $controller_class = $self->controller_class;
    my $action = $self->action;
    unless ( $controller_class && defined $action ) {
        $self->not_found;
        return $self->res->finalize;
    }
    my $args = $self->args;
    my $controller = $controller_class->new;
    $controller->execute( $action, $self, $args );
    $self->call_trigger('post_dispatch');
    # return PSGI response.
    $self->finalize;
}

sub not_found {
    my $c = shift;
    $c->res->content_type('text/html');
    $c->res->body(<<'HTML');
<html>
<head>
<title>404 Not Found</title>
</head>
<body>
<h1>404 File Not Found</h1>
</body>
</html>
HTML
    
}

sub _prepare {
    my $self = shift;
    my $path = $self->req->path_info;
    $path .= 'index' if $path =~ m{/$};
    $path =~ s{^/}{};
    $self->stash->{template} = $path. '.html';
}

sub apply_filters {
    my $self = shift;
    $self->call_trigger('pre_filter');
    if ( @{$self->{filters}} ) {
        my $body = $self->res->body;
        for my $filter( @{$self->{filters}} ) {
            $body = $filter->( $body, $self );
        }
        $self->res->body( $body );
    }
    $self->call_trigger('post_filter');
}

sub finalize {
    my $self = shift;
    $self->call_trigger('pre_finalize');
    unless ( $self->finished ) {
        $self->render;
    }
    $self->apply_filters;
    my $result = $self->res->finalize;
    $self->call_trigger('post_finalize');
    $result;
}

sub uri_for {
    my( $self, @args ) = @_;
    my $req = $self->req;
    my $uri = $req->base;
    my $params =
        ( scalar @args && ref $args[$#args] eq 'HASH' ? pop @args : {} );
    my $path = ( $args[0] =~ m{^/} ) ? shift @args : $uri->path;
    my @path_segments = grep { $_ } map {
        split /\//, $_
    } ($path, @args);
    $uri->path_segments( @path_segments );
    $uri->query_form( %$params ) if $params;
    $uri;
}


sub redirect {
    my( $self, $url, $code ) = @_;
    $code ||= 302;
    $self->res->status( $code );
    $url = ($url =~ m{^https?://}) ? $url : $self->uri_for( $url );
    $self->res->headers( Location => $url );
    $self->finished(1);
}

sub controller_class {
    my $self = shift;
    my $match = $self->match;
    my $controller = $match->{controller};
    my $class = eval {
        Plack::Util::load_class(
            'Controller::'. camelize( $match->{controller} ), 
            $self->appname
        );
    };
    $class;
}

sub action {
    my $self = shift;
    my $match = $self->match;
    $match->{action};
}

sub args {
    my $self = shift;
    my $match = $self->match;
    $match->{args};
}

sub add_filter {
    my( $self, $code ) = @_;
    push @{$self->{filters}}, $code;
}

sub request_class {
    Plack::Util::load_class( 'Pickles::Request' );
}

sub response_class {
    Plack::Util::load_class( 'Pickles::Response' );
}

sub dispatcher_class {
    my $self = shift;
    Plack::Util::load_class( 'Dispatcher', $self->appname );
}

sub config_class {
    my $self = shift;
    Plack::Util::load_class( 'Config', $self->appname );
}

sub view_class {
    my $self = shift;
    Plack::Util::load_class( 'View', $self->appname );
}

1;

__END__