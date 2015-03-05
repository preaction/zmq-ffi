package ZMQ::FFI::ZMQ2::Socket;

use strict;
use warnings;

use ZMQ::FFI::Common;
use FFI::Platypus;
use FFI::Platypus::Buffer;

use Moo;
use namespace::clean;

with qw(
    ZMQ::FFI::SocketRole
    ZMQ::FFI::ErrorHandler
);

my $FFI_LOADED;

sub BUILD {
    my ($self) = @_;

    unless ($FFI_LOADED) {
        _load_zmq2_ffi($self->soname);
        $FFI_LOADED = 1;
    }

}

sub send {
    my ($self, $msg, $flags) = @_;

    $flags //= 0;

    my $msg_size;
    {
        use bytes;
        $msg_size = length($msg);
    };

    my $msg_ptr = malloc(zmq_msg_t_size);

    $self->check_error(
        'zmq_msg_init_size',
        zmq_msg_init_size($msg_ptr, $msg_size)
    );

    my $msg_data_ptr = zmq_msg_data($msg_ptr);

    $self->check_error(
        'zmq_send',
        zmq_send($self->_socket, $msg_ptr, $flags)
    );

    zmq_msg_close($msg_ptr);
}

sub recv {
    my ($self, $flags) = @_;

    $flags //= 0;

    my $msg_ptr = malloc(zmq_msg_t_size);

    $self->check_error(
        'zmq_msg_init',
        zmq_msg_init($msg_ptr)
    );

    $self->check_error(
        'zmq_recv',
        zmq_recv($self->_socket, $msg_ptr, $flags)
    );

    my $data_ptr = zmq_msg_data($msg_ptr);

    my $msg_size = zmq_msg_size($msg_ptr);
    $self->check_error('zmq_msg_size', $msg_size);

    my $rv;
    if ($msg_size) {
        $rv = buffer_to_scalar($data_ptr, $msg_size);
    }
    else {
        $rv = '';
    }

    zmq_msg_close($msg_ptr);

    return $rv;
}


sub disconnect {
    my ($self) = @_;

    $self->bad_version("disconnect not available in zmq 2.x");
}

sub unbind {
    my ($self) = @_;

    $self->bad_version("unbind not available in zmq 2.x");
}


sub _load_zmq2_ffi {
    my ($soname) = @_;

    $ffi = FFI::Platypus->new( lib => $soname );

    $ffi->attach(
        'zmq_send' => ['pointer', 'pointer', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_recv' => ['pointer', 'pointer', 'int'] => 'int'
    );
}

1;
