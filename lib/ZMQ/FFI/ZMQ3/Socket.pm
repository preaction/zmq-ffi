package ZMQ::FFI::ZMQ3::Socket;

use FFI::Platypus;
use FFI::Platypus::Buffer;
use FFI::Platypus::Memory qw(malloc free memcpy);
use ZMQ::FFI::Constants qw(:all);
use Carp;
use Try::Tiny;

use Moo;
use namespace::clean;

no if $] >= 5.018, warnings => "experimental";
use feature 'switch';

with qw(
    ZMQ::FFI::SocketRole
    ZMQ::FFI::ErrorHandler
    ZMQ::FFI::Versioner
);

my $FFI_LOADED;

sub BUILD {
    my ($self) = @_;

    unless ($FFI_LOADED) {
        _load_common_ffi($self->soname);
        _load_zmq3_ffi($self->soname);
        $FFI_LOADED = 1;
    }

    try {
        my $s = zmq_socket($self->ctx->_ctx, $self->type);
        $self->_socket($s);
        $self->check_null('zmq_socket', $self->_socket);
    }
    catch {
        $self->_socket(-1);
        die $_;
    };

    # ensure clean edge state
    while ( $self->has_pollin ) {
        $self->recv();
    }
}

### ZMQ3 API ###

sub _load_zmq3_ffi {
    my ($soname) = @_;

    my $ffi    = FFI::Platypus->new( lib => $soname );

    $ffi->attach(
        'zmq_send' => ['pointer', 'pointer', 'size_t', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_msg_recv' => ['pointer', 'pointer', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_unbind' => ['pointer', 'string'] => 'int'
    );

    $ffi->attach(
        'zmq_disconnect' => ['pointer', 'string'] => 'int'
    );
}

sub send {
    # my ($self, $msg, $flags) = @_;

    use bytes;
    my ($data, $data_size) = scalar_to_buffer($_[1]);
    no bytes;

    if ( -1 == zmq_send($_[0]->_socket, $data, $data_size, ($_[2] // 0)) ) {
        $_[0]->fatal('zmq_send');
    }
}

sub recv {
    # my ($self, $flags) = @_;

    my $msg_ptr = malloc zmq_msg_t_size;

    if ( -1 == zmq_msg_init($msg_ptr) ) {
        $_[0]->fatal('zmq_msg_init');
    }

    my $msg_size = zmq_msg_recv($msg_ptr, $_[0]->_socket, $_[1] // 0);

    my $rv = '';
    if ( $msg_size == -1 ) {
        $_[0]->fatal('zmq_msg_recv');
    }
    elsif ($msg_size) {
        $rv = buffer_to_scalar(zmq_msg_data($msg_ptr), $msg_size);
    }

    zmq_msg_close($msg_ptr);
    return $rv;
}

sub disconnect {
    my ($self, $endpoint) = @_;

    unless ($endpoint) {
        croak 'usage: $socket->disconnect($endpoint)';
    }

    $self->check_error(
        'zmq_disconnect',
        $self->_zmq3_ffi->{zmq_disconnect}->($self->_socket, $endpoint)
    );
}

sub unbind {
    my ($self, $endpoint) = @_;

    unless ($endpoint) {
        croak 'usage: $socket->unbind($endpoint)';
    }

    $self->check_error(
        'zmq_unbind',
        $self->_zmq3_ffi->{zmq_unbind}->($self->_socket, $endpoint)
    );
}

### ZMQ COMMON API ###

sub connect {
    my ($self, $endpoint) = @_;

    unless ($endpoint) {
        croak 'usage: $socket->connect($endpoint)';
    }

    $self->check_error(
        'zmq_connect',
        zmq_connect($self->_socket, $endpoint)
    );
}

sub bind {
    my ($self, $endpoint) = @_;

    unless ($endpoint) {
        croak 'usage: $socket->bind($endpoint)'
    }

    $self->check_error(
        'zmq_bind',
        zmq_bind($self->_socket, $endpoint)
    );
}

sub send_multipart {
    my ($self, $partsref, $flags) = @_;

    my @parts = @{$partsref // []};
    unless (@parts) {
        croak 'usage: send_multipart($parts, $flags)';
    }

    $flags //= 0;

    for my $i (0..$#parts-1) {
        $self->send($parts[$i], $flags | ZMQ_SNDMORE);
    }

    $self->send($parts[$#parts], $flags);
}

sub recv_multipart {
    my ($self, $flags) = @_;

    my @parts = ( $self->recv($flags) );

    my ($major) = $self->version;
    my $type    = $major == 2 ? 'int64_t' : 'int';

    while ( $self->get(ZMQ_RCVMORE, $type) ){
        push @parts, $self->recv($flags);
    }

    return @parts;
}

sub get_fd {
    my $self = shift;

    return $self->get(ZMQ_FD, 'int');
}

sub set_linger {
    my ($self, $linger) = @_;

    $self->set(ZMQ_LINGER, 'int', $linger);
}

sub get_linger {
    return shift->get(ZMQ_LINGER, 'int');
}

sub set_identity {
    my ($self, $id) = @_;

    $self->set(ZMQ_IDENTITY, 'binary', $id);
}

sub get_identity {
    return shift->get(ZMQ_IDENTITY, 'binary');
}

sub subscribe {
    my ($self, $topic) = @_;

    $self->set(ZMQ_SUBSCRIBE, 'binary', $topic);
}

sub unsubscribe {
    my ($self, $topic) = @_;

    $self->set(ZMQ_UNSUBSCRIBE, 'binary', $topic);
}

sub has_pollin {
    my $self = shift;

    my $zmq_events = $self->get(ZMQ_EVENTS, 'int');
    return $zmq_events & ZMQ_POLLIN;
}

sub has_pollout {
    my $self = shift;

    my $zmq_events = $self->get(ZMQ_EVENTS, 'int');
    return $zmq_events & ZMQ_POLLOUT;
}

sub get {
    my ($self, $opt, $opt_type) = @_;

    my $optval;
    my $optval_len;

    for ($opt_type) {
        when (/^(binary|string)$/) {
            my $optval_ptr = malloc(256);
            $optval_len    = 256;

            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_binary(
                    $self->_socket,
                    $opt,
                    $optval_ptr,
                    \$optval_len
                )
            );

            $optval = buffer_to_scalar($optval_ptr, $optval_len);
            free($optval_ptr);
        }

        when (/^int$/) {
            $optval_len = FFI::Platypus->new()->sizeof('int');
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_int(
                    $self->_socket,
                    $opt,
                    \$optval,
                    \$optval_len
                )
            );
        }

        when (/^int64_t$/) {
            $optval_len = FFI::Platypus->new()->sizeof('sint64');
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_int64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    \$optval_len
                )
            );
        }

        when (/^uint64_t$/) {
            $optval_len = FFI::Platypus->new()->sizeof('uint64');
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_uint64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    \$optval_len
                )
            );
        }

        default {
            croak "unknown type $opt_type";
        }
    }

    return if $optval eq '';
    return $optval;
}

sub set {
    my ($self, $opt, $opt_type, $optval) = @_;

    for ($opt_type) {
        when (/^(binary|string)$/) {
            my ($optval_ptr, $optval_len) = scalar_to_buffer($optval);
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_binary(
                    $self->_socket,
                    $opt,
                    $optval_ptr,
                    $optval_len
                )
            );
        }

        when (/^int$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_int(
                    $self->_socket,
                    $opt,
                    \$optval,
                    FFI::Platypus->new()->sizeof('int')
                )
            );
        }

        when (/^int64_t$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_int64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    FFI::Platypus->new()->sizeof('sint64')
                )
            );
        }

        when (/^uint64_t$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_uint64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    FFI::Platypus->new()->sizeof('uint64')
                )
            );
        }

        default {
            croak "unknown type $opt_type";
        }
    }

    return;
}

sub close {
    my $self = shift;

    $self->check_error(
        'zmq_close',
        zmq_close($self->_socket)
    );

    $self->_socket(-1);
}

sub DEMOLISH {
    my ($self) = @_;

    unless ($self->_socket == -1) {
        $self->close();
    }
};

1;

